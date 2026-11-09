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
final class earsonicsUITests: RemoteTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        // No restored queue, and nothing shared with other tests through the
        // demo account's server-side queue (tests run in parallel): these
        // checks are about navigation, with no music playing.
        app.launchArguments = ["-queueLaunchBehaviour", "startFresh", "-syncQueueWithServer", "NO"]
        launchToHome()
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
}

/// Settings choice rows open their list, save the choice, and leave the
/// other Settings pages working. Silent: starts with an empty queue.
final class SettingsNavigationUITests: RemoteTestCase {
    func testChoosingAQualityThenOpeningManageServers() {
        // No launch argument for the quality itself: arguments override what
        // the app saves, so the new choice could never show.
        app.launchArguments = ["-queueLaunchBehaviour", "startFresh", "-syncQueueWithServer", "NO"]
        launchToHome()
        selectTabFromRoot("Settings")

        for _ in 0..<6 where !focused.label.hasPrefix("Quality") { press(.down, pause: 0.5) }
        XCTAssertTrue(focused.label.hasPrefix("Quality"), "couldn't reach Quality; focused: \(focused.label)")

        choose("MP3 320 kbps")
        XCTAssertTrue(focused.label.contains("MP3 320 kbps"), "Quality didn't update: \(focused.label)")
        choose("Original (lossless)")   // leave the setting as it was
        XCTAssertTrue(focused.label.contains("Original (lossless)"), "Quality didn't update: \(focused.label)")

        // Other pages still open with their content.
        for _ in 0..<6 where !focused.label.contains("Manage servers") { press(.up, pause: 0.5) }
        press(.select, pause: 1.5)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add server'")).firstMatch
                        .waitForExistence(timeout: 5),
                      "Manage servers opened blank after using a choice list")
    }

    /// From the focused Quality row: opens its choices, picks `name`, and
    /// waits to be back on the row.
    private func choose(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        press(.select, pause: 1.5)
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 5),
                      "the Quality choices didn't open (blank page?)", file: file, line: line)
        for _ in 0..<4 where !focused.label.hasPrefix(name) { press(.down, pause: 0.5) }
        for _ in 0..<4 where !focused.label.hasPrefix(name) { press(.up, pause: 0.5) }
        XCTAssertTrue(focused.label.hasPrefix(name), "couldn't move to \(name); focused: \(focused.label)",
                      file: file, line: line)
        press(.select, pause: 1.5)
        XCTAssertTrue(waitUntil(timeout: 5) { self.focused.label.hasPrefix("Quality") },
                      "didn't return to Settings; focused: \(focused.label)", file: file, line: line)
    }
}
