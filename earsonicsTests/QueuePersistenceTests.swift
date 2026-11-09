import Foundation
import Testing
@testable import earsonics

@MainActor
@Suite("Test isolation")
struct TestIsolationTests {
    /// Unit tests run inside the app; it must not have loaded the device's
    /// real servers, or tests could change a real library.
    @Test func noRealServersAreLoaded() {
        #expect(ServerStore.shared.servers.isEmpty)
        #expect(AudioPlayerService.shared.server == nil)
        #expect(SubsonicClient.shared.server == nil)
    }
}

@MainActor
@Suite("Choosing which saved queue to restore")
struct QueueRestoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func local(savedAt: Date, ids: [String] = ["l1", "l2"]) -> QueueSnapshot {
        var q = PlayQueue()
        q.load(ids.map { makeSong($0) }, startIndex: 1, context: .album(id: "a"))
        q.cycleRepeat()   // .all — something only the local copy keeps
        return QueueSnapshot(queue: q, position: 42, savedAt: savedAt)
    }

    private func remote(changed: Date?, by client: String?, ids: [String] = ["r1", "r2", "r3"]) -> SubsonicClient.RemotePlayQueue {
        .init(songs: ids.map { makeSong($0) }, currentIndex: 2, position: 12.5, changed: changed, changedBy: client)
    }

    @Test func nothingSavedRestoresNothing() {
        #expect(QueueRestore.choose(local: nil, remote: nil) == nil)
    }

    @Test func onlyTheLocalCopy() {
        let l = local(savedAt: t0)
        #expect(QueueRestore.choose(local: l, remote: nil) == l)
    }

    @Test func onlyTheServerCopy() throws {
        let chosen = try #require(QueueRestore.choose(local: nil, remote: remote(changed: t0, by: "DSub")))
        #expect(chosen.queue.songs.map(\.id) == ["r1", "r2", "r3"])
        #expect(chosen.queue.currentIndex == 2)
        #expect(chosen.position == 12.5)
        #expect(chosen.queue.context == .mix)
        #expect(!chosen.queue.isShuffled)
    }

    @Test func anotherAppPlayingSinceWins() throws {
        let chosen = try #require(QueueRestore.choose(local: local(savedAt: t0),
                                                      remote: remote(changed: t0.addingTimeInterval(5), by: "DSub")))
        #expect(chosen.queue.songs.map(\.id) == ["r1", "r2", "r3"])
        // Repeat is a preference that carries over.
        #expect(chosen.queue.repeatMode == .all)
    }

    @Test func anOlderServerCopyLoses() {
        let l = local(savedAt: t0)
        #expect(QueueRestore.choose(local: l, remote: remote(changed: t0.addingTimeInterval(-60), by: "DSub")) == l)
    }

    @Test func ourOwnRecentServerSaveLosesToTheRicherLocalCopy() {
        let l = local(savedAt: t0)
        let r = remote(changed: t0.addingTimeInterval(10), by: SubsonicClient.clientName)
        #expect(QueueRestore.choose(local: l, remote: r) == l)
    }

    @Test func anotherAppleTVRunningEarsonicsWins() throws {
        let r = remote(changed: t0.addingTimeInterval(QueueRestore.ownSaveTolerance + 60), by: SubsonicClient.clientName)
        let chosen = try #require(QueueRestore.choose(local: local(savedAt: t0), remote: r))
        #expect(chosen.queue.songs.map(\.id) == ["r1", "r2", "r3"])
    }

    @Test func aServerCopyWithoutATimestampLoses() {
        let l = local(savedAt: t0)
        #expect(QueueRestore.choose(local: l, remote: remote(changed: nil, by: "DSub")) == l)
    }

    @Test func anEmptyServerCopyIsIgnored() {
        let l = local(savedAt: t0)
        #expect(QueueRestore.choose(local: l, remote: remote(changed: t0.addingTimeInterval(99), by: "DSub", ids: [])) == l)
    }

    @Test func anEmptyLocalCopyIsIgnored() throws {
        let empty = QueueSnapshot(queue: PlayQueue(), position: 0, savedAt: t0.addingTimeInterval(999))
        let chosen = try #require(QueueRestore.choose(local: empty, remote: remote(changed: t0, by: "DSub")))
        #expect(chosen.queue.count == 3)
    }
}

@Suite("Server timestamps")
struct TimestampTests {
    private func components(_ date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
    }

    /// The exact format the Navidrome demo returned for a saved queue.
    @Test func nanosecondPrecision() throws {
        let date = try #require(SubsonicClient.parseTimestamp("2026-11-01T12:52:06.49936326Z"))
        let c = components(date)
        #expect((c.year, c.month, c.day, c.hour, c.minute, c.second) == (2026, 11, 1, 12, 52, 6))
        #expect(abs(Double(c.nanosecond ?? 0) / 1e9 - 0.499) < 0.002)
    }

    @Test func otherCommonFormats() throws {
        let millis = try #require(SubsonicClient.parseTimestamp("2026-11-01T12:52:06.123Z"))
        let plain = try #require(SubsonicClient.parseTimestamp("2026-11-01T12:52:06Z"))
        let offset = try #require(SubsonicClient.parseTimestamp("2026-11-01T13:52:06.5+01:00"))
        #expect(abs(millis.timeIntervalSince(plain) - 0.123) < 0.001)
        #expect(abs(offset.timeIntervalSince(plain) - 0.5) < 0.001)
    }

    @Test func garbageIsRejected() {
        #expect(SubsonicClient.parseTimestamp("yesterday") == nil)
        #expect(SubsonicClient.parseTimestamp("") == nil)
    }
}

@Suite("Form encoding")
struct FormEncodingTests {
    @Test func escapesCharactersWithMeaningInFormBodies() {
        let body = SubsonicClient.formEncoded([
            URLQueryItem(name: "id", value: "a+b&c=d e"),
            URLQueryItem(name: "name", value: "Café/é"),
            URLQueryItem(name: "empty", value: nil),
        ])
        #expect(body == "id=a%2Bb%26c%3Dd%20e&name=Caf%C3%A9%2F%C3%A9&empty=")
    }

    @Test func leavesUnreservedCharactersAlone() {
        #expect(SubsonicClient.formEncoded([URLQueryItem(name: "v", value: "Az09-._~")]) == "v=Az09-._~")
    }
}

@MainActor
@Suite("Local queue store")
struct LocalQueueStoreTests {
    @Test func roundTripsASnapshot() async throws {
        let serverID = UUID()
        defer { LocalQueueStore.delete(serverID: serverID) }
        var q = PlayQueue()
        q.load(makeSongs("a", "b", "a"), startIndex: 2, shuffle: true, context: .playlist(id: "p"))
        q.appendAutoplay(makeSongs("r"))
        let snapshot = QueueSnapshot(queue: q, position: 73.25, savedAt: Date(timeIntervalSince1970: 1_800_000_000))

        LocalQueueStore.save(snapshot, serverID: serverID)
        // The write happens off the main thread.
        var loaded: QueueSnapshot?
        for _ in 0..<50 where loaded == nil {
            try await Task.sleep(for: .milliseconds(20))
            loaded = LocalQueueStore.load(serverID: serverID)
        }
        #expect(loaded == snapshot)
    }

    @Test func eachServerHasItsOwnCopy() {
        #expect(LocalQueueStore.fileURL(serverID: UUID()) != LocalQueueStore.fileURL(serverID: UUID()))
    }

    @Test func deletingRemovesIt() async throws {
        let serverID = UUID()
        LocalQueueStore.save(QueueSnapshot(queue: PlayQueue(), position: 0, savedAt: Date()), serverID: serverID)
        try await Task.sleep(for: .milliseconds(200))
        LocalQueueStore.delete(serverID: serverID)
        #expect(LocalQueueStore.load(serverID: serverID) == nil)
    }
}

/// Uses the shared player, which (see `TestIsolationTests`) has no server.
@MainActor
@Suite("Restoring a queue into the player", .serialized)
struct PlayerRestoreTests {
    let player = AudioPlayerService.shared

    private func snapshot(position: Double) -> QueueSnapshot {
        var q = PlayQueue()
        q.load([makeSong("a", duration: 200), makeSong("b", duration: 200)], startIndex: 1)
        return QueueSnapshot(queue: q, position: position, savedAt: Date())
    }

    @Test func restoresPausedAtTheSavedPosition() {
        defer { player.clearQueue() }
        player.restore(snapshot(position: 95), startPlaying: false)
        #expect(player.currentSong?.id == "b")
        #expect(player.currentTime == 95)
        #expect(player.currentPosition == 95)
        #expect(player.duration == 200)
        #expect(!player.intendsToPlay)
        #expect(!player.isPlaying)
    }

    @Test func aPositionAtTheVeryEndStartsTheTrackAgain() {
        defer { player.clearQueue() }
        player.restore(snapshot(position: 199.5), startPlaying: false)
        #expect(player.currentTime == 0)
    }
}
