import XCTest

/// Downloading an album: the page's button shows progress then Downloaded,
/// the album appears in Library › Downloads, and removing it frees it again.
/// Downloads a whole album from the test server.
final class DownloadsUITests: XCTestCase {
    @MainActor
    func testDownloadingAnAlbum() throws {
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
        let download = app.buttons["downloadButton"]
        XCTAssertTrue(download.waitForExistence(timeout: 15), "no download button")
        XCTAssertTrue(waitUntil(15) { download.isEnabled }, "the album's songs didn't load")

        // A leftover download from an earlier run: remove it first.
        if download.label == "Downloaded" || download.label.hasPrefix("Downloading") {
            remove(download, in: app)
        }
        XCTAssertEqual(download.label, "Download")
        download.tap()
        XCTAssertTrue(waitUntil(180) { download.label == "Downloaded" },
                      "the album didn't finish downloading (\(download.label))")

        // Library › Downloads lists it.
        app.tabBars.buttons["Library"].tap()
        let downloadsRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Downloads'")).firstMatch
        for _ in 0..<4 where !downloadsRow.isHittable { app.swipeUp() }
        XCTAssertTrue(downloadsRow.waitForExistence(timeout: 5), "no Downloads row in Library")
        downloadsRow.tap()
        XCTAssertTrue(app.staticTexts["Albums & Playlists"].waitForExistence(timeout: 5), "the album isn't listed")
        XCTAssertTrue(app.staticTexts["Ready to play offline"].exists)

        // Back on the album, remove it. Scrolling minimised the tab bar:
        // scroll back up to bring it out again.
        let home = app.tabBars.buttons["Home"]
        for _ in 0..<3 where !home.exists { app.swipeDown() }
        XCTAssertTrue(home.waitForExistence(timeout: 5), "the tab bar didn't come back")
        home.tap()
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        remove(download, in: app)
        XCTAssertEqual(download.label, "Download")
    }

    @MainActor
    private func remove(_ download: XCUIElement, in app: XCUIApplication) {
        download.tap()
        let confirm = app.buttons["Remove Download"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no Remove confirmation")
        confirm.tap()
        XCTAssertTrue(waitUntil(10) { download.label == "Download" }, "the download wasn't removed")
    }

    @MainActor
    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return condition()
    }
}
