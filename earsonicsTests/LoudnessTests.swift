import AVFoundation
import Foundation
import Testing
@testable import earsonics
@testable import EarsonicsCore

/// Interleaved samples of a sine (the same in every channel).
private func sine(frequency: Double = 997, amplitude: Double, seconds: Double,
                  sampleRate: Double = 48_000, channels: Int = 1) -> [Float] {
    let frames = Int(seconds * sampleRate)
    var samples = [Float](repeating: 0, count: frames * channels)
    for frame in 0..<frames {
        let value = Float(amplitude * sin(2 * .pi * frequency * Double(frame) / sampleRate))
        for channel in 0..<channels { samples[frame * channels + channel] = value }
    }
    return samples
}

private func loudness(_ samples: [Float], sampleRate: Double = 48_000, channels: Int = 1,
                      dualMono: Bool = false) -> Double? {
    var meter = LoudnessMeter(sampleRate: sampleRate, channelCount: channels, dualMono: dualMono)
    samples.withUnsafeBufferPointer { meter.process(interleaved: $0) }
    return meter.integratedLoudness
}

@Suite("Loudness measurement (BS.1770)")
struct LoudnessMeterTests {
    /// The standard's calibration: a 0 dBFS ~1 kHz sine in one channel reads
    /// −3.01 LUFS.
    @Test func fullScaleToneInOneChannel() throws {
        let value = try #require(loudness(sine(amplitude: 1, seconds: 5)))
        #expect(abs(value - -3.01) < 0.05, "\(value)")
    }

    @Test func fullScaleToneInBothChannels() throws {
        let value = try #require(loudness(sine(amplitude: 1, seconds: 5, channels: 2), channels: 2))
        #expect(abs(value - 0.0) < 0.05, "\(value)")
    }

    @Test func levelsScaleInDecibels() throws {
        let value = try #require(loudness(sine(amplitude: 0.1, seconds: 5)))
        #expect(abs(value - -23.01) < 0.05, "\(value)")
    }

    /// The filter coefficients are derived per sample rate.
    @Test(arguments: [44_100.0, 96_000.0])
    func otherSampleRates(_ rate: Double) throws {
        let value = try #require(loudness(sine(amplitude: 1, seconds: 5, sampleRate: rate), sampleRate: rate))
        #expect(abs(value - -3.01) < 0.05, "\(value) at \(rate) Hz")
    }

    /// Mono songs play through both TV speakers, so they count as dual mono.
    @Test func dualMonoMatchesStereo() throws {
        let value = try #require(loudness(sine(amplitude: 1, seconds: 5), dualMono: true))
        #expect(abs(value - 0.0) < 0.05, "\(value)")
    }

    @Test func silenceAndTooShortHaveNoLoudness() {
        #expect(loudness([Float](repeating: 0, count: 48_000 * 5)) == nil)
        #expect(loudness(sine(amplitude: 1, seconds: 0.3)) == nil)
    }

    /// Silence between tracks (absolute gate) and much quieter passages
    /// (relative gate) don't drag the result down.
    @Test func gatingIgnoresSilenceAndQuietPassages() throws {
        let tone = sine(amplitude: 0.5, seconds: 5)
        let alone = try #require(loudness(tone))
        let withSilence = try #require(loudness(tone + [Float](repeating: 0, count: 48_000 * 5)))
        let withQuiet = try #require(loudness(tone + sine(amplitude: 0.005, seconds: 5)))
        // The few 400 ms blocks straddling the join are partly tone, pass
        // the gates and count (as the standard intends), pulling the result
        // ~0.13 dB lower. Without the gates it would be ~3 dB lower.
        #expect(abs(withSilence - alone) < 0.25, "\(withSilence) vs \(alone)")
        #expect(abs(withQuiet - alone) < 0.25, "\(withQuiet) vs \(alone)")
    }

    @Test func gainIsRelativeToTheReplayGainReference() {
        #expect(LoudnessMeasurement(integratedLUFS: -9).gain == -9)
        #expect(LoudnessMeasurement(integratedLUFS: -23).gain == 5)
    }
}

@Suite("Measuring an audio file")
struct LoudnessFileTests {
    private func writeWAV(amplitude: Double, channels: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("loudness-\(UUID().uuidString).wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: AVAudioChannelCount(channels)))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(44_100 * 3)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<channels {
            let data = try #require(buffer.floatChannelData?[channel])
            for frame in 0..<Int(frames) {
                data[frame] = Float(amplitude * sin(2 * .pi * 997 * Double(frame) / 44_100))
            }
        }
        try file.write(from: buffer)
        return url
    }

    @Test func stereoFile() async throws {
        let url = try writeWAV(amplitude: 0.5, channels: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let measured = try #require(try await LoudnessAnalysis.measure(fileURL: url))
        #expect(abs(measured.integratedLUFS - -6.02) < 0.1, "\(measured.integratedLUFS)")
    }

    @Test func monoFileCountsAsBothSpeakers() async throws {
        let url = try writeWAV(amplitude: 0.5, channels: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let measured = try #require(try await LoudnessAnalysis.measure(fileURL: url))
        #expect(abs(measured.integratedLUFS - -6.02) < 0.1, "\(measured.integratedLUFS)")
    }

    @Test func notAudioIsNotMeasured() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("not-audio-\(UUID().uuidString).mp3")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let measured = try? await LoudnessAnalysis.measure(fileURL: url)
        #expect(measured == nil)
    }

    @MainActor
    @Test func theStoreMeasuresOnceAndReports() async throws {
        let url = try writeWAV(amplitude: 0.5, channels: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LoudnessStore(fileURL: nil)
        let serverID = UUID()
        var reported: [String] = []
        store.onMeasured = { songId, _ in reported.append(songId) }

        store.measureIfNeeded(fileURL: url, songId: "s1", serverID: serverID)
        store.measureIfNeeded(fileURL: url, songId: "s1", serverID: serverID)   // already queued
        for _ in 0..<100 where store.measurement(songId: "s1", serverID: serverID) == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let measured = try #require(store.measurement(songId: "s1", serverID: serverID))
        #expect(abs(measured.integratedLUFS - -6.02) < 0.1)
        #expect(reported == ["s1"])
        // Per server: the same song id on another server isn't measured.
        #expect(store.measurement(songId: "s1", serverID: UUID()) == nil)
    }
}

@Suite("Choosing each song's volume")
struct VolumeNormalisationTests {
    private func song(trackGain: Double? = nil, albumGain: Double? = nil) throws -> Song {
        var replayGain = ""
        if trackGain != nil || albumGain != nil {
            let fields = [trackGain.map { "\"trackGain\": \($0)" }, albumGain.map { "\"albumGain\": \($0)" }]
                .compactMap { $0 }.joined(separator: ", ")
            replayGain = ", \"replayGain\": {\(fields)}"
        }
        let json = "{\"id\": \"s\", \"title\": \"Song\"\(replayGain)}"
        return try JSONDecoder().decode(Song.self, from: Data(json.utf8))
    }

    private let measured = LoudnessMeasurement(integratedLUFS: -10)   // gain −8 dB

    @Test func tagsWinOverMeasurements() throws {
        let result = VolumeNormalisation.gain(for: try song(trackGain: -6), mode: .track, measured: measured)
        #expect(result.dB == -6 && result.source == .trackTag)
    }

    @Test func albumModeUsesAlbumGainWhenTagged() throws {
        let tagged = try song(trackGain: -6, albumGain: -9)
        #expect(VolumeNormalisation.gain(for: tagged, mode: .album, measured: nil).source == .albumTag)
        #expect(VolumeNormalisation.gain(for: tagged, mode: .album, measured: nil).dB == -9)
        // Track mode ignores album gain.
        #expect(VolumeNormalisation.gain(for: tagged, mode: .track, measured: nil).dB == -6)
        // Album mode without an album tag falls back to the track's own.
        #expect(VolumeNormalisation.gain(for: try song(trackGain: -6), mode: .album, measured: nil).source == .trackTag)
    }

    @Test func untaggedSongsUseTheirMeasurement() throws {
        let result = VolumeNormalisation.gain(for: try song(), mode: .album, measured: LoudnessMeasurement(integratedLUFS: -23))
        #expect(result.dB == 5 && result.source == .measured)
    }

    @Test func unmeasuredUntaggedSongsAreNotPlayedAtFullVolume() throws {
        let result = VolumeNormalisation.gain(for: try song(), mode: .track, measured: nil)
        #expect(result.source == .assumed)
        #expect(VolumeNormalisation.volume(forGain: result.dB) < 0.5)
    }

    /// The old code capped gain at 0 dB, so a quiet song couldn't be turned
    /// up relative to the rest; the headroom makes room for it.
    @Test func quietSongsCanBeTurnedUp() {
        let loud = VolumeNormalisation.volume(forGain: -9)
        let quiet = VolumeNormalisation.volume(forGain: 3)
        #expect(quiet > loud)
        #expect(abs(Double(loud) - pow(10, -13.0 / 20)) < 0.0001)
        #expect(abs(Double(quiet) - pow(10, -1.0 / 20)) < 0.0001)
        // Never above full volume.
        #expect(VolumeNormalisation.volume(forGain: 12) == 1)
    }
}
