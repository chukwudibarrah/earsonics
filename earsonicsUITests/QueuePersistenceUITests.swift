import XCTest

/// Saving and restoring the play queue across launches, locally and through
/// the server. Runs against the demo server; the demo account's shared queue
/// is put back after each test.
final class QueuePersistenceUITests: RemoteTestCase {

    private var savedDemoQueue: DemoServerAPI.SavedQueue?

    override func setUp() async throws {
        try await super.setUp()
        savedDemoQueue = try await DemoServerAPI.snapshotQueue()
    }

    override func tearDown() async throws {
        if let savedDemoQueue { try await DemoServerAPI.restoreQueue(savedDemoQueue) }
        try await super.tearDown()
    }

    /// Sync off: the on-device copy alone brings back the queue, paused, at
    /// the same track and position; "Resume playing" brings it back playing.
    func testQueueRestoresFromTheDeviceAfterRelaunch() throws {
        let localOnly = ["-syncQueueWithServer", "NO"]
        app.launchArguments = localOnly + ["-queueLaunchBehaviour", "restorePaused"]
        launchToHome(extraEnvironment: ["EARSONICS_UITEST_CLEAR_LOCAL_QUEUE": "1"])
        startPlayingFirstHomeAlbum()
        Thread.sleep(forTimeInterval: 12)                 // play a little
        pressPlayPause(expecting: "paused")
        let title = currentTitle
        Thread.sleep(forTimeInterval: 2)                  // let the save land
        app.terminate()

        launchToHome()                                    // same arguments
        XCTAssertTrue(waitForMiniPlayer(containing: "paused", timeout: 15),
                      "the queue wasn't restored; mini player: \(miniPlayerValue)")
        XCTAssertEqual(currentTitle, title)

        // It resumes where it left off rather than from the start.
        pressPlayPause(expecting: "playing")
        let elapsed = try openNowPlayingAndReadElapsed()
        XCTAssertGreaterThanOrEqual(elapsed, 10, "playback restarted from \(elapsed)s instead of the saved position")
        app.terminate()

        app.launchArguments = localOnly + ["-queueLaunchBehaviour", "resumePlaying"]
        launchToHome()
        XCTAssertTrue(waitForMiniPlayer(containing: "playing", timeout: 30),
                      "“Resume playing” didn't resume; mini player: \(miniPlayerValue)")
        XCTAssertEqual(currentTitle, title, "resumed a different song; mini player: \(miniPlayerValue)")
    }

    /// Sync on: what's playing here is saved on the server, as earsonics, at
    /// the right song and position — what another app would pick up.
    func testQueueIsSavedToTheServer() async throws {
        app.launchArguments = ["-syncQueueWithServer", "YES"]
        launchToHome(extraEnvironment: ["EARSONICS_UITEST_CLEAR_LOCAL_QUEUE": "1"])
        startPlayingFirstHomeAlbum()
        Thread.sleep(forTimeInterval: 8)
        pressPlayPause(expecting: "paused")
        let title = currentTitle
        try await Task.sleep(for: .seconds(4))

        let serverQueue = try await DemoServerAPI.playQueue()
        let queue = try XCTUnwrap(serverQueue, "no queue on the server")
        XCTAssertEqual(queue["changedBy"] as? String, "earsonics")
        let entries = queue["entry"] as? [[String: Any]] ?? []
        let index = try XCTUnwrap(queue["currentIndex"] as? Int)
        XCTAssertTrue(entries.indices.contains(index))
        XCTAssertEqual(entries[index]["title"] as? String, title)
        XCTAssertGreaterThan(entries.count, 1, "only the current song was saved, not the whole album")
        let position = queue["position"] as? Int ?? 0
        XCTAssertGreaterThanOrEqual(position, 6_000, "saved position \(position) ms is behind where playback paused")
    }

    /// A queue another app saved more recently is picked up on launch.
    func testQueueFromAnotherAppIsPickedUp() async throws {
        let songs = try await DemoServerAPI.randomSongs(3)
        XCTAssertEqual(songs.count, 3)
        let ids = songs.compactMap { $0["id"] as? String }
        let expectedTitle = try XCTUnwrap(songs[1]["title"] as? String)
        try await DemoServerAPI.savePlayQueue(ids: ids, currentIndex: 1, positionMs: 30_000)

        app.launchArguments = ["-syncQueueWithServer", "YES", "-queueLaunchBehaviour", "restorePaused"]
        launchToHome(extraEnvironment: ["EARSONICS_UITEST_CLEAR_LOCAL_QUEUE": "1"])
        XCTAssertTrue(waitForMiniPlayer(containing: "paused", timeout: 15),
                      "the other app's queue wasn't restored; mini player: \(miniPlayerValue)")
        XCTAssertEqual(currentTitle, expectedTitle)
    }

    /// Reproduces a failure seen once: a queue restored from the server, then
    /// Play pressed on that same album's page (which resumes the restored
    /// queue rather than reloading the album).
    func testPlayOnTheRestoredAlbumResumesIt() async throws {
        // Find the first "Just arrived" album and save its tracks as "another
        // app", currently on track 3, 30 s in.
        let newest = try await DemoServerAPI.call("getAlbumList2.view", [("type", "newest"), ("size", "1")])
        let albumID = try XCTUnwrap(((newest["albumList2"] as? [String: Any])?["album"] as? [[String: Any]])?.first?["id"] as? String)
        let album = try await DemoServerAPI.call("getAlbum.view", [("id", albumID)])
        let tracks = (album["album"] as? [String: Any])?["song"] as? [[String: Any]] ?? []
        XCTAssertGreaterThan(tracks.count, 3)
        let expectedTitle = try XCTUnwrap(tracks[2]["title"] as? String)
        try await DemoServerAPI.savePlayQueue(ids: tracks.compactMap { $0["id"] as? String }, currentIndex: 2, positionMs: 30_000)

        app.launchArguments = ["-syncQueueWithServer", "YES", "-queueLaunchBehaviour", "restorePaused"]
        launchToHome(extraEnvironment: ["EARSONICS_UITEST_CLEAR_LOCAL_QUEUE": "1"])
        XCTAssertTrue(waitForMiniPlayer(containing: "paused", timeout: 15),
                      "the queue wasn't restored; mini player: \(miniPlayerValue)")
        XCTAssertEqual(currentTitle, expectedTitle)
        startPlayingFirstHomeAlbum()
        XCTAssertEqual(currentTitle, expectedTitle, "Play reloaded the album instead of resuming the restored queue")
    }

    // MARK: - Helpers

    private var currentTitle: String {
        miniPlayerValue.components(separatedBy: ", ").first ?? ""
    }

    /// Moves focus up to the mini player, opens Now Playing, and reads the
    /// elapsed time (the first "m:ss" label).
    private func openNowPlayingAndReadElapsed() throws -> Int {
        // The pill sits top-right: go along the first shelf towards it first,
        // since Up from the leftmost card has nothing above it.
        for _ in 0..<5 { press(.right, pause: 0.5) }
        for _ in 0..<4 where !miniPlayer.hasFocus { press(.up, pause: 0.6) }
        XCTAssertTrue(miniPlayer.hasFocus, "couldn't reach the mini player; focused: \(focused.debugDescription)")
        press(.select, pause: 2)
        let times = app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]+:[0-9]{2}$'"))
        XCTAssertTrue(times.firstMatch.waitForExistence(timeout: 5), "Now Playing didn't open")
        let parts = times.firstMatch.label.split(separator: ":").compactMap { Int($0) }
        return try XCTUnwrap(parts.count == 2 ? parts[0] * 60 + parts[1] : nil)
    }
}
