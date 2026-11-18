import XCTest

/// The Genres tab: its pages open and switch tabs like every other tab's,
/// and Shuffle plays songs from the genre (checked on the server).
final class GenresUITests: RemoteTestCase {
    /// Opens Genres and the first (largest) genre; returns its name.
    @discardableResult
    private func openFirstGenre() -> String {
        selectTabFromRoot("Genres")
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS ' songs · '")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "no genre tiles")
        for _ in 0..<3 where !focused.label.contains(" songs · ") { press(.down) }
        let name = focused.label.components(separatedBy: ",").first ?? ""
        press(.select)
        waitFor(app.buttons["Shuffle"], "the genre page didn't open")
        XCTAssertTrue(app.staticTexts[name].exists, "the page isn't for \(name)")
        return name
    }

    func testGenrePageThenSwitchTab() {
        app.launchArguments = ["-queueLaunchBehaviour", "startFresh", "-syncQueueWithServer", "NO"]
        launchToHome()
        openFirstGenre()
        switchTabFromDetail(to: "Home", detailMarker: app.buttons["Shuffle"])
    }

    func testAnAlbumOpensFromAGenre() {
        app.launchArguments = ["-queueLaunchBehaviour", "startFresh", "-syncQueueWithServer", "NO"]
        launchToHome()
        openFirstGenre()
        openFirstAlbumFromArtistPage()   // same layout: buttons, then a grid of albums
        switchTabFromDetail(to: "Home", detailMarker: app.buttons["Play next"])
    }

    /// Plays a few seconds of audio.
    func testShufflePlaysTheGenre() async throws {
        continueAfterFailure = true   // see RemoteTestCase.continueAfterFailure
        app.launchArguments = ["-queueLaunchBehaviour", "startFresh", "-syncQueueWithServer", "NO"]
        launchToHome()
        let genre = openFirstGenre()
        for _ in 0..<3 where focused.label != "Shuffle" { press(.right, pause: 0.5) }
        XCTAssertEqual(focused.label, "Shuffle")
        press(.select)
        XCTAssertTrue(waitForMiniPlayer(containing: "playing", timeout: 30), "playback didn't start")

        var entry: [String: Any]?
        for _ in 0..<15 where entry == nil {
            entry = try await DemoServerAPI.earsonicsNowPlaying().first
            if entry == nil { try await Task.sleep(for: .seconds(1)) }
        }
        let playingGenre = try XCTUnwrap(entry?["genre"] as? String, "the server didn't list a playing song with a genre")
        XCTAssertTrue(playingGenre.localizedCaseInsensitiveContains(genre), "playing a \(playingGenre) song, not \(genre)")
        pressPlayPause(expecting: "paused")
    }
}
