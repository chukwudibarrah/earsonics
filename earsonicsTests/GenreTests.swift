import Foundation
import Testing
@testable import earsonics
@testable import EarsonicsCore

@MainActor
@Suite("Genre mixes", .serialized)
struct GenreMixTests {
    private let key = PlaybackPreferences.afterPlaylistKey

    /// Runs `body` with "When a playlist or mix ends" set to `choice`, then
    /// puts the user's own setting back.
    private func with(_ choice: QueueContinuation?, _ body: () -> Void) {
        let saved = UserDefaults.standard.object(forKey: key)
        if let choice { UserDefaults.standard.set(choice.rawValue, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
        defer { UserDefaults.standard.set(saved, forKey: key) }
        body()
    }

    @Test func aGenreMixCarriesOnInItsGenre() {
        for choice in [nil, QueueContinuation.similarSongs, .random, .sameArtist] {
            with(choice) {
                #expect(PlaybackPreferences.continuation(for: .genre(name: "Jazz")) == .sameGenre,
                        "with \(String(describing: choice))")
            }
        }
    }

    @Test func stopStillStops() {
        with(.stop) {
            #expect(PlaybackPreferences.continuation(for: .genre(name: "Jazz")) == .stop)
        }
    }

    @Test func otherMixesKeepTheUsersChoice() {
        with(.random) {
            #expect(PlaybackPreferences.continuation(for: .mix) == .random)
            #expect(PlaybackPreferences.continuation(for: .playlist(id: "p")) == .random)
        }
    }

    @Test func genreMixesAreMixes() {
        #expect(PlayContext.genre(name: "Jazz").group == .playlistsAndMixes)
        #expect(PlayContext.genre(name: "Jazz").genreName == "Jazz")
        #expect(PlayContext.mix.genreName == nil)
    }

    /// The mix's genre seeds autoplay, not the last song's own tag (a song can
    /// carry several genres, e.g. "Hip-Hop; Rap").
    @Test func theMixGenreOverridesTheSongsTag() throws {
        let json = #"{"id": "s", "title": "Song", "genre": "Hip-Hop; Rap"}"#
        let song = try JSONDecoder().decode(Song.self, from: Data(json.utf8))
        #expect(Autoplay.Seed(song).genre == "Hip-Hop; Rap")
        #expect(Autoplay.Seed(song, genre: "Hip-Hop").genre == "Hip-Hop")
    }

    /// A genre mix's context survives saving and restoring the queue.
    @Test func theContextIsSavedWithTheQueue() throws {
        let data = try JSONEncoder().encode(PlayContext.genre(name: "Soul"))
        #expect(try JSONDecoder().decode(PlayContext.self, from: data) == .genre(name: "Soul"))
    }
}

@MainActor
@Suite("Genre list")
struct GenreListTests {
    @Test func decodesTheServersGenreList() throws {
        let json = #"""
        {"subsonic-response": {"status": "ok", "version": "1.16.1",
          "genres": {"genre": [{"value": "Rock", "songCount": 120, "albumCount": 10},
                               {"value": "Jazz", "songCount": 1, "albumCount": 1}]}}}
        """#
        let body = try SubsonicClient.shared.decodeResponse(Data(json.utf8))
        let genres = try #require(body.genres?.genre)
        #expect(genres.map(\.value) == ["Rock", "Jazz"])
        #expect(GenreTile.counts(genres[0]) == "120 songs · 10 albums")
        #expect(GenreTile.counts(genres[1]) == "1 song · 1 album")
    }
}

/// Against the test server (`TestServer`). Needs network.
@MainActor
@Suite("Genres on the server")
struct GenreServerTests {
    let server = Server(name: "Test server", url: TestServer.details.url,
                        username: TestServer.details.username, password: TestServer.details.password)

    @Test func aGenresAlbumsAndSongsLoad() async throws {
        let genres = try await SubsonicClient.shared.getGenres(server: server)
        let biggest = try #require(genres.max { ($0.songCount ?? 0) < ($1.songCount ?? 0) }, "no genres")
        let albums = try await SubsonicClient.shared.getAlbumsByGenre(genre: biggest.value, server: server)
        #expect(!albums.isEmpty, "no albums for \(biggest.value)")
        let songs = try await SubsonicClient.shared.getRandomSongs(size: 20, genre: biggest.value, server: server)
        #expect(!songs.isEmpty)
        #expect(songs.allSatisfy { $0.genre?.localizedCaseInsensitiveContains(biggest.value) == true },
                "random songs for \(biggest.value) include other genres")
    }
}
