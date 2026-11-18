// EarsonicsCore/Loudness.swift
import AVFoundation
import Foundation

/// How loud a song is, measured on the device for songs whose files carry no
/// Replay Gain tags (most libraries are only partly tagged).
public nonisolated struct LoudnessMeasurement: Codable, Hashable, Sendable {
    /// Integrated loudness in LUFS (ITU-R BS.1770-4 / EBU R128).
    public let integratedLUFS: Double

    public init(integratedLUFS: Double) {
        self.integratedLUFS = integratedLUFS
    }

    /// The Replay Gain 2.0 gain for this song, in dB: how far it is from the
    /// −18 LUFS reference that Replay Gain tags use.
    public var gain: Double { LoudnessMeter.referenceLUFS - integratedLUFS }
}

/// Integrated loudness per ITU-R BS.1770-4: K-weighting, 400 ms blocks with
/// 75% overlap, an absolute gate at −70 LUFS and a relative gate 10 LU below
/// the ungated level. Fed interleaved samples in any number of chunks.
public nonisolated struct LoudnessMeter {
    public static let referenceLUFS = -18.0

    /// A biquad filter (transposed direct form II).
    private struct Biquad {
        let b0, b1, b2, a1, a2: Double
        var z1 = 0.0, z2 = 0.0

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    private let channelCount: Int
    private let weights: [Double]
    private var shelves: [Biquad]
    private var highPasses: [Biquad]
    /// 100 ms of samples: four of these make a 400 ms block, and blocks start
    /// every 100 ms (75% overlap).
    private let subBlockLength: Int
    private var subBlockFill = 0
    private var channelSums: [Double]
    /// Channel-weighted mean square of each 100 ms sub-block.
    private var subBlocks: [Double] = []

    /// `dualMono` counts a mono file as playing through both speakers, as it
    /// does on a TV, so it compares fairly with stereo songs.
    public init(sampleRate: Double, channelCount: Int, dualMono: Bool = false) {
        self.channelCount = max(channelCount, 1)
        if channelCount == 6 {
            // 5.1 in the usual order (L R C LFE Ls Rs): no LFE, surrounds +1.5 dB.
            weights = [1, 1, 1, 0, 1.41, 1.41]
        } else if channelCount == 1 && dualMono {
            weights = [2]
        } else {
            weights = Array(repeating: 1, count: self.channelCount)
        }

        // K-weighting for any sample rate (the BS.1770 filters, re-derived as
        // in libebur128). Stage 1: high shelf, about +4 dB above 2 kHz.
        let f0 = 1681.974450955533, gainDB = 3.999843853973347, q = 0.7071752369554196
        var k = tan(Double.pi * f0 / sampleRate)
        let vh = pow(10, gainDB / 20), vb = pow(vh, 0.4996667741545416)
        var a0 = 1 + k / q + k * k
        let shelf = Biquad(b0: (vh + vb * k / q + k * k) / a0,
                           b1: 2 * (k * k - vh) / a0,
                           b2: (vh - vb * k / q + k * k) / a0,
                           a1: 2 * (k * k - 1) / a0,
                           a2: (1 - k / q + k * k) / a0)
        // Stage 2: high pass at about 38 Hz.
        let f1 = 38.13547087602444, q1 = 0.5003270373238773
        k = tan(Double.pi * f1 / sampleRate)
        a0 = 1 + k / q1 + k * k
        let highPass = Biquad(b0: 1, b1: -2, b2: 1,
                              a1: 2 * (k * k - 1) / a0,
                              a2: (1 - k / q1 + k * k) / a0)
        shelves = Array(repeating: shelf, count: self.channelCount)
        highPasses = Array(repeating: highPass, count: self.channelCount)
        subBlockLength = max(Int((sampleRate * 0.1).rounded()), 1)
        channelSums = Array(repeating: 0, count: self.channelCount)
    }

    /// Adds interleaved samples (frame by frame, one sample per channel).
    public mutating func process(interleaved samples: UnsafeBufferPointer<Float>) {
        let frames = samples.count / channelCount
        var index = 0
        for _ in 0..<frames {
            for channel in 0..<channelCount {
                let y = highPasses[channel].process(shelves[channel].process(Double(samples[index])))
                channelSums[channel] += y * y
                index += 1
            }
            subBlockFill += 1
            if subBlockFill == subBlockLength {
                var energy = 0.0
                for channel in 0..<channelCount {
                    energy += weights[channel] * channelSums[channel] / Double(subBlockLength)
                    channelSums[channel] = 0
                }
                subBlocks.append(energy)
                subBlockFill = 0
            }
        }
    }

    /// Integrated loudness in LUFS, or nil for less than 400 ms of audio or
    /// (near) silence.
    public var integratedLoudness: Double? {
        guard subBlocks.count >= 4 else { return nil }
        func lufs(_ energy: Double) -> Double { -0.691 + 10 * log10(energy) }
        var blocks: [Double] = []
        blocks.reserveCapacity(subBlocks.count - 3)
        for i in 0...(subBlocks.count - 4) {
            blocks.append((subBlocks[i] + subBlocks[i + 1] + subBlocks[i + 2] + subBlocks[i + 3]) / 4)
        }
        let aboveAbsolute = blocks.filter { $0 > 0 && lufs($0) > -70 }
        guard !aboveAbsolute.isEmpty else { return nil }
        let relativeGate = lufs(aboveAbsolute.reduce(0, +) / Double(aboveAbsolute.count)) - 10
        let gated = aboveAbsolute.filter { lufs($0) > relativeGate }
        guard !gated.isEmpty else { return nil }
        return lufs(gated.reduce(0, +) / Double(gated.count))
    }
}

/// Measures an audio file's loudness by decoding it to PCM.
public nonisolated enum LoudnessAnalysis {
    public static func measure(fileURL: URL) async throws -> LoudnessMeasurement? {
        let asset = AVURLAsset(url: fileURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first,
              let description = try await track.load(.formatDescriptions).first,
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              format.mSampleRate > 0, format.mChannelsPerFrame > 0 else { return nil }
        let channels = Int(format.mChannelsPerFrame)

        let reader = try AVAssetReader(asset: asset)
        // Same sample rate and channel count as the file; 32-bit float.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }
        defer { if reader.status == .reading { reader.cancelReading() } }

        var meter = LoudnessMeter(sampleRate: format.mSampleRate, channelCount: channels, dualMono: channels == 1)
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let count = length / MemoryLayout<Float>.size
            if samples.count != count { samples = Array(repeating: 0, count: count) }
            let status = samples.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                           destination: bytes.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            samples.withUnsafeBufferPointer { meter.process(interleaved: $0) }
        }
        guard reader.status == .completed else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }
        return meter.integratedLoudness.map(LoudnessMeasurement.init(integratedLUFS:))
    }
}

/// Measurements for songs, per server (song ids are only unique within a
/// server). Songs are measured one at a time in the background, from their
/// cached files. Kept in the Caches folder: if tvOS clears it, songs are
/// simply measured again.
@MainActor
public final class LoudnessStore {
    public static let shared = LoudnessStore(fileURL: LoudnessStore.isHostingTests ? nil : LoudnessStore.defaultFileURL())

    /// Called on the main actor when a song has been measured.
    public var onMeasured: ((_ songId: String, _ serverID: UUID) -> Void)?

    private let fileURL: URL?
    private var measurements: [String: LoudnessMeasurement] = [:]
    private var pending: [(key: String, songId: String, serverID: UUID, file: URL)] = []
    private var queued: Set<String> = []
    /// Files that couldn't be measured this session, so they aren't retried
    /// on every play.
    private var failed: Set<String> = []
    private var worker: Task<Void, Never>?

    /// `fileURL` nil keeps measurements in memory only (tests).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: LoudnessMeasurement].self, from: data) {
            measurements = saved
        }
    }

    public func measurement(songId: String, serverID: UUID) -> LoudnessMeasurement? {
        measurements[Self.key(songId, serverID)]
    }

    /// Queues a song's cached file for measuring, unless it's already
    /// measured, queued, or failed this session.
    public func measureIfNeeded(fileURL file: URL, songId: String, serverID: UUID) {
        let key = Self.key(songId, serverID)
        guard measurements[key] == nil, !queued.contains(key), !failed.contains(key) else { return }
        queued.insert(key)
        pending.append((key, songId, serverID, file))
        startNextIfIdle()
    }

    private func startNextIfIdle() {
        guard worker == nil, !pending.isEmpty else { return }
        let job = pending.removeFirst()
        worker = Task.detached(priority: .background) { [weak self] in
            let result = try? await LoudnessAnalysis.measure(fileURL: job.file)
            await self?.finish(key: job.key, songId: job.songId, serverID: job.serverID, result: result)
        }
    }

    private func finish(key: String, songId: String, serverID: UUID, result: LoudnessMeasurement?) {
        worker = nil
        queued.remove(key)
        if let result {
            measurements[key] = result
            save()
            onMeasured?(songId, serverID)
        } else {
            failed.insert(key)
        }
        startNextIfIdle()
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(measurements) else { return }
        Task.detached(priority: .background) {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func key(_ songId: String, _ serverID: UUID) -> String {
        "\(serverID.uuidString)/\(songId)"
    }

    private static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Loudness", isDirectory: true)
            .appendingPathComponent("measurements.json")
    }

    /// Unit tests run inside the app: keep their measurements out of the
    /// device's saved ones.
    private static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

/// Picks each song's volume: Replay Gain tags from the server when the song
/// has them, otherwise the on-device measurement, otherwise a safe guess.
public nonisolated enum VolumeNormalisation {
    public static let modeKey = "volumeNormalisationMode"

    /// Everything plays this much quieter, so songs quieter than the
    /// reference can be turned up: the player can't go above full volume.
    public static let headroom = -4.0
    /// For songs not yet measured and without tags: about the level of a
    /// modern master, so they don't play much louder than measured songs.
    public static let assumedGain = -8.0

    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        /// Every song at the same level (best for shuffles and mixes).
        case track
        /// An album's songs keep their levels relative to each other, using
        /// album gain tags where the server has them.
        case album

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .track: return "Song by song"
            case .album: return "By album"
            }
        }

        public static var current: Mode {
            UserDefaults.standard.string(forKey: modeKey).flatMap(Mode.init(rawValue:)) ?? .track
        }
    }

    public enum Source: Equatable, Sendable {
        case albumTag, trackTag, measured, assumed
    }

    /// The gain in dB to apply to `song`, and where it came from.
    public static func gain(for song: Song, mode: Mode, measured: LoudnessMeasurement?) -> (dB: Double, source: Source) {
        if mode == .album, let album = song.replayGain?.albumGain { return (album, .albumTag) }
        if let track = song.replayGain?.trackGain { return (track, .trackTag) }
        if let measured { return (measured.gain, .measured) }
        return (assumedGain, .assumed)
    }

    /// Player volume (0…1) for a gain, including the headroom.
    public static func volume(forGain dB: Double) -> Float {
        Float(min(1, pow(10, (dB + headroom) / 20)))
    }
}
