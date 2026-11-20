import XCTest

/// The full Now Playing screen: opens from the mini player, its transport
/// works, and the queue and lyrics panels show. Plays a few seconds of audio.
final class NowPlayingUITests: XCTestCase {
    @MainActor
    func testNowPlayingScreen() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        app.launchEnvironment = [
            "EARSONICS_UITEST_SERVER_URL": TestServer.details.url,
            "EARSONICS_UITEST_USERNAME": TestServer.details.username,
            "EARSONICS_UITEST_PASSWORD": TestServer.details.password,
            "EARSONICS_UITEST_CLEAR_LOCAL_QUEUE": "1",
        ]
        app.launchArguments = ["-queueLaunchBehaviour", "startFresh", "-syncQueueWithServer", "NO"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Not Now"].waitForExistence(timeout: 4) { springboard.buttons["Not Now"].tap() }

        // Play an album.
        let album = app.buttons.matching(identifier: "albumCard").firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 20), "no albums on Home")
        album.tap()
        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        XCTAssertTrue(waitUntil(15) { play.isEnabled }, "the album's songs didn't load")
        play.tap()

        // Open Now Playing from the mini player.
        let miniPlayer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Now playing:'")).firstMatch
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 20), "no mini player")
        let firstTitle = miniPlayer.label
        miniPlayer.tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Now Playing didn't open")

        // Pause, then play again (the screen's own button, not the mini
        // player's behind it).
        let playPause = app.buttons["nowPlaying.playPause"]
        XCTAssertEqual(playPause.label, "Pause")
        playPause.tap()
        XCTAssertTrue(waitUntil(10) { playPause.label == "Play" }, "pause didn't work")
        playPause.tap()
        XCTAssertTrue(waitUntil(15) { playPause.label == "Pause" }, "play didn't work")

        // The queue shows what's next; Next moves on.
        app.buttons["Queue"].tap()
        XCTAssertTrue(app.staticTexts["Up Next"].waitForExistence(timeout: 5), "the queue didn't show")
        app.buttons["nowPlaying.next"].tap()
        app.buttons["Lyrics"].tap()
        XCTAssertTrue(waitUntil(15) {
            app.staticTexts["No lyrics"].exists || app.scrollViews.count > 0
        }, "the lyrics panel didn't show")

        playPause.tap()
        close.tap()
        XCTAssertTrue(waitUntil(10) { !close.exists }, "Now Playing didn't close")
        XCTAssertNotEqual(miniPlayer.label, firstTitle, "Next didn't change the song")
    }

    @MainActor
    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }
}
