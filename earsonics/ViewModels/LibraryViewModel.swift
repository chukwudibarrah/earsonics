// ViewModels/LibraryViewModel.swift
import SwiftUI
import Observation
import EarsonicsCore

@MainActor
@Observable
final class LibraryViewModel {
    var recentAlbums: [Album] = []
    var newestAlbums: [Album] = []
    var randomAlbums: [Album] = []
    var keepSpinningSongs: [Song] = []
    var artists: [Artist] = []
    /// Shared with every other screen (see `LibraryStore`).
    var playlists: [Playlist] { LibraryStore.shared.playlists }
    var isLoading: Bool = false
    var error: String? = nil

    /// Loads the Home screen: the album shelves, plus (in the background) the
    /// playlists used by card context menus and the "Keep spinning" shelf.
    ///
    /// Deliberately does NOT fetch artists or genres — Home shows neither, and
    /// `getArtists` can be large enough on a big library to stall the whole
    /// screen for a minute or more. The spinner clears as soon as the first
    /// shelves arrive; the rest fills in progressively.
    func loadHome() async {
        isLoading = true
        error = nil
        async let newest = SubsonicClient.shared.getAlbumList(type: "newest", size: 20)
        async let recent = SubsonicClient.shared.getAlbumList(type: "recent", size: 20)
        async let random = SubsonicClient.shared.getAlbumList(type: "random", size: 20)
        async let playlistsLoaded: Void = LibraryStore.shared.loadPlaylists()

        // Show the screen as soon as the first two shelves are ready.
        //
        // A cancelled load must leave the screen alone: SwiftUI can start
        // this task twice at launch and cancel the first, whose requests then
        // all fail with CancellationError. Without the checks below, that run
        // emptied the shelves and set `error`, flashing "Couldn't load your
        // library" on every launch until the second run's results arrived.
        var failures: [Error] = []
        do {
            newestAlbums = try await newest
        } catch {
            if Task.isCancelled { return }
            newestAlbums = []
            failures.append(error)
        }
        do {
            recentAlbums = try await recent
        } catch {
            if Task.isCancelled { return }
            recentAlbums = []
            failures.append(error)
        }
        isLoading = false

        do {
            randomAlbums = try await random
        } catch {
            if Task.isCancelled { return }
            randomAlbums = []
            failures.append(error)
        }
        await playlistsLoaded

        if newestAlbums.isEmpty && recentAlbums.isEmpty && randomAlbums.isEmpty,
           let failure = failures.first {
            error = failure.localizedDescription
        }
        await loadKeepSpinning()
    }

    /// Loads the artist list for the Artists tab (only what that screen shows).
    func loadArtists() async {
        isLoading = true
        error = nil
        do {
            artists = try await SubsonicClient.shared.getArtists()
        } catch {
            artists = []
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Builds the "Keep spinning" shelf: a couple of tracks from each of the
    /// most recently played albums, in recency order. The Subsonic API has no
    /// recently-played-songs endpoint, so this derives one from the album list.
    private func loadKeepSpinning() async {
        let sourceAlbums = Array(recentAlbums.prefix(8))
        guard !sourceAlbums.isEmpty else {
            keepSpinningSongs = []
            return
        }
        var songsByAlbum: [String: [Song]] = [:]
        let client = SubsonicClient.shared
        await withTaskGroup(of: (String, [Song]).self) { group in
            for album in sourceAlbums {
                group.addTask {
                    let detailed = try? await client.getAlbum(id: album.id)
                    return (album.id, Array((detailed?.songs ?? []).prefix(2)))
                }
            }
            for await (id, songs) in group {
                songsByAlbum[id] = songs
            }
        }
        // Cancelled requests come back empty; keep whatever is showing.
        guard !Task.isCancelled else { return }
        keepSpinningSongs = sourceAlbums.flatMap { songsByAlbum[$0.id] ?? [] }
    }

    func loadAlbum(id: String) async -> Album? {
        do {
            return try await SubsonicClient.shared.getAlbum(id: id)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func loadArtistAlbums(artistId: String) async -> [Album] {
        do {
            return try await SubsonicClient.shared.getArtistAlbums(artistId: artistId)
        } catch {
            self.error = error.localizedDescription
            return []
        }
    }
}
