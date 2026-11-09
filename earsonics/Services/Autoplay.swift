// Services/Autoplay.swift
import Foundation

/// Picks songs to keep playing after a queue runs out (see
/// `QueueContinuation`, chosen per kind of queue in Settings).
///
/// Every source can come back empty — similar songs and similar artists
/// depend on the server having external metadata (e.g. Last.fm), and the
/// Navidrome demo has no similar artists at all — so each choice falls back
/// through similar songs → same artist → random until something turns up.
struct Autoplay {
    /// What the next batch is based on: the song that's ending.
    struct Seed: Equatable {
        let songID: String
        let artistID: String?
        let artistName: String?
        let genre: String?

        init(_ song: Song) {
            songID = song.id
            artistID = song.artistId
            artistName = song.artist
            genre = song.genre
        }
    }

    /// Where songs come from. Injected so the rules can be tested offline.
    struct Source {
        var similarSongs: (_ songID: String) async -> [Song]
        var topSongs: (_ artistName: String) async -> [Song]
        var artistSongs: (_ artistID: String) async -> [Song]
        var similarArtists: (_ artistID: String) async -> [Artist]
        var randomSongs: (_ genre: String?) async -> [Song]
    }

    static let batchSize = 20
    /// Similar artists sampled per batch (each one costs a request).
    static let similarArtistsSampled = 4

    let source: Source

    /// The order sources are tried in: the user's choice first, then the
    /// fallbacks. `.stop` tries nothing.
    static func plan(for choice: QueueContinuation) -> [QueueContinuation] {
        guard choice != .stop else { return [] }
        var plan = [choice]
        for fallback in [QueueContinuation.similarSongs, .sameArtist, .random] where !plan.contains(fallback) {
            plan.append(fallback)
        }
        return plan
    }

    /// Up to `batchSize` songs not already played this session (and no
    /// repeats within the batch), shuffled.
    static func pick(_ candidates: [Song], excluding played: Set<String>, limit: Int = batchSize) -> [Song] {
        var seen = played
        var picked: [Song] = []
        for song in candidates.shuffled() where !seen.contains(song.id) {
            seen.insert(song.id)
            picked.append(song)
            if picked.count == limit { break }
        }
        return picked
    }

    /// The next batch, trying each source in `plan(for:)` until one gives
    /// something new. Empty if nothing does (playback then stops).
    func nextBatch(for choice: QueueContinuation, seed: Seed, excluding played: Set<String>) async -> [Song] {
        for option in Self.plan(for: choice) {
            let batch = Self.pick(await candidates(from: option, seed: seed), excluding: played)
            if !batch.isEmpty { return batch }
        }
        return []
    }

    private func candidates(from option: QueueContinuation, seed: Seed) async -> [Song] {
        switch option {
        case .stop:
            return []
        case .similarSongs:
            return await source.similarSongs(seed.songID)
        case .sameArtist:
            var songs: [Song] = []
            if let name = seed.artistName { songs += await source.topSongs(name) }
            if let id = seed.artistID { songs += await source.artistSongs(id) }
            return songs
        case .similarArtists:
            guard let id = seed.artistID else { return [] }
            let artists = await source.similarArtists(id).shuffled().prefix(Self.similarArtistsSampled)
            var songs: [Song] = []
            for artist in artists { songs += await source.artistSongs(artist.id) }
            return songs
        case .sameGenre:
            guard let genre = seed.genre, !genre.isEmpty else { return [] }
            return await source.randomSongs(genre)
        case .random:
            return await source.randomSongs(nil)
        }
    }
}

extension Autoplay.Source {
    /// The real server. Failures count as "nothing found", so the next
    /// fallback gets a turn.
    @MainActor static func server(_ srv: Server) -> Self {
        let client = SubsonicClient.shared
        return Self(
            similarSongs: { (try? await client.getSimilarSongs(id: $0, server: srv)) ?? [] },
            topSongs: { (try? await client.getTopSongs(artist: $0, server: srv)) ?? [] },
            artistSongs: { artistID in
                // A few of the artist's albums, rather than every one.
                let albums = ((try? await client.getArtistAlbums(artistId: artistID, server: srv)) ?? []).shuffled().prefix(3)
                var songs: [Song] = []
                for album in albums {
                    songs += (try? await client.getAlbum(id: album.id, server: srv))?.songs ?? []
                }
                return songs
            },
            similarArtists: { (try? await client.getSimilarArtists(artistId: $0, server: srv)) ?? [] },
            randomSongs: { (try? await client.getRandomSongs(size: Autoplay.batchSize * 2, genre: $0, server: srv)) ?? [] }
        )
    }
}
