// ViewModels/LibraryViewModel.swift
import SwiftUI
import Combine

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var recentAlbums: [Album] = []
    @Published var newestAlbums: [Album] = []
    @Published var randomAlbums: [Album] = []
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
