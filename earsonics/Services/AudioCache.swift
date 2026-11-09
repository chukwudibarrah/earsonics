// Services/AudioCache.swift
import Foundation
import CryptoKit
import UniformTypeIdentifiers

/// On-disk cache of fully-downloaded songs, keyed by song id + quality tag so a
/// track cached at one quality is never served for another. Only complete files
/// are ever stored (see `CachingResourceLoaderDelegate`). Size is bounded by a
/// user-configurable cap with least-recently-used eviction (LRU tracked via file
/// modification dates — no separate index needed).
///
/// An `actor` so disk I/O and eviction happen off the main thread.
actor AudioCache {
    static let shared = AudioCache()

    /// UserDefaults key for the cap, in gigabytes (default 2 GB).
    static let limitKey = "audioCacheLimitGB"
    private static let defaultLimitGB = 2

    private let directory: URL

    init() {
        directory = Self.directoryURL()
    }

    /// The cache directory, creating it if needed. `nonisolated` so the resource
    /// loader can place its temp file on the same volume synchronously (keeping
    /// the final move atomic) without hopping onto the actor.
    nonisolated static func directoryURL() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("AudioCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Returns the cached file URL for a song at a given quality, but only if a
    /// complete file exists. Touches the file's modification date so recently
    /// played tracks survive eviction (LRU). `nonisolated` so the player can
    /// check for a cache hit synchronously when building a player item — it only
    /// touches the (thread-safe) file system, no actor state.
    nonisolated static func cachedFileURL(for songId: String, serverID: UUID, quality: StreamQuality,
                                          fileExtension ext: String?) -> URL? {
        guard let ext, let url = fileURL(songId: songId, serverID: serverID, quality: quality, fileExtension: ext),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return url
    }

    /// Moves a completed download into the cache, then enforces the size cap.
    func store(tempFile: URL, songId: String, serverID: UUID, quality: StreamQuality, fileExtension ext: String?) {
        // Without an extension the file couldn't be played back (see
        // `fileExtension`), so don't keep it.
        guard let ext, let destination = Self.fileURL(songId: songId, serverID: serverID, quality: quality,
                                                      fileExtension: ext) else {
            try? FileManager.default.removeItem(at: tempFile)
            return
        }
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: tempFile, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: tempFile)
            return
        }
        enforceLimit()
    }

    /// Total size of the cache, in bytes.
    func diskUsage() -> Int64 {
        contents().reduce(0) { $0 + $1.size }
    }

    /// Empties the cache.
    func clear() {
        for file in contents() {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    // MARK: - Private

    private func enforceLimit() {
        let gb = UserDefaults.standard.object(forKey: Self.limitKey) as? Int ?? Self.defaultLimitGB
        let cap = Int64(max(gb, 1)) * 1_073_741_824  // GB → bytes
        var files = contents()
        var total = files.reduce(0) { $0 + $1.size }
        guard total > cap else { return }
        // Evict oldest-modified first until under the cap.
        files.sort { $0.modified < $1.modified }
        for file in files where total > cap {
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
        }
    }

    private struct Entry { let url: URL; let size: Int64; let modified: Date }

    private func contents() -> [Entry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys) else { return [] }
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return Entry(url: url,
                         size: Int64(values?.fileSize ?? 0),
                         modified: values?.contentModificationDate ?? .distantPast)
        }
    }

    /// Song ids are only unique within one server (many servers use small
    /// integers), so the key is scoped by server. Files cached before this
    /// scoping are never matched again and age out via LRU eviction.
    private nonisolated static func fileURL(songId: String, serverID: UUID, quality: StreamQuality,
                                           fileExtension ext: String) -> URL? {
        guard !ext.isEmpty else { return nil }
        let key = "\(serverID.uuidString)-\(songId)-\(quality.cacheTag)"
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined() + ".\(ext)"
        return directoryURL().appendingPathComponent(name)
    }

    /// The extension a cached copy is stored under. AVFoundation chooses the
    /// decoder from a local file's extension: without one, the file fails to
    /// open ("Cannot Open") — which is what happened to every Original-quality
    /// replay from 1.06 to 1.08. Transcodes are MP3; originals keep the song's
    /// own format, from its suffix or else its MIME type. Nil (unknown format)
    /// means "don't cache".
    nonisolated static func fileExtension(quality: StreamQuality, songSuffix: String?, contentType: String?) -> String? {
        if let transcoded = quality.fileSuffix { return transcoded }
        let fromSuffix = songSuffix.map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        if let fromSuffix, !fromSuffix.isEmpty, fromSuffix.count <= 5 { return fromSuffix }
        if let mime = contentType, let ext = UTType(mimeType: mime)?.preferredFilenameExtension { return ext }
        return nil
    }

    /// Deletes files cached before 1.09 without an extension: they can't be
    /// played (see `fileExtension`) and would only take up space until
    /// evicted. Leaves in-progress downloads (`.tmp`) alone.
    func removeUnplayableFiles() {
        for file in contents() where file.url.pathExtension.isEmpty {
            try? FileManager.default.removeItem(at: file.url)
        }
    }
}
