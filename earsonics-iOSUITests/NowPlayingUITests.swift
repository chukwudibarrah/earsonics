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

    /// Up Next can be edited: swipe to remove, swipe to play next, clear.
    @MainActor
    func testEditingUpNext() throws {
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

        app.buttons.matching(identifier: "albumCard").firstMatch.tap()
        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        XCTAssertTrue(waitUntil(15) { play.isEnabled })
        // The album's first songs, from its track list ("Title, Artist, 3:55").
        let tracks = app.buttons.matching(NSPredicate(format: "label MATCHES '.*, [0-9]+:[0-9]{2}$'"))
        XCTAssertGreaterThan(tracks.count, 3, "an album with fewer than four songs")
        let titles = (0..<4).map { tracks.element(boundBy: $0).label.components(separatedBy: ", ").first ?? "" }
        play.tap()
        let miniPlayer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Now playing:'")).firstMatch
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 20))
        miniPlayer.tap()
        app.buttons["nowPlaying.playPause"].tap()   // pause: the test needs no sound
        app.buttons["Queue"].tap()
        XCTAssertTrue(app.staticTexts["Up Next"].waitForExistence(timeout: 5))

        // Rows are labelled "Title, Artist"; only on-screen rows exist, so
        // scroll to a row before swiping it.
        let list = app.collectionViews["queueList"]
        func row(_ title: String) -> XCUIElement {
            list.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title + ", ")).firstMatch
        }
        func scrollTo(_ title: String) {
            for _ in 0..<6 where !(row(title).exists && row(title).isHittable) { list.swipeUp() }
        }
        func upNextOrder() -> [String] {
            list.buttons.matching(NSPredicate(format: "label CONTAINS ', '")).allElementsBoundByIndex
                .map { $0.label.components(separatedBy: ", ").first ?? "" }
        }

        // Swipe left to remove the first song in Up Next.
        XCTAssertTrue(row(titles[1]).waitForExistence(timeout: 5))
        row(titles[1]).swipeLeft()
        app.buttons["Remove"].tap()
        XCTAssertTrue(waitUntil(5) { !row(titles[1]).exists }, "the song wasn't removed")

        // Swipe right to play a later song next: it must follow the current one.
        scrollTo(titles[3])
        row(titles[3]).swipeRight()
        app.buttons["Play Next"].tap()
        for _ in 0..<6 where !row(titles[0]).exists { list.swipeDown() }
        XCTAssertTrue(waitUntil(5) { Array(upNextOrder().prefix(2)) == [titles[0], titles[3]] },
                      "Play Next didn't move the song up; order: \(upNextOrder())")

        // Clear Up Next.
        app.buttons["Clear"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Clear '")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Nothing up next"].waitForExistence(timeout: 5), "Up Next wasn't cleared")
        XCTAssertTrue(row(titles[0]).exists, "clearing removed the playing song")
    }

    /// Dragging the position thumb seeks, and the song carries on from
    /// there (the slider doesn't always report the end of a drag).
    @MainActor
    func testScrubbing() throws {
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

        let album = app.buttons.matching(identifier: "albumCard").firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 20), "no albums on Home")
        album.tap()
        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        XCTAssertTrue(waitUntil(15) { play.isEnabled }, "the album's songs didn't load")
        play.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 15), "the album's Play didn't become Pause")
        let miniPlayer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Now playing:'")).firstMatch
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 20), "no mini player")
        miniPlayer.tap()

        let slider = app.sliders["Position"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        func seconds() -> Double {
            let time = (slider.value as? String ?? "").components(separatedBy: " of ").first ?? ""
            let parts = time.split(separator: ":").compactMap { Double($0) }
            return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
        }
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
        start.press(forDuration: 0.5, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                    withVelocity: 150, thenHoldForDuration: 0.3)
        let landed = seconds()
        XCTAssertGreaterThan(landed, 30, "the drag didn't move the position")
        XCTAssertTrue(waitUntil(10) { seconds() >= landed + 3 }, "the song didn't carry on from the new position")
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
