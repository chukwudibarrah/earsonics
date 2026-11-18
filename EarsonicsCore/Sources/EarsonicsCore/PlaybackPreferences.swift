// EarsonicsCore/PlaybackPreferences.swift
import Foundation

/// User preferences for the play queue, read live from UserDefaults by the
/// player and bound by the Settings screen through `@AppStorage` (same keys).
public enum PlaybackPreferences: Sendable {
    public static let crossfadeKey = "crossfadeDuration"
    public static let syncQueueKey = "syncQueueWithServer"
    public static let launchBehaviourKey = "queueLaunchBehaviour"
    public static let afterAlbumKey = "continuationAfterAlbum"
    public static let afterPlaylistKey = "continuationAfterPlaylist"

    /// Save the queue to the server so other Subsonic apps (and other Apple
    /// TVs) can pick up where you left off. On by default.
    public static var syncQueueWithServer: Bool {
        // `bool(forKey:)`, not `object(forKey:) as? Bool`: a value supplied
        // as a string ("NO", e.g. from a launch argument) isn't a Bool and
        // would silently read as the default.
        UserDefaults.standard.object(forKey: syncQueueKey) == nil
            ? true : UserDefaults.standard.bool(forKey: syncQueueKey)
    }

    public static var launchBehaviour: QueueLaunchBehaviour {
        UserDefaults.standard.string(forKey: launchBehaviourKey)
            .flatMap(QueueLaunchBehaviour.init(rawValue:)) ?? .restorePaused
    }

    /// What plays when this queue runs out. A genre mix carries on with more
    /// from its genre, unless the user chose to stop after mixes.
    public static func continuation(for context: PlayContext) -> QueueContinuation {
        let chosen = continuation(for: context.group)
        return context.genreName != nil && chosen != .stop ? .sameGenre : chosen
    }

    /// What plays when a queue from this kind of source runs out.
    public static func continuation(for group: PlayContext.Group) -> QueueContinuation {
        switch group {
        case .albums:
            return UserDefaults.standard.string(forKey: afterAlbumKey)
                .flatMap(QueueContinuation.init(rawValue:)) ?? QueueContinuation.defaultAfterAlbum
        case .playlistsAndMixes:
            return UserDefaults.standard.string(forKey: afterPlaylistKey)
                .flatMap(QueueContinuation.init(rawValue:)) ?? QueueContinuation.defaultAfterPlaylist
        }
    }
}

/// What happens to the saved queue when the app starts (or a server is
/// switched to).
public nonisolated enum QueueLaunchBehaviour: String, CaseIterable, Identifiable, Sendable {
    case restorePaused
    case resumePlaying
    case startFresh

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .restorePaused: return "Restore queue, paused"
        case .resumePlaying: return "Restore queue and keep playing"
        case .startFresh:    return "Start with an empty queue"
        }
    }
}

/// What plays after the last song of a queue.
public nonisolated enum QueueContinuation: String, CaseIterable, Identifiable, Sendable {
    case stop
    case similarSongs
    case sameArtist
    case similarArtists
    case sameGenre
    case random

    public var id: String { rawValue }

    public static let defaultAfterAlbum: QueueContinuation = .stop
    public static let defaultAfterPlaylist: QueueContinuation = .similarSongs

    public var displayName: String {
        switch self {
        case .stop:           return "Stop"
        case .similarSongs:   return "Similar songs"
        case .sameArtist:     return "More from the same artist"
        case .similarArtists: return "Similar artists"
        case .sameGenre:      return "Same genre"
        case .random:         return "Random songs"
        }
    }
}
