//
//  earsonicsUITests.swift
//  earsonicsUITests
//
//  Created by MacDaddy on 02/05/2026.
//

import XCTest

/// Remote-driven navigation tests, run against the public Navidrome demo
/// (https://demo.navidrome.org, demo/demo) through the debug-only launch hook
/// in `ServerStore`, so the simulator's saved servers are never touched. They
/// need network access and depend on the demo's library (starred albums,
/// artists, playlists), which the demo keeps populated.
///
/// The main check is the tab-switch bug: open a page inside a tab, switch tab
/// from the sidebar, and the new tab must actually appear — the page must not
/// stay on screen with the new tab loading behind it.
@MainActor
final class earsonicsUITests: XCTestCase {

    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared
    private let tabOrder = ["Search", "Home", "Artists", "Tracks", "Playlists", "Favourites", "Settings"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment = [
            "EARSONICS_UITEST_SERVER_URL": "https://demo.navidrome.org",
            "EARSONICS_UITEST_USERNAME": "demo",
            "EARSONICS_UITEST_PASSWORD": "demo",
        ]
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

    // MARK: - Tab switching from detail pages
    // Search isn't covered: tvOS's full-screen keyboard doesn't respond to
    // automated remote presses in the simulator. It uses the same fix as
    // the screens below — check it by hand.

    /// Control: Home pushes through a navigation path and has always worked.
    func testHomeAlbumThenSwitchTab() {
        press(.select)                        // focus starts on the first "Just arrived" album
        waitFor(app.buttons["Play next"], "album page didn't open")
        switchTabFromDetail(to: "Artists", detailMarker: app.buttons["Play next"])
    }

    func testFavouritesAlbumThenSwitchTab() {
        selectTabFromRoot("Favourites")
        waitForFavouritesToLoad()
        press(.right)                         // Songs → Albums (selects on focus)
        press(.down)                          // into the album grid
        press(.select)
        waitFor(app.buttons["Play next"], "album page didn't open")
        switchTabFromDetail(to: "Home", detailMarker: app.buttons["Play next"])
    }

    func testFavouritesArtistThenSwitchTab() {
        selectTabFromRoot("Favourites")
        waitForFavouritesToLoad()
        press(.right); press(.right)          // Songs → Albums → Artists
        press(.down)
        press(.select)
        waitFor(app.buttons["Play all"], "artist page didn't open")
        switchTabFromDetail(to: "Home", detailMarker: app.buttons["Play all"])
    }

    /// Two levels deep through the shared artist page, in a second tab:
    /// Favourites → artist → album.
    func testFavouritesArtistAlbumThenSwitchTab() {
        selectTabFromRoot("Favourites")
        waitForFavouritesToLoad()
        press(.right); press(.right)
        press(.down)
        press(.select)
        waitFor(app.buttons["Play all"], "artist page didn't open")
        openFirstAlbumFromArtistPage()
        switchTabFromDetail(to: "Home", detailMarker: app.buttons["Play next"])
    }

    func testArtistsTabArtistThenSwitchTab() {
        openFirstArtistFromArtistsTab()
        switchTabFromDetail(to: "Home", detailMarker: app.buttons["Play all"])
    }

    /// Two levels deep: Artists → artist → album, opened from inside the
    /// artist page.
    func testArtistsTabAlbumThenSwitchTab() {
        openFirstArtistFromArtistsTab()
        openFirstAlbumFromArtistPage()
        switchTabFromDetail(to: "Home", detailMarker: app.buttons["Play next"])
    }

    /// Control after the 1.08 fix: Playlists was rebuilt on Home's pattern.
    func testPlaylistThenSwitchTab() {
        selectTabFromRoot("Playlists")
        waitFor(app.buttons["New playlist"], "Playlists didn't load")
        press(.down)                          // first playlist row
        press(.select)
        waitFor(app.buttons["Rename"], "playlist page didn't open")
        switchTabFromDetail(to: "Home", detailMarker: app.buttons["Rename"])
    }

    func testSettingsServerEditorThenSwitchTab() {
        selectTabFromRoot("Settings")
        press(.select)                        // "Manage servers" (focused on arrival)
        // Row labels combine their texts, so match by substring.
        waitFor(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add server'")).firstMatch,
                "server list didn't open")
        press(.select)                        // first server row
        waitFor(app.buttons["Test connection"], "server editor didn't open")
        switchTabFromDetail(to: "Home", detailMarker: app.buttons["Test connection"])
    }

    // MARK: - Steps

    private func openFirstArtistFromArtistsTab() {
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
    private func waitForFavouritesToLoad() {
        waitFor(app.buttons["Albums"], "Favourites didn't open")
        XCTAssertTrue(waitUntil(timeout: 30) { !self.app.activityIndicators["Loading favourites..."].exists },
                      "Favourites didn't finish loading")
    }

    /// On an artist page, moves down from the header buttons into the album
    /// grid and opens the first album.
    private func openFirstAlbumFromArtistPage() {
        for _ in 0..<4 {
            press(.down)
            if focused.frame.minY > 400 { break }
        }
        press(.select)
        waitFor(app.buttons["Play next"], "album page didn't open from the artist page")
    }

    /// From a tab's root screen, Menu opens the sidebar (nothing to pop).
    private func selectTabFromRoot(_ name: String) {
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
    private func switchTabFromDetail(to name: String, detailMarker: XCUIElement,
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

    private func moveSidebarFocus(to name: String) {
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

    private var focused: XCUIElement {
        app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
    }

    /// The tab name if a sidebar item has focus. The focused item is a cell
    /// whose button carries the tab's label.
    private var focusedSidebarTab: String? {
        let element = focused
        guard element.exists, element.elementType == .cell else { return nil }
        let label = element.buttons.firstMatch.label
        return tabOrder.contains(label) ? label : nil
    }

    /// Polls `condition` until it holds or `timeout` passes.
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }

    private func press(_ button: XCUIRemote.Button, pause: TimeInterval = 1) {
        remote.press(button)
        Thread.sleep(forTimeInterval: pause)
    }

    private func waitFor(_ element: XCUIElement, _ message: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        let found = element.waitForExistence(timeout: 15)
        XCTAssertTrue(found, "\(message); focused: \(focused.debugDescription)", file: file, line: line)
    }
}
