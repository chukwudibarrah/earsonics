// Services/QueuePersistence.swift
import Foundation

/// A saved queue and how far into the current song playback had got.
struct QueueSnapshot: Codable, Equatable {
    var queue: PlayQueue
    /// Seconds into the current song.
    var position: Double
    var savedAt: Date
}

/// The on-device copy of each server's queue: one JSON file per server.
///
/// It lives in Caches because tvOS gives apps no guaranteed persistent file
/// storage (UserDefaults is capped at 512 KB, too small for long queues), so
/// the system may purge it. That's acceptable: with sync on, the server keeps
/// the durable copy; this one adds what the server can't store (shuffle,
/// repeat, autoplay labels, where the queue came from) and covers servers or
/// moments without a connection.
enum LocalQueueStore {
    static func directory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("PlayQueues", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileURL(serverID: UUID) -> URL {
        directory().appendingPathComponent("\(serverID.uuidString).json")
    }

    static func load(serverID: UUID) -> QueueSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(serverID: serverID)) else { return nil }
        return try? JSONDecoder().decode(QueueSnapshot.self, from: data)
    }

    /// Encodes on the caller's actor and writes off the main thread.
    static func save(_ snapshot: QueueSnapshot, serverID: UUID) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let url = fileURL(serverID: serverID)
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func delete(serverID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(serverID: serverID))
    }
}

/// Picks which saved queue to restore: the server's or the local copy.
enum QueueRestore {
    /// Our own saves can lag the local copy by a few seconds (the server save
    /// is batched), so a server copy saved by this app only wins if it's
    /// clearly newer — i.e. another Apple TV running earsonics saved it.
    static let ownSaveTolerance: TimeInterval = 30

    /// - The only copy available wins.
    /// - With both, the server's copy wins if it was saved after the local
    ///   one: another app (or another Apple TV) has been playing since.
    ///   Otherwise the local copy wins, because it also keeps shuffle,
    ///   repeat and autoplay labels.
    static func choose(local: QueueSnapshot?, remote: SubsonicClient.RemotePlayQueue?,
                       clientName: String = SubsonicClient.clientName, now: Date = Date()) -> QueueSnapshot? {
        guard let remote, !remote.songs.isEmpty else { return local }
        let remoteSnapshot = QueueSnapshot(
            queue: PlayQueue(entries: remote.songs.map { QueueEntry(song: $0) },
                             currentIndex: remote.currentIndex,
                             repeatMode: local?.queue.repeatMode ?? .off,
                             context: .mix),
            position: remote.position,
            savedAt: remote.changed ?? now)
        guard let local, !local.queue.isEmpty else { return remoteSnapshot }
        guard let changed = remote.changed else { return local }
        let tolerance = remote.changedBy == clientName ? ownSaveTolerance : 0
        return changed > local.savedAt.addingTimeInterval(tolerance) ? remoteSnapshot : local
    }
}
