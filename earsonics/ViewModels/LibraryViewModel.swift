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
    @Published var genres: [Genre] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    func loadHome() async {
        isLoading = true
        error = nil
        do {
            async let recent  = SubsonicClient.shared.getAlbumList(type: "recent",  size: 20)
            async let newest  = SubsonicClient.shared.getAlbumList(type: "newest",  size: 20)
            async let random  = SubsonicClient.shared.getAlbumList(type: "random",  size: 20)
            async let arts    = SubsonicClient.shared.getArtists()
            async let genres  = SubsonicClient.shared.getGenres()
            (recentAlbums, newestAlbums, randomAlbums, artists, self.genres) =
                try await (recent, newest, random, arts, genres)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        await loadKeepSpinning()
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
