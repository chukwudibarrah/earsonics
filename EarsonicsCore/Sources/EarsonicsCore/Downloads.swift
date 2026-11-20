// EarsonicsCore/Downloads.swift
import Foundation
import Observation
import os
import UIKit

/// A downloaded album or playlist (what the user asked to keep offline).
public nonisolated struct DownloadedCollection: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case album, playlist }
    public let kind: Kind
    public let id: String
    public var name: String
    public var artist: String?
    public var coverArt: String?
    public var songIDs: [String]

    public init(kind: Kind, id: String, name: String, artist: String?, coverArt: String?, songIDs: [String]) {
        self.kind = kind; self.id = id; self.name = name; self.artist = artist; self.coverArt = coverArt; self.songIDs = songIDs
    }

    /// Unique within a server: albums and playlists can share ids.
    public var key: String { "\(kind.rawValue):\(id)" }
}

/// One song in the download index: what's wanted, and the file once it's here.
public nonisolated struct DownloadEntry: Codable, Hashable, Sendable {
    public var song: Song
    /// Collection keys, or `DownloadEntry.single`, that want this song kept.
    /// The file is deleted when none are left.
    public var owners: Set<String>
    public var fileName: String
    public var quality: String
    /// Set once the file has arrived.
    public var bytes: Int64?
    public var downloadedAt: Date?

    public static let single = "single"
    public var isDownloaded: Bool { bytes != nil }
}

/// Everything downloaded from one server.
public nonisolated struct DownloadIndex: Codable, Sendable {
    public var entries: [String: DownloadEntry] = [:]
    public var collections: [String: DownloadedCollection] = [:]

    public var totalBytes: Int64 { entries.values.compactMap(\.bytes).reduce(0, +) }
}

/// Downloads for offline listening. Files live in Application Support (kept,
/// unlike the cache), excluded from iCloud backup, under one folder per
/// server. A song shared by two downloaded albums or playlists is stored
/// once and removed only when nothing needs it.
@MainActor @Observable
public final class DownloadStore {
    public static let shared = DownloadStore(
        root: isHostingTests ? FileManager.default.temporaryDirectory.appendingPathComponent("earsonics-test-downloads")
                             : defaultRoot(),
        engine: downloadsHere ? DownloadEngine.shared : nil)

    public enum SongState: Equatable, Sendable {
        case none, waiting, downloading(Double), downloaded, failed
    }

    private let root: URL
    @ObservationIgnored private let engine: DownloadEngine?
    private var indexes: [UUID: DownloadIndex] = [:]
    /// Keyed by `key(songId, serverID)`.
    public private(set) var progress: [String: Double] = [:]
    public private(set) var failed: Set<String> = []
    /// Bumped when saved covers arrive, so covers on screen can look again.
    public private(set) var artworkVersion = 0
    @ObservationIgnored private var fetchingArtwork: Set<String> = []

    /// `engine` nil records requests without downloading (tests).
    public init(root: URL, engine: DownloadEngine?) {
        self.root = root
        self.engine = engine
        engine?.store = self
    }

    // MARK: Reading

    public func index(for serverID: UUID) -> DownloadIndex {
        if let loaded = indexes[serverID] { return loaded }
        let loaded = (try? Data(contentsOf: indexURL(serverID)))
            .flatMap { try? JSONDecoder().decode(DownloadIndex.self, from: $0) } ?? DownloadIndex()
        indexes[serverID] = loaded
        return loaded
    }

    /// The downloaded file for a song, if it's here.
    public func localFile(songId: String, serverID: UUID) -> URL? {
        guard let entry = index(for: serverID).entries[songId], entry.isDownloaded else { return nil }
        let url = fileURL(serverID, entry.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func state(songId: String, serverID: UUID) -> SongState {
        let key = Self.key(songId, serverID)
        guard let entry = index(for: serverID).entries[songId] else { return .none }
        if entry.isDownloaded { return .downloaded }
        if failed.contains(key) { return .failed }
        if let fraction = progress[key] { return .downloading(fraction) }
        return .waiting
    }

    public func collection(_ kind: DownloadedCollection.Kind, id: String, serverID: UUID) -> DownloadedCollection? {
        index(for: serverID).collections["\(kind.rawValue):\(id)"]
    }

    /// How much of a collection has arrived.
    public func completion(of collection: DownloadedCollection, serverID: UUID) -> (done: Int, total: Int) {
        let entries = index(for: serverID).entries
        return (collection.songIDs.filter { entries[$0]?.isDownloaded == true }.count, collection.songIDs.count)
    }

    /// Downloaded songs, in the order they arrived (newest first).
    public func downloadedSongs(serverID: UUID) -> [Song] {
        // By artist, album, then the album's own order (whole albums download
        // in no particular order, so download time isn't useful).
        index(for: serverID).entries.values.filter(\.isDownloaded).map(\.song).sorted {
            let a = ($0.artist ?? "", $0.album ?? ""), b = ($1.artist ?? "", $1.album ?? "")
            if a.0 != b.0 { return a.0.localizedStandardCompare(b.0) == .orderedAscending }
            if a.1 != b.1 { return a.1.localizedStandardCompare(b.1) == .orderedAscending }
            return ($0.discNumber ?? 0, $0.track ?? 0, $0.title) < ($1.discNumber ?? 0, $1.track ?? 0, $1.title)
        }
    }

    // MARK: Changing

    /// Keeps `songs` offline, as an album or playlist when `collection` is
    /// given, otherwise as single songs.
    public func download(_ songs: [Song], as collection: DownloadedCollection? = nil, server: Server) {
        var index = index(for: server.id)
        let owner = collection?.key ?? DownloadEntry.single
        if let collection { index.collections[collection.key] = collection }
        let quality = StreamQuality.forDownloads
        var toStart: [DownloadEntry] = []
        for song in songs {
            if var entry = index.entries[song.id] {
                entry.owners.insert(owner)
                index.entries[song.id] = entry
                if !entry.isDownloaded, failed.remove(Self.key(song.id, server.id)) != nil { toStart.append(entry) }
            } else {
                let ext = AudioCache.fileExtension(quality: quality, songSuffix: song.suffix, contentType: song.contentType) ?? "audio"
                let entry = DownloadEntry(song: song, owners: [owner], fileName: Self.fileName(song.id, ext: ext),
                                          quality: quality.rawValue)
                index.entries[song.id] = entry
                toStart.append(entry)
            }
        }
        indexes[server.id] = index
        save(server.id)
        for entry in toStart { start(entry, server: server) }
        fetchArtwork(server: server)
    }

    /// Stops keeping an album or playlist offline; songs nothing else needs
    /// are deleted.
    public func remove(_ collection: DownloadedCollection, serverID: UUID) {
        var index = index(for: serverID)
        index.collections[collection.key] = nil
        indexes[serverID] = index
        release(owner: collection.key, songIDs: collection.songIDs, serverID: serverID)
    }

    /// Stops keeping a song offline (whether downloaded on its own or as
    /// part of albums and playlists).
    public func remove(songId: String, serverID: UUID) {
        guard let owners = index(for: serverID).entries[songId]?.owners else { return }
        for owner in owners { release(owner: owner, songIDs: [songId], serverID: serverID) }
    }

    public func removeAll(serverID: UUID) {
        Task { await engine?.cancel { $0.serverID == serverID } }
        indexes[serverID] = DownloadIndex()
        try? FileManager.default.removeItem(at: folder(serverID))
        progress = progress.filter { !$0.key.hasPrefix(serverID.uuidString) }
        failed = failed.filter { !$0.hasPrefix(serverID.uuidString) }
    }

    /// Restarts anything still wanted that isn't downloading (e.g. the app was
    /// closed mid-download, or a download failed and should be retried).
    public func resumePending(server: Server) async {
        let running = await engine?.runningJobs() ?? []
        let runningSongs = Set(running.filter { $0.serverID == server.id }.map(\.songID))
        for entry in index(for: server.id).entries.values where !entry.isDownloaded && !runningSongs.contains(entry.song.id) {
            failed.remove(Self.key(entry.song.id, server.id))
            start(entry, server: server)
        }
        fetchArtwork(server: server)
    }

    /// Starts unfinished downloads again, e.g. after "Download over mobile
    /// data" changes, so they follow the new setting.
    public func restartPending(server: Server) {
        guard engine != nil else { return }
        let pending = Set(index(for: server.id).entries.values.filter { !$0.isDownloaded }.map(\.song.id))
        guard !pending.isEmpty else { return }
        let serverID = server.id
        Task {
            // Cancelled first, so the new tasks aren't caught by the cancel.
            await engine?.cancel { $0.serverID == serverID && pending.contains($0.songID) }
            for id in pending {
                guard let entry = index(for: serverID).entries[id], !entry.isDownloaded else { continue }
                failed.remove(Self.key(id, serverID))
                progress[Self.key(id, serverID)] = nil
                start(entry, server: server)
            }
        }
    }

    // MARK: Engine callbacks

    func didProgress(_ job: DownloadJob, fraction: Double) {
        let key = Self.key(job.songID, job.serverID)
        guard index(for: job.serverID).entries[job.songID]?.isDownloaded == false else { return }
        // Whole-percent steps keep redraws down.
        let rounded = (fraction * 100).rounded() / 100
        if progress[key] != rounded { progress[key] = rounded }
    }

    func didFinish(_ job: DownloadJob, bytes: Int64) {
        let key = Self.key(job.songID, job.serverID)
        progress[key] = nil
        var index = index(for: job.serverID)
        guard var entry = index.entries[job.songID] else {
            // Removed while downloading: drop the file.
            try? FileManager.default.removeItem(at: fileURL(job.serverID, job.fileName))
            return
        }
        entry.bytes = bytes
        entry.downloadedAt = .now
        index.entries[job.songID] = entry
        indexes[job.serverID] = index
        save(job.serverID)
    }

    func didFail(_ job: DownloadJob) {
        let key = Self.key(job.songID, job.serverID)
        progress[key] = nil
        if index(for: job.serverID).entries[job.songID] != nil { failed.insert(key) }
    }

    // MARK: Files

    /// Where `DownloadEngine` puts a finished file.
    nonisolated static func destination(root: URL, for job: DownloadJob) -> URL {
        root.appendingPathComponent(job.serverID.uuidString, isDirectory: true).appendingPathComponent(job.fileName)
    }

    private func start(_ entry: DownloadEntry, server: Server) {
        guard let engine,
              let url = SubsonicClient.shared.streamURL(songId: entry.song.id,
                                                        quality: StreamQuality(rawValue: entry.quality) ?? .forDownloads,
                                                        server: server) else { return }
        try? FileManager.default.createDirectory(at: folder(server.id), withIntermediateDirectories: true)
        engine.start(DownloadJob(serverID: server.id, songID: entry.song.id, fileName: entry.fileName), url: url,
                     allowsCellular: UserDefaults.standard.bool(forKey: Self.cellularDownloadsKey))
    }

    private func release(owner: String, songIDs: [String], serverID: UUID) {
        var index = index(for: serverID)
        for id in songIDs {
            guard var entry = index.entries[id] else { continue }
            entry.owners.remove(owner)
            if entry.owners.isEmpty {
                index.entries[id] = nil
                Task { await engine?.cancel { $0.serverID == serverID && $0.songID == id } }
                try? FileManager.default.removeItem(at: fileURL(serverID, entry.fileName))
                progress[Self.key(id, serverID)] = nil
                failed.remove(Self.key(id, serverID))
            } else {
                index.entries[id] = entry
            }
        }
        indexes[serverID] = index
        save(serverID)
        pruneArtwork(serverID)
    }

    // MARK: Artwork

    /// The saved cover for `id`, if something downloaded uses it. Covers are
    /// kept once, at 800 px, for every size they're drawn at.
    public func artworkFile(id: String, serverID: UUID) -> URL? {
        let url = artworkURL(serverID, id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Every cover the server's downloads show: their albums' and
    /// playlists' covers and each song's own.
    func artworkIDs(serverID: UUID) -> Set<String> {
        let index = index(for: serverID)
        return Set(index.collections.values.compactMap(\.coverArt) + index.entries.values.compactMap(\.song.coverArt))
    }

    /// Saves any covers the downloads need that aren't saved yet. Small and
    /// quick, so they use an ordinary session; anything missed (offline, or
    /// waiting for Wi-Fi) is fetched on the next launch or download.
    private func fetchArtwork(server: Server) {
        guard engine != nil else { return }
        let missing = artworkIDs(serverID: server.id).filter { artworkFile(id: $0, serverID: server.id) == nil && !fetchingArtwork.contains($0) }
        guard !missing.isEmpty else { return }
        fetchingArtwork.formUnion(missing)
        let jobs = missing.compactMap { id in
            SubsonicClient.shared.coverArtURL(id: id, size: 800, server: server).map { (id, $0, artworkURL(server.id, id)) }
        }
        let allowsCellular = UserDefaults.standard.bool(forKey: Self.cellularDownloadsKey)
        Task.detached(priority: .utility) {
            for (_, url, destination) in jobs {
                var request = URLRequest(url: url)
                request.allowsExpensiveNetworkAccess = allowsCellular
                request.allowsConstrainedNetworkAccess = allowsCellular
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      (response as? HTTPURLResponse)?.statusCode == 200, UIImage(data: data) != nil else { continue }
                try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: destination, options: .atomic)
            }
            await MainActor.run {
                self.fetchingArtwork.subtract(missing)
                // Removed while fetching: don't keep what nothing needs.
                self.pruneArtwork(server.id)
                self.artworkVersion += 1
            }
        }
    }

    /// Deletes saved covers nothing downloaded uses any more.
    private func pruneArtwork(_ serverID: UUID) {
        let folder = artworkFolder(serverID)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        let keep = Set(artworkIDs(serverID: serverID).map { Self.fileName($0, ext: "img") })
        for file in files where !keep.contains(file) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }

    private func artworkFolder(_ serverID: UUID) -> URL { folder(serverID).appendingPathComponent("Artwork", isDirectory: true) }
    private func artworkURL(_ serverID: UUID, _ id: String) -> URL {
        artworkFolder(serverID).appendingPathComponent(Self.fileName(id, ext: "img"))
    }

    private func save(_ serverID: UUID) {
        guard let index = indexes[serverID], let data = try? JSONEncoder().encode(index) else { return }
        let url = indexURL(serverID)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func folder(_ serverID: UUID) -> URL { root.appendingPathComponent(serverID.uuidString, isDirectory: true) }
    private func fileURL(_ serverID: UUID, _ name: String) -> URL { folder(serverID).appendingPathComponent(name) }
    private func indexURL(_ serverID: UUID) -> URL { folder(serverID).appendingPathComponent("index.json") }

    /// Allow downloads over mobile data (off by default).
    public static let cellularDownloadsKey = "downloadOverCellular"

    static func key(_ songId: String, _ serverID: UUID) -> String { "\(serverID.uuidString)/\(songId)" }

    /// A file name safe for any song id.
    static func fileName(_ songId: String, ext: String) -> String {
        let safe = songId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        return "\(safe).\(ext)"
    }

    private static func defaultRoot() -> URL {
        var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Music the user can download again isn't worth their iCloud space.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    /// The Apple TV app only reads (there's nothing to read), so it never
    /// opens a background session.
    private static var downloadsHere: Bool {
        #if os(tvOS)
        false
        #else
        !isHostingTests
        #endif
    }

    private static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

/// What a download task is for, carried in its task description so it
/// survives the app being closed.
public nonisolated struct DownloadJob: Codable, Hashable, Sendable {
    public let serverID: UUID
    public let songID: String
    public let fileName: String

    var encoded: String { (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? "" }
    init(serverID: UUID, songID: String, fileName: String) {
        self.serverID = serverID; self.songID = songID; self.fileName = fileName
    }
    init?(_ description: String?) {
        guard let data = description?.data(using: .utf8),
              let job = try? JSONDecoder().decode(DownloadJob.self, from: data) else { return nil }
        self = job
    }
}

/// A background URL session, so downloads carry on while the app is in the
/// background or closed; iOS relaunches the app to deliver finished files.
public nonisolated final class DownloadEngine: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let sessionIdentifier = "com.wonderworks.earsonics.downloads"
    public static let shared = DownloadEngine()

    /// Set by the store; callbacks hop to the main actor to reach it.
    @MainActor weak var store: DownloadStore?
    /// On a background relaunch, events can arrive before anything has
    /// opened the store.
    @MainActor private var target: DownloadStore { store ?? .shared }
    private let root: URL
    private var session: URLSession!
    private let eventsDone = OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>(initialState: nil)

    override private init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func start(_ job: DownloadJob, url: URL, allowsCellular: Bool) {
        var request = URLRequest(url: url)
        request.allowsExpensiveNetworkAccess = allowsCellular
        request.allowsConstrainedNetworkAccess = allowsCellular
        let task = session.downloadTask(with: request)
        task.taskDescription = job.encoded
        task.resume()
    }

    func cancel(where matches: @escaping @Sendable (DownloadJob) -> Bool) async {
        for task in await session.allTasks where DownloadJob(task.taskDescription).map(matches) == true { task.cancel() }
    }

    func runningJobs() async -> [DownloadJob] {
        await session.allTasks.compactMap { DownloadJob($0.taskDescription) }
    }

    /// Waits until iOS has delivered every event for a background relaunch
    /// (SwiftUI's `.backgroundTask(.urlSession(...))` awaits this).
    public func backgroundEventsDelivered() async {
        await withCheckedContinuation { continuation in
            eventsDone.withLock { $0 = continuation }
        }
    }

    // MARK: URLSessionDownloadDelegate

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let job = DownloadJob(downloadTask.taskDescription) else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            Task { @MainActor in self.target.didFail(job) }
            return
        }
        // The temporary file is deleted when this returns: move it now.
        let destination = DownloadStore.destination(root: root, for: job)
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.removeItem(at: destination)
        do {
            try fileManager.moveItem(at: location, to: destination)
            let bytes = (try? fileManager.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
            Task { @MainActor in self.target.didFinish(job, bytes: bytes) }
        } catch {
            Task { @MainActor in self.target.didFail(job) }
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let job = DownloadJob(downloadTask.taskDescription) else { return }
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        Task { @MainActor in self.target.didProgress(job, fraction: min(fraction, 1)) }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as? URLError)?.code != .cancelled, let job = DownloadJob(task.taskDescription) else { return }
        Task { @MainActor in self.target.didFail(job) }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let continuation = eventsDone.withLock { value -> CheckedContinuation<Void, Never>? in
            defer { value = nil }
            return value
        }
        continuation?.resume()
    }
}
