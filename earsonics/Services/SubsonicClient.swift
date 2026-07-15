// Services/SubsonicClient.swift
import Foundation
import CryptoKit
import Combine

// MARK: - Subsonic REST API Client
class SubsonicClient: ObservableObject {
    static let shared = SubsonicClient()

    private let apiVersion = "1.16.1"
    private let clientName  = "earsonics"
    private let jsonFormat  = "json"

    // Current server (set by AppState)
    var server: Server?

    /// Dedicated session for API calls. The timeout stays generous on purpose:
    /// a slow server (disk spinning up, remote link) can legitimately take a
    /// long time to answer, and aborting such a request only converts a slow
    /// success into a hard failure. Recovery from *dead* pooled connections is
    /// handled by the hedged duplicate request in `requestData`, not by this
    /// timeout. Responses carry a per-request auth salt so they're never
    /// cacheable.
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = iso.date(from: str) { return date }
            // fallback
            let iso2 = ISO8601DateFormatter()
            if let date = iso2.date(from: str) { return date }
            
            // Subsonic standard uses different custom date formats
            let formatter1 = DateFormatter()
            formatter1.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            if let date = formatter1.date(from: str) { return date }
            
            let formatter2 = DateFormatter()
            formatter2.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            if let date = formatter2.date(from: str) { return date }

            // Just fail gracefully without throwing a hard exception if possible
            return Date(timeIntervalSince1970: 0) 
        }
        return d
    }()

    // MARK: - Auth params
    private func authParams(for srv: Server) -> [URLQueryItem] {
        let salt = randomSalt()
        let token = md5(srv.password + salt)
        return [
            URLQueryItem(name: "u", value: srv.username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "c", value: clientName),
            URLQueryItem(name: "f", value: jsonFormat)
        ]
    }

    private func randomSalt(length: Int = 16) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private func md5(_ str: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(str.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - URL builder
    func url(endpoint: String, params: [URLQueryItem] = [], server srv: Server? = nil) -> URL? {
        guard let s = srv ?? server else { return nil }
        var comps = URLComponents(string: "\(s.baseURL)/rest/\(endpoint)")
        var items = authParams(for: s)
        items.append(contentsOf: params)
        comps?.queryItems = items
        return comps?.url
    }

    // MARK: - Stream URL
    /// Builds a stream URL for the given quality. `.original` requests the raw
    /// library file; the MP3 qualities ask the server to transcode.
    func streamURL(songId: String, quality: StreamQuality = .original, server srv: Server? = nil) -> URL? {
        var params = [URLQueryItem(name: "id", value: songId)]
        params.append(contentsOf: quality.streamParams)
        return url(endpoint: "stream.view", params: params, server: srv)
    }

    // MARK: - Cover Art URL
    func coverArtURL(id: String, size: Int? = nil, server srv: Server? = nil) -> URL? {
        var params = [URLQueryItem(name: "id", value: id)]
        if let s = size { params.append(URLQueryItem(name: "size", value: "\(s)")) }
        return url(endpoint: "getCoverArt.view", params: params, server: srv)
    }

    // MARK: - Generic request
    private func fetch(endpoint: String, params: [URLQueryItem] = [], server srv: Server? = nil, hedged: Bool = true) async throws -> SubsonicResponseBody {
        guard let u = url(endpoint: endpoint, params: params, server: srv) else {
            throw SubsonicError.invalidURL
        }
        let data = try await requestData(from: u, hedged: hedged)
        // Parse subsonic response wrapper
        let wrapper = try decoder.decode(SubsonicResponse<SubsonicResponseBody>.self, from: data)
        guard wrapper.subsonicResponse.status == "ok" else {
            throw SubsonicError.serverError(wrapper.subsonicResponse.error?.message ?? "Unknown error")
        }
        return wrapper.subsonicResponse
    }

    /// How long the first attempt gets before a duplicate request is hedged on
    /// a fresh connection. A healthy server answers well within this; a dead
    /// pooled connection never will, so recovery arrives ~this fast.
    private static let hedgeDelayNanos: UInt64 = 3_000_000_000

    /// Fetches data with a *hedged* duplicate rather than a timeout-and-retry.
    ///
    /// After the app sits idle or is suspended, every keep-alive connection in
    /// the session's pool can be silently dead — and the Home screen opens
    /// several at once, so a single retry can land on a second dead socket and
    /// fail too. Aborting the first attempt is also wrong when the server is
    /// merely slow: that turns a late success into a hard failure.
    ///
    /// So instead: the first attempt is left running, and if it hasn't
    /// answered within `hedgeDelayNanos` a duplicate fires on a brand-new
    /// single-use session (a guaranteed-fresh connection — the same thing
    /// backing out and reopening a screen used to achieve by hand). Whichever
    /// attempt finishes first wins; the loser is cancelled, which also tears
    /// down its dead socket so the pool progressively heals.
    ///
    /// `hedged: false` performs one attempt with a single sequential retry on
    /// a fresh connection instead — for mutating endpoints, where two racing
    /// copies of the same call could double-apply.
    private func requestData(from url: URL, hedged: Bool = true) async throws -> Data {
        guard hedged else {
            do {
                return try await Self.perform(url, on: session)
            } catch let error as URLError where error.code != .cancelled {
                return try await Self.performOnFreshConnection(url)
            }
        }

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { [session] in
                try await Self.perform(url, on: session)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.hedgeDelayNanos)
                return try await Self.performOnFreshConnection(url)
            }
            defer { group.cancelAll() }

            var lastNetworkError: Error? = nil
            while let outcome = await group.nextResult() {
                switch outcome {
                case .success(let data):
                    return data
                case .failure(let error as URLError):
                    // A losing attempt is cancelled by the winner — ignore it.
                    // Other network errors: let the remaining attempt play out.
                    if error.code != .cancelled { lastNetworkError = error }
                case .failure(is CancellationError):
                    continue
                case .failure(let error):
                    // HTTP/server errors mean the connection works; a duplicate
                    // request would get the same answer, so fail fast.
                    throw error
                }
            }
            throw lastNetworkError ?? CancellationError()
        }
    }

    private static func perform(_ url: URL, on session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw SubsonicError.httpError(http.statusCode)
        }
        return data
    }

    /// One request on a throwaway session: guarantees a fresh connection that
    /// no stale pooled socket can stall.
    private static func performOnFreshConnection(_ url: URL) async throws -> Data {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.urlCache = nil
        let fresh = URLSession(configuration: cfg)
        defer { fresh.finishTasksAndInvalidate() }
        return try await perform(url, on: fresh)
    }

    // MARK: - Ping
    func ping(server srv: Server) async throws -> Bool {
        let r = try await fetch(endpoint: "ping.view", server: srv)
        return r.status == "ok"
    }

    // MARK: - Artists
    func getArtists(server srv: Server? = nil) async throws -> [Artist] {
        let r = try await fetch(endpoint: "getArtists.view", server: srv)
        let indexes = r.artists?.index ?? []
        return indexes.flatMap { $0.artist ?? [] }
    }

    // MARK: - Artist detail
    func getArtist(id: String, server srv: Server? = nil) async throws -> Artist {
        let r = try await fetch(endpoint: "getArtist.view",
                                params: [URLQueryItem(name: "id", value: id)], server: srv)
        guard let artist = r.artist else { throw SubsonicError.missingData }
        return artist.asArtist
    }

    // MARK: - Artist albums
    func getArtistAlbums(artistId: String, server srv: Server? = nil) async throws -> [Album] {
        let r = try await fetch(endpoint: "getArtist.view",
                                params: [URLQueryItem(name: "id", value: artistId)], server: srv)
        return r.artist?.albumList ?? []
    }

    // MARK: - Album detail
    func getAlbum(id: String, server srv: Server? = nil) async throws -> Album {
        let r = try await fetch(endpoint: "getAlbum.view",
                                params: [URLQueryItem(name: "id", value: id)], server: srv)
        guard let album = r.album else { throw SubsonicError.missingData }
        return album.asAlbum
    }

    // MARK: - Recent / Random Albums
    func getAlbumList(type: String = "recent", size: Int = 50, offset: Int = 0, server srv: Server? = nil) async throws -> [Album] {
        let r = try await fetch(endpoint: "getAlbumList2.view",
                                params: [URLQueryItem(name: "type", value: type),
                                         URLQueryItem(name: "size", value: "\(size)"),
                                         URLQueryItem(name: "offset", value: "\(offset)")],
                                server: srv)
        return r.albumList2?.album ?? []
    }

    // MARK: - Song detail
    func getSong(id: String, server srv: Server? = nil) async throws -> Song {
        let r = try await fetch(endpoint: "getSong.view",
                                params: [URLQueryItem(name: "id", value: id)], server: srv)
        guard let song = r.song else { throw SubsonicError.missingData }
        return song
    }

    // MARK: - Playlists
    func getPlaylists(server srv: Server? = nil) async throws -> [Playlist] {
        let r = try await fetch(endpoint: "getPlaylists.view", server: srv)
        return r.playlists?.playlist ?? []
    }

    func getPlaylist(id: String, server srv: Server? = nil) async throws -> Playlist {
        let r = try await fetch(endpoint: "getPlaylist.view",
                                params: [URLQueryItem(name: "id", value: id)], server: srv)
        guard let pl = r.playlist else { throw SubsonicError.missingData }
        return pl
    }

    func createPlaylist(name: String, songIds: [String] = [], server srv: Server? = nil) async throws -> Playlist {
        var params = [URLQueryItem(name: "name", value: name)]
        params += songIds.map { URLQueryItem(name: "songId", value: $0) }
        let r = try await fetch(endpoint: "createPlaylist.view", params: params, server: srv, hedged: false)
        guard let pl = r.playlist else { throw SubsonicError.missingData }
        return pl
    }

    func updatePlaylist(id: String, name: String? = nil, comment: String? = nil,
                        songIdsToAdd: [String] = [], indexesToRemove: [Int] = [],
                        server srv: Server? = nil) async throws {
        var params = [URLQueryItem(name: "playlistId", value: id)]
        if let n = name { params.append(URLQueryItem(name: "name", value: n)) }
        if let c = comment { params.append(URLQueryItem(name: "comment", value: c)) }
        params += songIdsToAdd.map { URLQueryItem(name: "songIdToAdd", value: $0) }
        params += indexesToRemove.map { URLQueryItem(name: "songIndexToRemove", value: "\($0)") }
        _ = try await fetch(endpoint: "updatePlaylist.view", params: params, server: srv, hedged: false)
    }

    func deletePlaylist(id: String, server srv: Server? = nil) async throws {
        _ = try await fetch(endpoint: "deletePlaylist.view",
                            params: [URLQueryItem(name: "id", value: id)], server: srv, hedged: false)
    }

    // MARK: - Starred
    func getStarred(server srv: Server? = nil) async throws -> (artists: [Artist], albums: [Album], songs: [Song]) {
        let r = try await fetch(endpoint: "getStarred2.view", server: srv)
        return (r.starred2?.artist ?? [], r.starred2?.album ?? [], r.starred2?.song ?? [])
    }

    func star(songId: String? = nil, albumId: String? = nil, artistId: String? = nil, server srv: Server? = nil) async throws {
        var params: [URLQueryItem] = []
        if let id = songId   { params.append(URLQueryItem(name: "id", value: id)) }
        if let id = albumId  { params.append(URLQueryItem(name: "albumId", value: id)) }
        if let id = artistId { params.append(URLQueryItem(name: "artistId", value: id)) }
        _ = try await fetch(endpoint: "star.view", params: params, server: srv, hedged: false)
    }

    func unstar(songId: String? = nil, albumId: String? = nil, artistId: String? = nil, server srv: Server? = nil) async throws {
        var params: [URLQueryItem] = []
        if let id = songId   { params.append(URLQueryItem(name: "id", value: id)) }
        if let id = albumId  { params.append(URLQueryItem(name: "albumId", value: id)) }
        if let id = artistId { params.append(URLQueryItem(name: "artistId", value: id)) }
        _ = try await fetch(endpoint: "unstar.view", params: params, server: srv, hedged: false)
    }

    // MARK: - Scrobble
    func scrobble(id: String, submission: Bool = true, server srv: Server? = nil) async throws {
        _ = try await fetch(endpoint: "scrobble.view",
                            params: [URLQueryItem(name: "id", value: id),
                                     URLQueryItem(name: "submission", value: submission ? "true" : "false")],
                            server: srv, hedged: false)
    }

    // MARK: - Lyrics
    func getLyrics(artist: String? = nil, title: String? = nil, server srv: Server? = nil) async throws -> Lyrics? {
        var params: [URLQueryItem] = []
        if let a = artist { params.append(URLQueryItem(name: "artist", value: a)) }
        if let t = title  { params.append(URLQueryItem(name: "title", value: t)) }
        let r = try await fetch(endpoint: "getLyrics.view", params: params, server: srv)
        return r.lyrics
    }

    func getLyricsBySongId(id: String, server srv: Server? = nil) async throws -> [StructuredLyrics] {
        let r = try await fetch(endpoint: "getLyricsBySongId.view",
                                params: [URLQueryItem(name: "id", value: id)], server: srv)
        return r.lyricsList?.structuredLyrics ?? []
    }

    // MARK: - Search
    func search(query: String, artistCount: Int = 10, albumCount: Int = 10, songCount: Int = 20,
                songOffset: Int = 0, server srv: Server? = nil) async throws -> SearchResult {
        let params: [URLQueryItem] = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "artistCount", value: "\(artistCount)"),
            URLQueryItem(name: "albumCount", value: "\(albumCount)"),
            URLQueryItem(name: "songCount", value: "\(songCount)"),
            URLQueryItem(name: "songOffset", value: "\(songOffset)")
        ]
        let r = try await fetch(endpoint: "search3.view", params: params, server: srv)
        return SearchResult(
            artists: r.searchResult3?.artist ?? [],
            albums:  r.searchResult3?.album ?? [],
            songs:   r.searchResult3?.song ?? []
        )
    }

    // MARK: - Genres
    func getGenres(server srv: Server? = nil) async throws -> [Genre] {
        let r = try await fetch(endpoint: "getGenres.view", server: srv)
        return r.genres?.genre ?? []
    }

    // MARK: - Songs by genre
    func getSongsByGenre(genre: String, count: Int = 50, offset: Int = 0, server srv: Server? = nil) async throws -> [Song] {
        let r = try await fetch(endpoint: "getSongsByGenre.view",
                                params: [URLQueryItem(name: "genre", value: genre),
                                         URLQueryItem(name: "count", value: "\(count)"),
                                         URLQueryItem(name: "offset", value: "\(offset)")],
                                server: srv)
        return r.songsByGenre?.song ?? []
    }

    // MARK: - Random songs
    func getRandomSongs(size: Int = 50, server srv: Server? = nil) async throws -> [Song] {
        let r = try await fetch(endpoint: "getRandomSongs.view",
                                params: [URLQueryItem(name: "size", value: "\(size)")], server: srv)
        return r.randomSongs?.song ?? []
    }
}

// MARK: - Errors
enum SubsonicError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case serverError(String)
    case missingData

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .httpError(let code): return "HTTP error \(code)"
        case .serverError(let msg): return "Server error: \(msg)"
        case .missingData: return "Missing data in response"
        }
    }
}

// MARK: - Response Wrappers
struct SubsonicResponse<T: Decodable>: Decodable {
    let subsonicResponse: T

    // The actual JSON key is "subsonic-response" (hyphen), NOT underscore.
    // convertFromSnakeCase only handles underscores, so we need explicit CodingKeys.
    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

struct SubsonicError_: Decodable {
    let code: Int?
    let message: String?
}

// A catch-all response body covering all possible fields
struct SubsonicResponseBody: Decodable {
    let status: String
    let version: String?
    let error: SubsonicError_?

    // Browse
    let artists: ArtistsWrapper?
    let artist: ArtistDetail?
    let album: AlbumDetail?
    let song: Song?

    // Album lists
    let albumList2: AlbumListWrapper?

    // Playlists
    let playlists: PlaylistsWrapper?
    let playlist: Playlist?

    // Starred
    let starred2: Starred2?

    // Search
    let searchResult3: SearchResult3?

    // Lyrics
    let lyrics: Lyrics?
    let lyricsList: LyricsListWrapper?

    // Genres
    let genres: GenresWrapper?
    let songsByGenre: SongsByGenreWrapper?
    let randomSongs: RandomSongsWrapper?
}

// MARK: - Nested response types
struct ArtistsWrapper: Decodable {
    let index: [ArtistIndex]?
    struct ArtistIndex: Decodable {
        let name: String?
        let artist: [Artist]?
    }
}

struct ArtistDetail: Decodable {
    let id: String
    let name: String
    let albumCount: Int?
    let coverArt: String?
    var starred: Date?
    let album: [Album]?

    var albumList: [Album] { album ?? [] }

    // Expose as Artist model
    var asArtist: Artist {
        Artist(id: id, name: name, albumCount: albumCount, coverArt: coverArt, starred: starred)
    }
}

struct AlbumDetail: Decodable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let songCount: Int?
    let duration: Int?
    let year: Int?
    let genre: String?
    var starred: Date?
    let song: [Song]?

    var asAlbum: Album {
        Album(id: id, name: name, artist: artist, artistId: artistId,
              coverArt: coverArt, songCount: songCount, duration: duration,
              year: year, genre: genre, starred: starred, songs: song)
    }
}

struct AlbumListWrapper: Decodable {
    let album: [Album]?
}

struct PlaylistsWrapper: Decodable {
    let playlist: [Playlist]?
}

struct Starred2: Decodable {
    let artist: [Artist]?
    let album: [Album]?
    let song: [Song]?
}

struct SearchResult3: Decodable {
    let artist: [Artist]?
    let album: [Album]?
    let song: [Song]?
}

struct LyricsListWrapper: Decodable {
    let structuredLyrics: [StructuredLyrics]?
}

struct GenresWrapper: Decodable {
    let genre: [Genre]?
}

struct SongsByGenreWrapper: Decodable {
    let song: [Song]?
}

struct RandomSongsWrapper: Decodable {
    let song: [Song]?
}

// Extend Artist for nested Decodable inside ArtistDetail
extension Artist {
    // Already Codable
}

// Album: add songs from AlbumDetail
extension Album {
    init(from detail: AlbumDetail) {
        self.init(id: detail.id, name: detail.name, artist: detail.artist,
                  artistId: detail.artistId, coverArt: detail.coverArt,
                  songCount: detail.songCount, duration: detail.duration,
                  year: detail.year, genre: detail.genre, starred: detail.starred,
                  songs: detail.song)
    }
}
