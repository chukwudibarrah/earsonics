import XCTest

/// Playback driven by the Siri Remote against the demo server. Needs network
/// access; the demo streams real audio.
final class PlaybackUITests: RemoteTestCase {

    /// The remote's play/pause button must toggle playback once per press —
    /// wherever focus is, including on song rows (which also handle the
    /// press) and on a screen that has nothing to do with playback.
    func testPlayPauseButtonTogglesFromAnywhere() {
        launchToHome()
        startPlayingFirstHomeAlbum()

        // Focus on the album page's Play button.
        pressPlayPause(expecting: "paused")
        pressPlayPause(expecting: "playing")

        // Focus on a song row.
        for _ in 0..<3 { press(.right, pause: 0.6) }
        XCTAssertTrue(focused.label.contains(":"), "expected a song row (with a duration); focused: \(focused.debugDescription)")
        pressPlayPause(expecting: "paused")
        pressPlayPause(expecting: "playing")

        // Back on Home.
        press(.menu, pause: 1.5)
        XCTAssertTrue(app.staticTexts["Keep spinning"].waitForExistence(timeout: 5))
        pressPlayPause(expecting: "paused")
        pressPlayPause(expecting: "playing")
    }

    /// End to end with the server: "now playing" is reported as soon as a
    /// track starts, and the play is recorded once half of it has been heard
    /// — not before. Takes about two minutes of real playback.
    func testNowPlayingAndScrobbleReachTheServer() async throws {
        launchToHome()
        startPlayingFirstHomeAlbum()
        let title = miniPlayerValue.components(separatedBy: ", ").first ?? ""

        // 1. Now playing.
        var entry: [String: Any]?
        for _ in 0..<20 where entry == nil {
            entry = try await DemoServerAPI.earsonicsNowPlaying().first { ($0["title"] as? String) == title }
            if entry == nil { try await Task.sleep(for: .seconds(1)) }
        }
        let nowPlaying = try XCTUnwrap(entry, "the server never listed “\(title)” as playing in earsonics")
        let songID = try XCTUnwrap(nowPlaying["id"] as? String)
        let duration = try XCTUnwrap(nowPlaying["duration"] as? Int)
        let threshold = min(Double(duration) / 2, 240)
        let before = try await DemoServerAPI.song(id: songID)["playCount"] as? Int ?? 0

        // 2. Not counted early.
        try await Task.sleep(for: .seconds(threshold * 0.6))
        let early = try await DemoServerAPI.song(id: songID)["playCount"] as? Int ?? 0
        XCTAssertEqual(early, before, "the play was recorded before half the track was heard")

        // 3. Counted once past the threshold (plus slack for buffering and
        // the half-second tick).
        var after = early
        let deadline = Date().addingTimeInterval(threshold * 0.4 + 30)
        while after == before, Date() < deadline {
            try await Task.sleep(for: .seconds(3))
            after = try await DemoServerAPI.song(id: songID)["playCount"] as? Int ?? 0
        }
        XCTAssertEqual(after, before + 1, "the play wasn't recorded once (play count \(before) → \(after))")
    }
}
