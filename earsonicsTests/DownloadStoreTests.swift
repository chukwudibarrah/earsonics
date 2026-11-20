import Foundation
import Testing
@testable import earsonics
@testable import EarsonicsCore

/// The download index, without the network: the engine is replaced by
/// calling the store's callbacks directly, in a throwaway folder.
@MainActor
@Suite("Downloads", .serialized)
struct DownloadStoreTests {
    let server = Server(name: "Test", url: "https://music.example.com", username: "u", password: "p")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("downloads-\(UUID().uuidString)")

    private func makeStore() -> DownloadStore { DownloadStore(root: root, engine: nil) }

    private func album(_ id: String, _ songs: [Song]) -> DownloadedCollection {
        DownloadedCollection(kind: .album, id: id, name: "Album \(id)", artist: nil, coverArt: nil, songIDs: songs.map(\.id))
    }

    /// Pretends the engine finished a song: puts a file where it would, then
    /// reports it.
    private func arrive(_ songId: String, in store: DownloadStore) throws {
        let entry = try #require(store.index(for: server.id).entries[songId])
        let job = DownloadJob(serverID: server.id, songID: songId, fileName: entry.fileName)
        let file = DownloadStore.destination(root: root, for: job)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3, 4]).write(to: file)
        store.didFinish(job, bytes: 4)
    }

    @Test func anAlbumWaitsThenArrives() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore()
        let songs = makeSongs("a", "b")
        let collection = album("1", songs)
        store.download(songs, as: collection, server: server)

        #expect(store.state(songId: "a", serverID: server.id) == .waiting)
        #expect(store.localFile(songId: "a", serverID: server.id) == nil)
        #expect(store.completion(of: collection, serverID: server.id) == (0, 2))

        try arrive("a", in: store)
        #expect(store.state(songId: "a", serverID: server.id) == .downloaded)
        #expect(store.localFile(songId: "a", serverID: server.id) != nil)
        #expect(store.completion(of: collection, serverID: server.id) == (1, 2))
        #expect(store.index(for: server.id).totalBytes == 4)
    }

    @Test func aSongSharedByTwoAlbumsIsKeptUntilBothAreRemoved() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore()
        let first = album("1", makeSongs("a", "shared"))
        let second = album("2", makeSongs("shared", "c"))
        store.download(makeSongs("a", "shared"), as: first, server: server)
        store.download(makeSongs("shared", "c"), as: second, server: server)
        try arrive("shared", in: store)
        let file = try #require(store.localFile(songId: "shared", serverID: server.id))

        store.remove(first, serverID: server.id)
        #expect(store.localFile(songId: "shared", serverID: server.id) != nil, "still needed by the second album")
        #expect(store.index(for: server.id).entries["a"] == nil)

        store.remove(second, serverID: server.id)
        #expect(store.index(for: server.id).entries["shared"] == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path), "the file wasn't deleted")
        #expect(store.index(for: server.id).collections.isEmpty)
    }

    @Test func removingASongTakesItOutOfEverything() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore()
        store.download(makeSongs("a"), as: album("1", makeSongs("a")), server: server)
        store.download(makeSongs("a"), server: server)   // also as a single
        try arrive("a", in: store)
        store.remove(songId: "a", serverID: server.id)
        #expect(store.index(for: server.id).entries["a"] == nil)
        #expect(store.localFile(songId: "a", serverID: server.id) == nil)
    }

    @Test func aFailedDownloadIsRetriedWhenAskedAgain() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore()
        store.download(makeSongs("a"), server: server)
        let entry = try #require(store.index(for: server.id).entries["a"])
        store.didFail(DownloadJob(serverID: server.id, songID: "a", fileName: entry.fileName))
        #expect(store.state(songId: "a", serverID: server.id) == .failed)
        store.download(makeSongs("a"), server: server)
        #expect(store.state(songId: "a", serverID: server.id) == .waiting)
    }

    @Test func theIndexSurvivesARestart() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore()
        let collection = album("1", makeSongs("a"))
        store.download(makeSongs("a"), as: collection, server: server)
        try arrive("a", in: store)

        let reopened = makeStore()
        #expect(reopened.localFile(songId: "a", serverID: server.id) != nil)
        #expect(reopened.collection(.album, id: "1", serverID: server.id) == collection)
        #expect(reopened.downloadedSongs(serverID: server.id).map(\.id) == ["a"])
    }

    @Test func removingEverythingClearsTheServersFolder() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore()
        store.download(makeSongs("a", "b"), as: album("1", makeSongs("a", "b")), server: server)
        try arrive("a", in: store)
        store.removeAll(serverID: server.id)
        #expect(store.index(for: server.id).entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(server.id.uuidString).path))
    }

    @Test func jobsSurviveTheTaskDescriptionRoundTrip() throws {
        let job = DownloadJob(serverID: server.id, songID: "a/b c", fileName: "x.mp3")
        #expect(DownloadJob(job.encoded) == job)
        #expect(DownloadJob("not json") == nil)
        #expect(!DownloadStore.fileName("a/b c", ext: "mp3").contains("/"))
    }
}

@MainActor
@Suite("Streaming quality on mobile data", .serialized)
struct CellularQualityTests {
    private let key = StreamQuality.cellularKey

    private func with(_ value: String?, _ body: () -> Void) {
        let saved = UserDefaults.standard.object(forKey: key)
        if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        defer { UserDefaults.standard.set(saved, forKey: key) }
        body()
    }

    @Test func theSettingIsReadAsAQualityOrSameAsWiFi() {
        with("mp3_192") { #expect(StreamQuality.cellularChoice == .mp3_192) }
        with(StreamQuality.sameAsWiFiValue) { #expect(StreamQuality.cellularChoice == nil) }
        // Unset: these tests run in the Apple TV app, where it means same as Wi-Fi.
        with(nil) { #expect(StreamQuality.cellularChoice == nil) }
    }

    @Test func onWiFiTheUsualQualityIsUsed() {
        guard !NetworkMonitor.shared.isCostly else { return }   // the test Mac is on mobile data
        with("mp3_192") { #expect(StreamQuality.forStreaming == StreamQuality.current) }
    }
}

@MainActor
@Suite("Downloaded artwork", .serialized)
struct DownloadArtworkTests {
    let server = Server(name: "Test", url: "https://music.example.com", username: "u", password: "p")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("downloads-\(UUID().uuidString)")

    /// Puts a cover where the store keeps them, as a finished fetch would.
    private func saveCover(_ id: String) throws -> URL {
        let url = root.appendingPathComponent(server.id.uuidString).appendingPathComponent("Artwork")
            .appendingPathComponent(DownloadStore.fileName(id, ext: "img"))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: url)
        return url
    }

    @Test func coversAreKeptWhileSomethingDownloadedShowsThem() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DownloadStore(root: root, engine: nil)
        let song = Song(id: "a", title: "Song a", album: nil, albumId: nil, artist: nil, artistId: nil,
                        track: nil, discNumber: nil, year: nil, genre: nil, coverArt: "al-1", size: nil,
                        contentType: nil, suffix: nil, duration: 200, bitRate: nil, path: nil, replayGain: nil)
        let album = DownloadedCollection(kind: .album, id: "1", name: "One", artist: nil, coverArt: "al-1", songIDs: ["a"])
        let playlist = DownloadedCollection(kind: .playlist, id: "p", name: "Mix", artist: nil, coverArt: "pl-p", songIDs: ["a"])
        store.download([song], as: album, server: server)
        store.download([song], as: playlist, server: server)
        #expect(store.artworkIDs(serverID: server.id) == ["al-1", "pl-p"])

        let albumCover = try saveCover("al-1")
        let playlistCover = try saveCover("pl-p")
        #expect(store.artworkFile(id: "al-1", serverID: server.id) == albumCover)

        store.remove(playlist, serverID: server.id)
        #expect(!FileManager.default.fileExists(atPath: playlistCover.path), "the playlist's cover outlived it")
        #expect(FileManager.default.fileExists(atPath: albumCover.path), "the song still shows the album's cover")

        store.remove(album, serverID: server.id)
        #expect(store.artworkFile(id: "al-1", serverID: server.id) == nil)
    }
}
