// earsonics-iOS/Navigation/Route.swift
import SwiftUI
import EarsonicsCore

/// Everything a page can open. Pages open by value (`NavigationLink(value:)`
/// resolved by `routeDestinations()`), never with a destination closure:
/// that keeps every tab's navigation in its own path.
enum Route: Hashable {
    case album(Album)
    case artist(Artist)
    /// An artist known only by id and name, e.g. from a song or album.
    case artistID(id: String, name: String)
    case albumID(id: String, name: String)
    case playlist(Playlist)
    case genre(Genre)
    case section(LibrarySection)
}

/// The parts of the library: rows in the Library tab on iPhone, and sidebar
/// items on iPad.
enum LibrarySection: String, CaseIterable, Identifiable, Hashable {
    case favourites, recentlyPlayed, recentlyAdded
    case songs, albums, artists, genres
    case playlists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favourites:     "Favourites"
        case .recentlyPlayed: "Recently Played"
        case .recentlyAdded:  "Recently Added"
        case .songs:          "Songs"
        case .albums:         "Albums"
        case .artists:        "Artists"
        case .genres:         "Genres"
        case .playlists:      "Playlists"
        }
    }

    var subtitle: String {
        switch self {
        case .favourites:     "Songs, albums and artists you’ve starred"
        case .recentlyPlayed: "Albums from your latest listening"
        case .recentlyAdded:  "Fresh arrivals on your server"
        case .songs:          "Every track in your library"
        case .albums:         "Full records across your collection"
        case .artists:        "Artist pages and discographies"
        case .genres:         "Browse by style and mood"
        case .playlists:      "Saved sets from your server"
        }
    }

    var systemImage: String {
        switch self {
        case .favourites:     "heart.fill"
        case .recentlyPlayed: "clock.arrow.circlepath"
        case .recentlyAdded:  "sparkles"
        case .songs:          "music.note"
        case .albums:         "square.stack.fill"
        case .artists:        "music.mic"
        case .genres:         "square.grid.2x2.fill"
        case .playlists:      "music.note.list"
        }
    }

    /// How the Library tab groups the sections.
    static let groups: [(title: String, subtitle: String, sections: [LibrarySection])] = [
        ("Favourites & History", "What you reach for most", [.favourites, .recentlyPlayed, .recentlyAdded]),
        ("Browse", "Move through the whole library", [.songs, .albums, .artists, .genres]),
        ("Collections", "Saved sets and groupings", [.playlists]),
    ]
}

extension View {
    /// The pages every tab's navigation stack can open.
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .album(let album):          AlbumDetailView(albumID: album.id, preview: album)
            case .albumID(let id, _):        AlbumDetailView(albumID: id, preview: nil)
            case .artist(let artist):        ArtistDetailView(artistID: artist.id, preview: artist)
            case .artistID(let id, _):       ArtistDetailView(artistID: id, preview: nil)
            case .playlist(let playlist):    PlaylistDetailView(playlist: playlist)
            case .genre(let genre):          GenreDetailView(genre: genre)
            case .section(let section):      LibrarySectionView(section: section)
            }
        }
    }
}

/// A section's own page.
struct LibrarySectionView: View {
    let section: LibrarySection

    var body: some View {
        switch section {
        case .favourites:     FavouritesView()
        case .recentlyPlayed: AlbumGridView(title: section.title, initialSort: .recentlyPlayed, fixedSort: true)
        case .recentlyAdded:  AlbumGridView(title: section.title, initialSort: .recentlyAdded, fixedSort: true)
        case .songs:          AllSongsView()
        case .albums:         AlbumGridView(title: section.title, initialSort: .name)
        case .artists:        ArtistListView()
        case .genres:         GenreGridView()
        case .playlists:      PlaylistGridView()
        }
    }
}
