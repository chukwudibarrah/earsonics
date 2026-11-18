import XCTest

/// The Artists search field sits below the top strip (the old inline
/// keyboard drew under the page title and the Now Playing button), and
/// searching filters the list. Silent: nothing plays.
final class ArtistsSearchUITests: RemoteTestCase {
    func testSearchFieldIsBelowTheTopStripAndFilters() {
        app.launchArguments = ["-queueLaunchBehaviour", "startFresh", "-syncQueueWithServer", "NO"]
        launchToHome()
        selectTabFromRoot("Artists")

        let field = app.textFields["Search artists"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no search field on Artists")
        XCTAssertGreaterThan(field.frame.minY, 140, "the search field is up in the top strip: \(field.frame)")
        // The old inline keyboard's letters must be gone.
        XCTAssertFalse(app.keyboards.firstMatch.exists, "a keyboard is showing before searching")

        // Up from the list reaches the field.
        for _ in 0..<4 where !field.hasFocus { press(.up, pause: 0.6) }
        XCTAssertTrue(field.hasFocus, "Up didn't reach the search field; focused: \(focused.debugDescription)")

        // Searching for something that isn't there shows the no-match message.
        press(.select, pause: 1.5)
        field.typeText("zzqqxx")
        press(.menu, pause: 1.5)   // leave the keyboard
        XCTAssertTrue(app.staticTexts["No artists match “zzqqxx”"].waitForExistence(timeout: 5),
                      "searching didn't filter the list")
    }
}
