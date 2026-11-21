import XCTest

/// App Store screenshots, from the public Navidrome demo (freely licensed
/// music, published demo account). Skipped unless asked for:
///
///     TEST_RUNNER_EARSONICS_SCREENSHOTS=1 xcodebuild test … \
///         -only-testing:earsonics-iOSUITests/AppStoreScreenshots
///
/// Each screen is attached to the result bundle as "NN-name".
final class AppStoreScreenshots: XCTestCase {
    @MainActor
    func testCaptureScreens() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["EARSONICS_SCREENSHOTS"] == "1",
                          "set TEST_RUNNER_EARSONICS_SCREENSHOTS=1 to capture App Store screenshots")
        continueAfterFailure = true
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        app.launchEnvironment = [
            "EARSONICS_UITEST_SERVER_URL": "https://demo.navidrome.org",
            "EARSONICS_UITEST_USERNAME": "demo",
            "EARSONICS_UITEST_PASSWORD": "demo",
            "EARSONICS_UITEST_SERVER_NAME": "My Music",
            "EARSONICS_UITEST_CLEAR_LOCAL_QUEUE": "1",
        ]
        app.launchArguments = ["-queueLaunchBehaviour", "startFresh", "-syncQueueWithServer", "NO",
                               "-appearance", "dark"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Not Now"].waitForExistence(timeout: 4) { springboard.buttons["Not Now"].tap() }

        // Home, once covers have arrived.
        let album = app.buttons.matching(identifier: "albumCard").firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 30), "no albums on Home")
        settle(4)
        capture("01-home")

        // An album, playing.
        album.tap()
        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        XCTAssertTrue(waitUntil(20) { play.isEnabled })
        play.tap()
        settle(4)
        capture("02-album")

        // Now Playing, then its queue.
        let miniPlayer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Now playing:'")).firstMatch
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 30))
        miniPlayer.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        settle(4)
        capture("03-now-playing")
        // Wide windows already show the queue beside the controls.
        if !app.buttons["Queue"].isSelected {
            app.buttons["Queue"].tap()
            settle(2)
            capture("04-queue")
        }
        app.buttons["Close"].tap()
        settle(2)

        // Library, Settings and Search.
        app.tab("Library").tap()
        settle(3)
        capture("05-library")
        app.tab("Settings").tap()
        settle(2)
        capture("06-settings")

        // Search last (open, it takes over the tab bar), with a query: the
        // demo's quick-start chips include odd playlists made by visitors.
        app.tab("Search").tap()
        let field = app.searchFields["Albums, artists, songs"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no search field")
        // iPad shows the field without focusing it.
        if app.keyboards.count == 0 { field.tap() }
        field.typeText("love\n")
        settle(4)
        capture("07-search")
    }

    @MainActor
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func settle(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

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
