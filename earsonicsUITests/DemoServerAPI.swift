import CryptoKit
import Foundation

/// Direct calls to the demo server from the test runner, to check what the
/// app reported (now playing, scrobbles, saved queue) from the server's side.
enum DemoServerAPI {
    private static let base = "https://demo.navidrome.org/rest/"

    static func call(_ endpoint: String, _ params: [(String, String)] = []) async throws -> [String: Any] {
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        let token = Insecure.MD5.hash(data: Data(("demo" + salt).utf8)).map { String(format: "%02x", $0) }.joined()
        var comps = URLComponents(string: base + endpoint)!
        comps.queryItems = [("u", "demo"), ("t", token), ("s", String(salt)), ("v", "1.16.1"),
                            ("c", "earsonicsUITests"), ("f", "json")].map(URLQueryItem.init)
            + params.map(URLQueryItem.init)
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["subsonic-response"] as? [String: Any] ?? [:]
    }

    /// Entries in the server's "now playing" list reported by earsonics.
    static func earsonicsNowPlaying() async throws -> [[String: Any]] {
        let response = try await call("getNowPlaying.view")
        let entries = (response["nowPlaying"] as? [String: Any])?["entry"] as? [[String: Any]] ?? []
        return entries.filter { ($0["playerName"] as? String) == "earsonics" }
    }

    static func song(id: String) async throws -> [String: Any] {
        try await call("getSong.view", [("id", id)])["song"] as? [String: Any] ?? [:]
    }

    static func playQueue() async throws -> [String: Any]? {
        try await call("getPlayQueueByIndex.view")["playQueueByIndex"] as? [String: Any]
    }

    /// Saves a queue as this test runner (client "earsonicsUITests") — i.e.
    /// as "another app" from earsonics' point of view.
    static func savePlayQueue(ids: [String], currentIndex: Int, positionMs: Int) async throws {
        var params = ids.map { ("id", $0) }
        if !ids.isEmpty {
            params += [("currentIndex", String(currentIndex)), ("position", String(positionMs))]
        }
        _ = try await call("savePlayQueueByIndex.view", params)
    }

    static func randomSongs(_ count: Int) async throws -> [[String: Any]] {
        let response = try await call("getRandomSongs.view", [("size", String(count))])
        return (response["randomSongs"] as? [String: Any])?["song"] as? [[String: Any]] ?? []
    }

    /// The demo account's queue is shared by everyone trying clients against
    /// it; tests that change it put it back afterwards.
    struct SavedQueue {
        let ids: [String]
        let currentIndex: Int
        let positionMs: Int
    }

    static func snapshotQueue() async throws -> SavedQueue {
        let queue = try await playQueue() ?? [:]
        let ids = (queue["entry"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        return SavedQueue(ids: ids, currentIndex: queue["currentIndex"] as? Int ?? 0,
                          positionMs: queue["position"] as? Int ?? 0)
    }

    static func restoreQueue(_ saved: SavedQueue) async throws {
        try await savePlayQueue(ids: saved.ids, currentIndex: saved.currentIndex, positionMs: saved.positionMs)
    }
}

extension URLQueryItem {
    init(_ pair: (String, String)) { self.init(name: pair.0, value: pair.1) }
}
