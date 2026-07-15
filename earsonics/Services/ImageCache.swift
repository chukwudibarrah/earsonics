// Services/ImageCache.swift
import UIKit
import CryptoKit

/// Shared cover-art cache. Artwork is keyed by the Subsonic cover-art id and
/// requested size — deliberately NOT by URL, because `SubsonicClient` adds a
/// fresh random auth salt to every request, which would make each URL unique
/// and defeat any URL-based (`URLCache`) caching. Caching by id+size means a
/// cover is downloaded once and then served instantly from memory, and from
/// disk across launches.
///
/// An `actor` so decoding and disk I/O happen off the main thread, and so
/// concurrent requests for the same image are coalesced into one download.
actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    /// Dedicated session so artwork downloads don't share a connection pool with
    /// API requests (which would let a burst of covers stall library calls, and
    /// vice-versa). We do our own on-disk caching, so URLCache is disabled.
    /// The short timeout only detects dead pooled connections; the retry in
    /// `image(for:size:)` then runs on a fresh connection with the default
    /// (60s) timeout, so a slow server still gets to deliver.
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = nil
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("CoverArt", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Returns the cover art for `id` at `size`, fetching and caching it if
    /// necessary. Returns `nil` if the id is unusable or the download fails.
    func image(for id: String, size: Int) async -> UIImage? {
        let key = "\(id)-\(size)"

        // 1. Memory
        if let cached = memory.object(forKey: key as NSString) { return cached }

        // 2. Coalesce concurrent requests for the same key
        if let existing = inFlight[key] { return await existing.value }

        let task = Task<UIImage?, Never> { [directory, session] in
            // 3. Disk
            let fileURL = directory.appendingPathComponent(Self.filename(for: key))
            if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
                return image
            }
            // 4. Network. A pooled connection can be silently dead after the
            // app idles or is suspended, so a network failure gets one retry
            // on a brand-new single-use session — a guaranteed-fresh
            // connection, which is what "back out and reopen" achieved by
            // hand. The retry keeps the default 60s timeout so artwork a slow
            // server takes a while to produce arrives late rather than never.
            guard let url = SubsonicClient.shared.coverArtURL(id: id, size: size) else { return nil }
            do {
                return try await Self.download(url, with: session, storingAt: fileURL)
            } catch let error as URLError where error.code != .cancelled {
                let cfg = URLSessionConfiguration.ephemeral
                cfg.urlCache = nil
                let fresh = URLSession(configuration: cfg)
                defer { fresh.finishTasksAndInvalidate() }
                return try? await Self.download(url, with: fresh, storingAt: fileURL)
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil

        if let image { memory.setObject(image, forKey: key as NSString) }
        return image
    }

    /// Total size of the on-disk artwork cache, in bytes.
    func diskUsage() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    /// Empties both the in-memory and on-disk artwork caches.
    func clear() {
        memory.removeAllObjects()
        if let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) {
            files.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    /// Downloads and decodes one cover, persisting it to disk on success.
    /// Throws only for network-level failures (the caller's cue to retry on a
    /// fresh connection); an HTTP error or undecodable body returns nil.
    private static func download(_ url: URL, with session: URLSession, storingAt fileURL: URL) async throws -> UIImage? {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
        guard let image = UIImage(data: data) else { return nil }
        try? data.write(to: fileURL, options: .atomic)
        return image
    }

    /// Stable, filesystem-safe filename derived from the cache key.
    private static func filename(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
