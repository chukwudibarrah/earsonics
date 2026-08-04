// ViewModels/LibraryViewModel.swift
import SwiftUI
import Combine

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var recentAlbums: [Album] = []
    @Published var newestAlbums: [Album] = []
    @Published var randomAlbums: [Album] = []
    @Published var keepSpinningSongs: [Song] = []
    @Published var artists: [Artist] = []
    @Published var playlists: [Playlist] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

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
        async let pls    = SubsonicClient.shared.getPlaylists()

        // Show the screen as soon as the first two shelves are ready.
        var failures: [Error] = []
        do {
            newestAlbums = try await newest
        } catch {
            newestAlbums = []
            failures.append(error)
        }
        do {
            recentAlbums = try await recent
        } catch {
            recentAlbums = []
            failures.append(error)
        }
        isLoading = false

        do {
            randomAlbums = try await random
        } catch {
            randomAlbums = []
            failures.append(error)
        }
        do {
            playlists = try await pls
        } catch {
            playlists = []
            failures.append(error)
        }

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
        artists = (try? await SubsonicClient.shared.getArtists()) ?? []
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
        await withTaskGroup(of: (String, [Song]).self) { group in
            for album in sourceAlbums {
                group.addTask {
                    let detailed = try? await SubsonicClient.shared.getAlbum(id: album.id)
                    return (album.id, Array((detailed?.songs ?? []).prefix(2)))
                }
            }
            for await (id, songs) in group {
                songsByAlbum[id] = songs
            }
        }
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
