import XCTest

/// Stage 1 of the iPhone app: sign in, browse, play. Runs against the test
/// server (`TestServer`) through the debug-only launch hooks in `ServerStore`,
/// so nothing is saved on the simulator.
final class PhoneFoundationUITests: XCTestCase {
    /// A fresh app for one test, closed when the test ends (never leave
    /// music playing on the simulator).
    @MainActor
    private func makeApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        return app
    }

    /// The simulator's own system alerts (e.g. Apple Account verification)
    /// sit over the app and block taps; dismiss them if one is showing.
    @MainActor
    private func dismissSystemAlerts(waiting seconds: TimeInterval = 0) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notNow = springboard.buttons["Not Now"]
        if notNow.waitForExistence(timeout: seconds) { notNow.tap() }
    }

    /// Scrolls the form until `element` is on screen (the keyboard covers
    /// its lower rows, and off-screen rows aren't in the element tree).
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    /// Signed in: Home loads, an album opens and plays, and the mini player
    /// pauses it.
    @MainActor
    func testBrowseAndPlay() throws {
        let app = makeApp()
        app.launchEnvironment = [
            "EARSONICS_UITEST_SERVER_URL": TestServer.details.url,
            "EARSONICS_UITEST_USERNAME": TestServer.details.username,
            "EARSONICS_UITEST_PASSWORD": TestServer.details.password,
            "EARSONICS_UITEST_CLEAR_LOCAL_QUEUE": "1",
        ]
        app.launchArguments = ["-queueLaunchBehaviour", "startFresh", "-syncQueueWithServer", "NO"]
        app.launch()
        dismissSystemAlerts(waiting: 4)   // they appear a moment after launch

        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15), "Home didn't appear")
        let album = app.buttons.matching(identifier: "albumCard").firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 20), "no albums on Home")
        album.tap()

        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15), "the album page didn't open")
        XCTAssertTrue(waitUntil(timeout: 15) { play.isEnabled }, "the album's songs didn't load")
        play.tap()

        // The album's Play becomes Pause, as does the mini player's button.
        let pauses = app.buttons.matching(NSPredicate(format: "label == 'Pause'"))
        XCTAssertTrue(waitUntil(timeout: 30) { pauses.count == 2 }, "playback didn't start (\(pauses.count) Pause buttons)")
        pauses.firstMatch.tap()
        // Paused: the album offers Resume (it's still this album's queue).
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 10), "pause didn't work")
        XCTAssertEqual(pauses.count, 0)
    }

    /// A list that plays as a mix (Library › Songs) knows it's what's
    /// playing: Play becomes Pause, then Resume once paused.
    @MainActor
    func testSongsPagePlayBecomesPause() throws {
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
        dismissSystemAlerts()

        app.tabBars.buttons["Library"].tap()
        let songsRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Songs'")).firstMatch
        XCTAssertTrue(songsRow.waitForExistence(timeout: 15), "no Songs row in Library")
        songsRow.tap()
        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 20), "the Songs page didn't open")
        XCTAssertTrue(waitUntil(timeout: 20) { play.isEnabled }, "the songs didn't load")
        play.tap()

        let pauses = app.buttons.matching(NSPredicate(format: "label == 'Pause'"))
        XCTAssertTrue(waitUntil(timeout: 30) { pauses.count == 2 }, "the page's Play didn't become Pause")
        pauses.firstMatch.tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 10), "pausing didn't offer Resume")
    }

    /// First run: no servers, so the sign-in form shows; signing in opens
    /// the library.
    @MainActor
    func testSignIn() throws {
        let app = makeApp()
        app.launchEnvironment = ["EARSONICS_UITEST_NO_SERVERS": "1"]
        app.launchArguments = ["-queueLaunchBehaviour", "startFresh", "-syncQueueWithServer", "NO"]
        app.launch()
        dismissSystemAlerts(waiting: 4)   // they appear a moment after launch

        XCTAssertTrue(app.navigationBars["Add a server"].waitForExistence(timeout: 10), "no sign-in form on first run")
        let save = app.buttons["Save"]
        XCTAssertFalse(save.isEnabled, "Save is enabled with empty fields")

        type(TestServer.details.username + "'s server", into: app.textFields["Name"])
        let address = app.textFields["Address"]
        address.tap()
        address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + TestServer.details.url)
        type(TestServer.details.username, into: app.textFields["Username"])
        type(TestServer.details.password, into: app.secureTextFields["Password"])

        dismissSystemAlerts()
        let test = app.buttons["Test connection"]
        reveal(test, in: app)
        test.tap()
        XCTAssertTrue(app.staticTexts["Connected successfully"].waitForExistence(timeout: 15), "the connection test failed")
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15), "signing in didn't open the library")
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }

    @MainActor
    private func type(_ text: String, into field: XCUIElement) {
        field.tap()
        field.typeText(text)
    }
}
