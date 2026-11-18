import Foundation

/// The Subsonic server the tests run against.
///
/// To use your own server, put its details in `TestServer.local.json` at the
/// top of the repository (next to `earsonics.xcodeproj`):
///
///     { "url": "https://music.example.com", "username": "…", "password": "…" }
///
/// That file is git-ignored: the repository is public, so a real address or
/// password must never be committed. Without the file, tests use the public
/// Navidrome demo, which anyone can use and change (see `isPublicDemo`).
/// `earsonicsUITests/TestServer.swift` is a copy of this file for the UI tests.
enum TestServer {
    struct Details: Decodable {
        let url: String
        let username: String
        let password: String
    }

    static let publicDemo = Details(url: "https://demo.navidrome.org", username: "demo", password: "demo")

    static let details: Details = {
        // Simulator test processes can read the Mac's file system, so the
        // file is found from this source file's location.
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TestServer.local.json")
        guard let data = try? Data(contentsOf: file) else { return publicDemo }
        guard let local = try? JSONDecoder().decode(Details.self, from: data) else {
            fatalError("TestServer.local.json must contain \"url\", \"username\" and \"password\"")
        }
        return local
    }()

    /// True when using the public demo, where other people's apps can change
    /// shared state (the saved queue, play counts) mid-test.
    static var isPublicDemo: Bool { details.url == publicDemo.url }
}
