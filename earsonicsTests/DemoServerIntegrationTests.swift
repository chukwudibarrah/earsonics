import Foundation
import Testing
@testable import earsonics

/// Requests against the public Navidrome demo (no playback). Needs network.
@MainActor
@Suite("Demo server integration")
struct DemoServerIntegrationTests {
    let demo = Server(name: "Demo", url: "https://demo.navidrome.org", username: "demo", password: "demo")

    @Test(arguments: [QueueContinuation.similarSongs, .sameArtist, .similarArtists, .sameGenre, .random])
    func everyAutoplayChoiceFindsSongs(_ choice: QueueContinuation) async throws {
        let seedSong = try #require(try await SubsonicClient.shared.getRandomSongs(size: 10, server: demo)
            .first { $0.genre?.isEmpty == false && $0.artistId != nil })
        let batch = await Autoplay(source: .server(demo))
            .nextBatch(for: choice, seed: Autoplay.Seed(seedSong), excluding: [seedSong.id])
        #expect(!batch.isEmpty, "no songs for \(choice) (with fallbacks)")
        #expect(batch.count <= Autoplay.batchSize)
        #expect(!batch.contains { $0.id == seedSong.id })
    }

    @Test func detectsTheDemosExtensions() async {
        let extensions = await SubsonicClient.shared.openSubsonicExtensions(server: demo)
        #expect(extensions.contains("formPost"))
        #expect(extensions.contains("indexBasedQueue"))
    }
}
