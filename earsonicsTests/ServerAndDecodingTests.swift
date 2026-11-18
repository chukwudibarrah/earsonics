import Foundation
import Testing
@testable import earsonics
@testable import EarsonicsCore

@MainActor
@Suite("Server URL checks")
struct ServerURLCheckTests {
    @Test(arguments: [
        "https://music.example.com",
        "https://music.example.com:4533/navidrome",
        "http://192.168.1.20:4533",
        "http://10.0.0.5",
        "http://172.16.0.1", "http://172.31.255.255",
        "http://127.0.0.1:4533",
        "http://169.254.10.10",
        "http://100.64.0.1",          // Tailscale (CGNAT)
        "http://localhost:4533",
        "http://nas:4533",            // single-word host
        "http://music.local",         // Bonjour
        "http://[::1]:4533",
        "http://[fd12:3456::1]",
        "  https://music.example.com  ",
    ])
    func acceptable(_ url: String) {
        #expect(Server.check(url: url) == .ok)
    }

    @Test(arguments: ["http://203.0.113.7", "http://172.32.0.1", "http://100.128.0.1", "http://[2001:db8::1]"])
    func unencryptedOverTheInternet(_ url: String) {
        #expect(Server.check(url: url) == .unencryptedPublic)
    }

    @Test(arguments: ["http://music.example.com", "http://example.org:4533"])
    func plainHTTPToADomainIsBlocked(_ url: String) {
        #expect(Server.check(url: url) == .blockedHTTPDomain)
    }

    @Test(arguments: ["", "https://", "ftp://music.example.com", "music.example.com", "not a url"])
    func invalid(_ url: String) {
        #expect(Server.check(url: url) == .invalid)
    }

    @Test func baseURLDropsTrailingSlashesAndSpaces() {
        let server = Server(name: "x", url: "  https://music.example.com/navidrome//  ", username: "u", password: "p")
        #expect(server.baseURL == "https://music.example.com/navidrome")
    }
}

/// Replies in the shapes different servers send, decoded by the app's real
/// decoder. Trimmed from real responses.
@MainActor
@Suite("Decoding server replies")
struct ResponseDecodingTests {
    private func decode(_ json: String) throws -> SubsonicResponseBody {
        try SubsonicClient.shared.decodeResponse(Data(json.utf8))
    }

    /// Navidrome: OpenSubsonic extras (unknown fields), nanosecond dates,
    /// ReplayGain, disc numbers.
    @Test func navidromeAlbum() throws {
        let body = try decode("""
        {"subsonic-response":{"status":"ok","version":"1.16.1","type":"navidrome","serverVersion":"0.64.2","openSubsonic":true,
         "album":{"id":"5xhN","name":"NCS: Infinity","artist":"Various Artists","artistId":"ar1","coverArt":"al-5xhN","songCount":2,
          "duration":400,"year":2015,"genre":"Electronic","starred":"2026-11-01T12:52:06.49936326Z","genres":[],"musicBrainzId":"",
          "song":[{"id":"s1","title":"Levitate","album":"NCS: Infinity","albumId":"5xhN","artist":"JPB","artistId":"ar1","track":9,
           "discNumber":1,"year":2015,"coverArt":"mf-s1","size":7887685,"contentType":"audio/mpeg","suffix":"mp3","duration":196,
           "bitRate":320,"path":"a/b.mp3","bpm":138,"isrc":[],"moods":[],"replayGain":{"trackGain":-2.5,"albumGain":-3,"trackPeak":0.98,"albumPeak":1},
           "artists":[{"id":"ar1","name":"JPB"}],"played":"2026-11-01T01:54:48.045019696Z"},
           {"id":"s2","title":"Two","discNumber":2,"track":1,"duration":204}]}}}
        """)
        let album = try #require(body.album?.asAlbum)
        #expect(album.name == "NCS: Infinity")
        #expect(album.starred != nil && album.starred != Date(timeIntervalSince1970: 0))
        let songs = try #require(album.songs)
        #expect(songs.map(\.id) == ["s1", "s2"])
        #expect(songs[0].replayGain?.trackGain == -2.5)
        #expect(songs[1].discNumber == 2)
    }

    /// gonic: prefixed string ids, few optional fields, dates without a fraction.
    @Test func gonicStarred() throws {
        let body = try decode("""
        {"subsonic-response":{"status":"ok","version":"1.15.0","type":"gonic","serverVersion":"0.16.4",
         "starred2":{"artist":[{"id":"ar-12","name":"Boards of Canada","albumCount":3}],
          "album":[{"id":"al-77","name":"Geogaddi","artist":"Boards of Canada","artistId":"ar-12","created":"2024-03-01T10:00:00Z"}],
          "song":[{"id":"tr-901","title":"Music Is Math","album":"Geogaddi","albumId":"al-77","starred":"2024-05-05T08:30:00Z"}]}}}
        """)
        let starred = try #require(body.starred2)
        #expect(starred.artist?.first?.id == "ar-12")
        #expect(starred.album?.first?.name == "Geogaddi")
        let song = try #require(starred.song?.first)
        #expect(song.id == "tr-901")
        #expect(song.starred != nil && song.starred != Date(timeIntervalSince1970: 0))
        #expect(song.duration == nil)
    }

    /// Airsonic: millisecond dates with an offset, lyrics from the legacy endpoint.
    @Test func airsonicSearchAndLyrics() throws {
        let search = try decode("""
        {"subsonic-response":{"status":"ok","version":"1.15.0",
         "searchResult3":{"song":[{"id":"1043","title":"Teardrop","artist":"Massive Attack","duration":330,
          "starred":"2021-07-01T09:15:30.123+0000","suffix":"flac","contentType":"audio/flac"}]}}}
        """)
        let song = try #require(search.searchResult3?.song?.first)
        #expect(song.id == "1043")
        #expect(song.isLossless)
        #expect(song.starred != nil && song.starred != Date(timeIntervalSince1970: 0))

        let lyrics = try decode("""
        {"subsonic-response":{"status":"ok","version":"1.15.0",
         "lyrics":{"artist":"Massive Attack","title":"Teardrop","value":"Love, love is a verb"}}}
        """)
        #expect(lyrics.lyrics?.value == "Love, love is a verb")
    }

    /// An unreadable date mustn't fail the whole reply.
    @Test func oddDateDoesNotFailTheReply() throws {
        let body = try decode("""
        {"subsonic-response":{"status":"ok","version":"1.16.1",
         "albumList2":{"album":[{"id":"a","name":"A","created":"sometime"},{"id":"b","name":"B"}]}}}
        """)
        #expect(body.albumList2?.album?.map(\.id) == ["a", "b"])
    }

    @Test func failedStatusBecomesAReadableError() throws {
        do {
            _ = try decode("""
            {"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":40,"message":"Wrong username or password"}}}
            """)
            Issue.record("a failed reply should throw")
        } catch let error as SubsonicError {
            #expect(error.errorDescription == "Wrong username or password.")
        }
    }
}

/// Servers saved by a version before 1.06 kept their passwords in the
/// settings store; loading must move them into the Keychain and strip them
/// from the settings.
@MainActor
@Suite("Password migration to the Keychain", .serialized)
struct PasswordMigrationTests {
    @Test func plaintextPasswordsMoveToTheKeychain() throws {
        let suiteName = "earsonics-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let server = Server(name: "Old", url: "https://music.example.com", username: "me", password: "hunter2")
        defer { KeychainHelper.delete(account: server.id.uuidString) }
        defaults.set(try JSONEncoder().encode([server]), forKey: ServerStore.serversKey)

        let store = ServerStore(defaults: defaults)

        // Loaded with its password…
        #expect(store.servers.first?.password == "hunter2")
        #expect(store.activeServer?.id == server.id)
        // …which is now in the Keychain…
        #expect(KeychainHelper.read(account: server.id.uuidString) == "hunter2")
        // …and no longer in the settings store.
        let saved = try JSONDecoder().decode([Server].self, from: try #require(defaults.data(forKey: ServerStore.serversKey)))
        #expect(saved.first?.password == "")
    }

    @Test func passwordsAlreadyInTheKeychainAreUsed() throws {
        let suiteName = "earsonics-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let server = Server(name: "New", url: "https://music.example.com", username: "me", password: "")
        defer { KeychainHelper.delete(account: server.id.uuidString) }
        KeychainHelper.save("from-keychain", account: server.id.uuidString)
        defaults.set(try JSONEncoder().encode([server]), forKey: ServerStore.serversKey)

        let store = ServerStore(defaults: defaults)
        #expect(store.servers.first?.password == "from-keychain")
    }
}
