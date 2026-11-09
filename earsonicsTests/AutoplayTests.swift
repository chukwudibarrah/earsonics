import Foundation
import Testing
@testable import earsonics

@Suite("Autoplay")
struct AutoplayTests {

    /// A fake server: each source returns what the test gives it and records
    /// what it was asked for.
    final class FakeServer: @unchecked Sendable {
        var similar: [Song] = []
        var top: [Song] = []
        var artistSongs: [String: [Song]] = [:]
        var similarArtists: [Artist] = []
        var random: [Song] = []
        var genreRandom: [String: [Song]] = [:]
        var calls: [String] = []

        var source: Autoplay.Source {
            Autoplay.Source(
                similarSongs: { self.calls.append("similar:\($0)"); return self.similar },
                topSongs: { self.calls.append("top:\($0)"); return self.top },
                artistSongs: { self.calls.append("artist:\($0)"); return self.artistSongs[$0] ?? [] },
                similarArtists: { self.calls.append("similarArtists:\($0)"); return self.similarArtists },
                randomSongs: { genre in
                    self.calls.append("random:\(genre ?? "-")")
                    return genre.map { self.genreRandom[$0] ?? [] } ?? self.random
                })
        }
    }

    private let seed = Autoplay.Seed(makeSong("seed", artistId: "ar1", genre: "Jazz"))
    private func songs(_ prefix: String, _ n: Int) -> [Song] { (0..<n).map { makeSong("\(prefix)\($0)") } }
    private func artist(_ id: String) -> Artist { Artist(id: id, name: id, albumCount: nil, coverArt: nil) }

    @Test func planTriesTheChoiceThenTheFallbacks() {
        #expect(Autoplay.plan(for: .stop).isEmpty)
        #expect(Autoplay.plan(for: .similarSongs) == [.similarSongs, .sameArtist, .random])
        #expect(Autoplay.plan(for: .sameGenre) == [.sameGenre, .similarSongs, .sameArtist, .random])
        #expect(Autoplay.plan(for: .random) == [.random, .similarSongs, .sameArtist])
    }

    @Test func pickSkipsPlayedSongsAndDuplicatesAndCaps() {
        let candidates = songs("s", 30) + [makeSong("s1"), makeSong("played")]
        let picked = Autoplay.pick(candidates, excluding: ["played", "s0"], limit: 20)
        #expect(picked.count == 20)
        #expect(Set(picked.map(\.id)).count == 20)
        #expect(!picked.contains { $0.id == "played" || $0.id == "s0" })
    }

    @Test func usesTheChosenSourceWhenItHasSongs() async {
        let server = FakeServer()
        server.similar = songs("sim", 5)
        let batch = await Autoplay(source: server.source).nextBatch(for: .similarSongs, seed: seed, excluding: [])
        #expect(Set(batch.map(\.id)) == Set(server.similar.map(\.id)))
        #expect(server.calls == ["similar:seed"])
    }

    @Test func fallsBackWhenTheChoiceIsEmpty() async {
        // The demo server's situation: no similar artists.
        let server = FakeServer()
        server.random = songs("r", 3)
        let batch = await Autoplay(source: server.source).nextBatch(for: .similarArtists, seed: seed, excluding: [])
        // Similar artists → similar songs → same artist (no name on this
        // seed, so only its albums) → random, which has songs.
        #expect(server.calls == ["similarArtists:ar1", "similar:seed", "artist:ar1", "random:-"])
        #expect(Set(batch.map(\.id)) == ["r0", "r1", "r2"])
    }

    @Test func sameArtistCombinesTopSongsAndAlbums() async {
        let server = FakeServer()
        let named = Autoplay.Seed(Song(id: "seed", title: "t", album: nil, albumId: nil, artist: "Miles",
                                       artistId: "ar1", track: nil, discNumber: nil, year: nil, genre: nil,
                                       coverArt: nil, size: nil, contentType: nil, suffix: nil, duration: 200,
                                       bitRate: nil, path: nil, replayGain: nil))
        server.top = [makeSong("t1")]
        server.artistSongs["ar1"] = [makeSong("a1"), makeSong("a2")]
        let batch = await Autoplay(source: server.source).nextBatch(for: .sameArtist, seed: named, excluding: [])
        #expect(Set(batch.map(\.id)) == ["t1", "a1", "a2"])
        #expect(server.calls == ["top:Miles", "artist:ar1"])
    }

    @Test func similarArtistsUsesTheirSongs() async {
        let server = FakeServer()
        server.similarArtists = [artist("x"), artist("y")]
        server.artistSongs = ["x": [makeSong("x1")], "y": [makeSong("y1")]]
        let batch = await Autoplay(source: server.source).nextBatch(for: .similarArtists, seed: seed, excluding: [])
        #expect(Set(batch.map(\.id)) == ["x1", "y1"])
    }

    @Test func sameGenreAsksForThatGenre() async {
        let server = FakeServer()
        server.genreRandom["Jazz"] = [makeSong("j1")]
        let batch = await Autoplay(source: server.source).nextBatch(for: .sameGenre, seed: seed, excluding: [])
        #expect(batch.map(\.id) == ["j1"])
        #expect(server.calls == ["random:Jazz"])
    }

    @Test func alreadyPlayedSongsDontCountAsFound() async {
        let server = FakeServer()
        server.similar = [makeSong("old")]
        server.random = [makeSong("new")]
        let batch = await Autoplay(source: server.source).nextBatch(for: .similarSongs, seed: seed, excluding: ["old"])
        #expect(batch.map(\.id) == ["new"])
    }

    @Test func nothingAnywhereStops() async {
        let server = FakeServer()
        let batch = await Autoplay(source: server.source).nextBatch(for: .similarSongs, seed: seed, excluding: [])
        #expect(batch.isEmpty)
        #expect(server.calls == ["similar:seed", "artist:ar1", "random:-"])
    }

    @Test func stopFetchesNothing() async {
        let server = FakeServer()
        server.similar = songs("s", 3)
        let batch = await Autoplay(source: server.source).nextBatch(for: .stop, seed: seed, excluding: [])
        #expect(batch.isEmpty)
        #expect(server.calls.isEmpty)
    }

    @Test func defaultsMatchWhatWasAgreed() {
        #expect(QueueContinuation.defaultAfterAlbum == .stop)
        #expect(QueueContinuation.defaultAfterPlaylist == .similarSongs)
    }
}
