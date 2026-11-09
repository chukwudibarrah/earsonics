import XCTest

/// Shared setup and Siri Remote helpers for the UI tests. Tests run against
/// the public Navidrome demo (https://demo.navidrome.org, demo/demo) through
/// the debug-only launch hook in `ServerStore`, so the simulator's saved
/// servers are never touched.
@MainActor
class RemoteTestCase: XCTestCase {

    var app: XCUIApplication!
    let remote = XCUIRemote.shared
    let tabOrder = ["Search", "Home", "Artists", "Tracks", "Playlists", "Favourites", "Settings"]

    static let demoEnvironment = [
        "EARSONICS_UITEST_SERVER_URL": "https://demo.navidrome.org",
        "EARSONICS_UITEST_USERNAME": "demo",
        "EARSONICS_UITEST_PASSWORD": "demo",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Always close the app: playback tests stream real audio, and an app
    /// left running on the test simulator keeps playing after the run.
    override func tearDownWithError() throws {
        app?.terminate()
        try super.tearDownWithError()
    }

    /// Launches against the demo server and waits for Home to load and take
    /// focus.
    func launchToHome(extraEnvironment: [String: String] = [:]) {
        app.launchEnvironment = Self.demoEnvironment.merging(extraEnvironment) { $1 }
        app.launch()
        // A short settle only: launch used to strand focus on the hidden
        // sidebar for ~8s (Select ignored, Menu exiting the app); Home now
        // claims focus as soon as its first shelf exists, so these tests also
        // guard that fix.
        XCTAssertTrue(app.staticTexts["Keep spinning"].waitForExistence(timeout: 30),
                      "Home didn't finish loading from the demo server")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(waitUntil(timeout: 10) { self.focused.exists }, "nothing took focus after launch")
    }

    // MARK: - Steps

    func openFirstArtistFromArtistsTab() {
        selectTabFromRoot("Artists")
        // Focus lands in the search field's keyboard; move down to the list.
        for _ in 0..<10 where !focused.label.localizedCaseInsensitiveContains("album") {
            press(.down)
        }
        XCTAssertTrue(focused.label.localizedCaseInsensitiveContains("album"),
                      "couldn't reach an artist row; focused: \(focused.debugDescription)")
        press(.select)
        waitFor(app.buttons["Play all"], "artist page didn't open")
    }

    /// Favourites shows a full-screen spinner until its data arrives; pressing
    /// before then finds nothing to move to (a slow demo server made this flaky).
    func waitForFavouritesToLoad() {
        waitFor(app.buttons["Albums"], "Favourites didn't open")
        XCTAssertTrue(waitUntil(timeout: 30) { !self.app.activityIndicators["Loading favourites..."].exists },
                      "Favourites didn't finish loading")
    }

    /// On an artist page, moves down from the header buttons into the album
    /// grid and opens the first album.
    func openFirstAlbumFromArtistPage() {
        for _ in 0..<4 {
            press(.down)
            if focused.frame.minY > 400 { break }
        }
        press(.select)
        waitFor(app.buttons["Play next"], "album page didn't open from the artist page")
    }

    /// From a tab's root screen, Menu opens the sidebar (nothing to pop).
    func selectTabFromRoot(_ name: String) {
        press(.menu, pause: 0.5)
        let opened = waitUntil(timeout: 5) { self.focusedSidebarTab != nil }
        XCTAssertTrue(opened, "Menu didn't open the sidebar; focused: \(focused.debugDescription)")
        moveSidebarFocus(to: name)
        press(.select, pause: 0.5)
        // Wait for focus to land in the new tab before the next press.
        XCTAssertTrue(waitUntil(timeout: 10) { self.focused.exists && self.focusedSidebarTab == nil },
                      "focus didn't move into \(name)")
    }

    /// From a pushed page, reach the sidebar by moving LEFT — the way a user
    /// does — then pick another tab, and require the page to leave the screen.
    /// Never presses Menu here: on a pushed page Menu pops it, which would
    /// make the check pass for the wrong reason.
    func switchTabFromDetail(to name: String, detailMarker: XCUIElement,
                                     file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 where focusedSidebarTab == nil {
            press(.left)
        }
        guard focusedSidebarTab != nil else {
            XCTFail("couldn't reach the sidebar by moving left; focused: \(focused.debugDescription)",
                    file: file, line: line)
            return
        }
        moveSidebarFocus(to: name)
        press(.select, pause: 2)

        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: detailMarker)
        let result = XCTWaiter().wait(for: [gone], timeout: 6)
        XCTAssertEqual(result, .completed,
                       "after selecting \(name) in the sidebar, the previous page is still on screen",
                       file: file, line: line)
    }

    func moveSidebarFocus(to name: String) {
        guard let target = tabOrder.firstIndex(of: name) else { return XCTFail("unknown tab \(name)") }
        for _ in 0..<tabOrder.count {
            guard let current = focusedSidebarTab, let index = tabOrder.firstIndex(of: current) else {
                return XCTFail("sidebar not focused; focused: \(focused.debugDescription)")
            }
            if index == target { return }
            press(index > target ? .up : .down, pause: 0.6)
        }
        XCTFail("couldn't move sidebar focus to \(name)")
    }

    // MARK: - Helpers

    var focused: XCUIElement {
        app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
    }

    /// The tab name if a sidebar item has focus. The focused item is a cell
    /// whose button carries the tab's label.
    var focusedSidebarTab: String? {
        let element = focused
        guard element.exists, element.elementType == .cell else { return nil }
        let label = element.buttons.firstMatch.label
        return tabOrder.contains(label) ? label : nil
    }

    /// Polls `condition` until it holds or `timeout` passes.
    func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }

    func press(_ button: XCUIRemote.Button, pause: TimeInterval = 1) {
        remote.press(button)
        Thread.sleep(forTimeInterval: pause)
    }

    func waitFor(_ element: XCUIElement, _ message: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        let found = element.waitForExistence(timeout: 15)
        XCTAssertTrue(found, "\(message); focused: \(focused.debugDescription)", file: file, line: line)
    }
}

// MARK: - Playback helpers
extension RemoteTestCase {
    var miniPlayer: XCUIElement { app.buttons["miniPlayer"] }

    /// Opens the first "Just arrived" album and presses Play.
    func startPlayingFirstHomeAlbum() {
        press(.select)
        waitFor(app.buttons["Play next"], "album page didn't open")
        // Wait for the tracks before pressing Play (Play does nothing while
        // the album is still loading).
        XCTAssertTrue(waitUntil(timeout: 20) { self.app.buttons.matching(NSPredicate(format: "label CONTAINS ':'")).count > 0 },
                      "album tracks didn't load")
        XCTAssertTrue(focused.label.contains("Play"), "expected focus on Play; focused: \(focused.debugDescription)")
        press(.select)
        XCTAssertTrue(waitForMiniPlayer(containing: "playing", timeout: 30),
                      "playback didn't start; mini player: \(miniPlayerValue)")
    }

    func pressPlayPause(expecting state: String, file: StaticString = #filePath, line: UInt = #line) {
        press(.playPause, pause: 0.5)
        XCTAssertTrue(waitForMiniPlayer(containing: state, timeout: 10),
                      "after play/pause expected \(state); mini player: \(String(describing: miniPlayer.value)); focused: \(focused.debugDescription)",
                      file: file, line: line)
        // Make sure it doesn't flip back (a press handled twice would toggle
        // and immediately toggle again).
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(miniPlayerValue.hasSuffix(state),
                      "state flipped back after play/pause: \(miniPlayerValue)", file: file, line: line)
    }

    var miniPlayerValue: String { (miniPlayer.value as? String) ?? "" }

    func waitForMiniPlayer(containing state: String, timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) { self.miniPlayer.exists && self.miniPlayerValue.hasSuffix(state) }
    }
}
