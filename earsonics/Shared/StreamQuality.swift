// Shared/StreamQuality.swift
import Foundation

/// The streaming/cache quality the user selects in Settings. One choice drives
/// both live playback and what gets cached, so a replayed track always matches
/// its first play. All transcoding is server-side via Subsonic `stream.view`
/// params — the app never converts audio itself.
enum StreamQuality: String, CaseIterable, Identifiable {
    case original          // format=raw — the original lossless/library file
    case mp3_320           // server transcode to MP3 @ 320 kbps
    case mp3_192           // server transcode to MP3 @ 192 kbps

    var id: String { rawValue }

    /// `stream.view` query parameters for this quality.
    var streamParams: [URLQueryItem] {
        switch self {
        case .original:
            return [URLQueryItem(name: "format", value: "raw")]
        case .mp3_320:
            return [URLQueryItem(name: "format", value: "mp3"),
                    URLQueryItem(name: "maxBitRate", value: "320"),
                    // Ask the server for an estimated Content-Length; on-the-fly
                    // transcodes are otherwise chunked with no length, which the
                    // player needs in order to schedule playback.
                    URLQueryItem(name: "estimateContentLength", value: "true")]
        case .mp3_192:
            return [URLQueryItem(name: "format", value: "mp3"),
                    URLQueryItem(name: "maxBitRate", value: "192"),
                    URLQueryItem(name: "estimateContentLength", value: "true")]
        }
    }

    /// Short tag used in the cache key so a track cached at one quality is never
    /// served for another.
    var cacheTag: String {
        switch self {
        case .original: return "raw"
        case .mp3_320:  return "mp3-320"
        case .mp3_192:  return "mp3-192"
        }
    }

    /// File extension for the cached copy. `nil` means "use the song's own
    /// suffix" (only the original preserves the source container/codec).
    var fileSuffix: String? {
        switch self {
        case .original: return nil
        case .mp3_320, .mp3_192: return "mp3"
        }
    }

    /// True when the served bytes have a known length and support range
    /// requests (only the original file). Transcoded streams are produced
    /// on the fly with no `Content-Length` and no range support.
    var knownLength: Bool { self == .original }

    var displayName: String {
        switch self {
        case .original: return "Original (lossless)"
        case .mp3_320:  return "MP3 320 kbps"
        case .mp3_192:  return "MP3 192 kbps"
        }
    }

    // MARK: - Settings access

    /// Shared UserDefaults key, read live by the player/cache and bound by the
    /// Settings picker.
    static let defaultsKey = "streamQuality"

    /// Current selection from UserDefaults (defaults to `.original`).
    static var current: StreamQuality {
        let raw = UserDefaults.standard.string(forKey: defaultsKey)
        return raw.flatMap(StreamQuality.init(rawValue:)) ?? .original
    }
}
