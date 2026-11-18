import XCTest

/// Up reaches the Now Playing pill from the top of every tab, wherever focus
/// is (it used to work only from items below the pill, on the right), and
/// Down goes back into the page. Paused right after starting, so silent.
final class NowPlayingFocusUITests: RemoteTestCase {
    func testUpReachesNowPlayingFromEveryTab() {
        app.launchArguments = ["-queueLaunchBehaviour", "startFresh", "-syncQueueWithServer", "NO"]
        launchToHome()
        startPlayingFirstHomeAlbum()
        pressPlayPause(expecting: "paused")
        press(.menu, pause: 1.5)   // back to Home's shelves

        // Where focus lands on each tab, plus the spots reported not to work:
        // Home's third album and Tracks' Shuffle play (moves right first).
        let cases: [(tab: String, rights: Int)] = [("Home", 0), ("Home", 2), ("Artists", 0), ("Genres", 0), ("Tracks", 0),
                                                   ("Tracks", 1), ("Playlists", 0), ("Favourites", 0), ("Settings", 0)]
        for (tab, rights) in cases {
            selectTabFromRoot(tab)
            for _ in 0..<rights { press(.right, pause: 0.6) }
            let start = focused.label
            for _ in 0..<8 where !miniPlayer.hasFocus { press(.up, pause: 0.6) }
            XCTAssertTrue(miniPlayer.hasFocus, "\(tab): Up didn't reach Now Playing from “\(start)”; focused: \(focused.debugDescription)")
            // Down goes back into the page (to the nearest item below the
            // pill; SwiftUI doesn't remember where focus came from).
            press(.down, pause: 1)
            XCTAssertTrue(focused.exists && !miniPlayer.hasFocus && focusedSidebarTab == nil,
                          "\(tab): Down from Now Playing didn't go back into the page; focused: \(focused.debugDescription)")
        }
    }
}
