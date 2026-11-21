import XCTest

extension XCUIApplication {
    /// A tab by name: in the tab bar along the bottom on iPhone, or among the
    /// tab buttons along the top on iPad.
    @MainActor
    func tab(_ name: String) -> XCUIElement {
        let inTabBar = tabBars.buttons[name]
        if inTabBar.exists { return inTabBar }
        return buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }
}

extension XCUIElement {
    /// Taps a page's Play until playback starts (the mini player appears).
    /// A page can still be settling its layout as its songs arrive, and a
    /// tap at that moment lands where the button was.
    @MainActor
    func tapToPlay(showing miniPlayer: XCUIElement, timeout: TimeInterval = 20) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if label == "Play" && isHittable { tap() }
            if miniPlayer.waitForExistence(timeout: 5) { return }
        } while Date() < deadline
    }
}
