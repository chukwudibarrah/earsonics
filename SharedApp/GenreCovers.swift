// SharedApp/GenreCovers.swift
import SwiftUI
import EarsonicsCore

/// The cover shown for each genre: the first album with artwork in the
/// genre's (alphabetical) album list, so a genre always shows the same one.
/// Looked up once per genre, when its tile first comes on screen.
@MainActor @Observable
final class GenreCovers {
    private(set) var coverArt: [String: String] = [:]
    @ObservationIgnored private var requested: Set<String> = []

    func load(_ genre: String) async {
        guard requested.insert(genre).inserted else { return }
        let albums = (try? await SubsonicClient.shared.getAlbumsByGenre(genre: genre, size: 10)) ?? []
        if let cover = albums.first(where: { $0.coverArt != nil })?.coverArt {
            coverArt[genre] = cover
        }
    }
}

extension Genre {
    /// "120 songs · 10 albums".
    var countsText: String {
        let songs = songCount ?? 0, albums = albumCount ?? 0
        return "\(songs) \(songs == 1 ? "song" : "songs") · \(albums) \(albums == 1 ? "album" : "albums")"
    }
}
