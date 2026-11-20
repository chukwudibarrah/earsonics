// earsonics-iOS/Library/LibrarySections.swift
import SwiftUI
import EarsonicsCore

/// Album orders the server can list, in the server's own names.
enum AlbumSort: String, CaseIterable, Identifiable {
    case name = "alphabeticalByName"
    case artist = "alphabeticalByArtist"
    case recentlyAdded = "newest"
    case recentlyPlayed = "recent"
    case mostPlayed = "frequent"
    case random

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name:           "Name"
        case .artist:         "Artist"
        case .recentlyAdded:  "Recently Added"
        case .recentlyPlayed: "Recently Played"
        case .mostPlayed:     "Most Played"
        case .random:         "Random"
        }
    }
}

/// A grid of albums in one order, loaded a page at a time as it scrolls.
struct AlbumGridView: View {
    let title: String
    let initialSort: AlbumSort
    /// For pages that are one order by definition (e.g. Recently Added).
    var fixedSort = false

    @Environment(AppState.self) private var appState
    @State private var sort: AlbumSort?
    @State private var albums: [Album] = []
    @State private var hasMore = true
    @State private var isLoading = false

    private static let pageSize = 60
    private var currentSort: AlbumSort { sort ?? initialSort }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(albums) { album in
                    AlbumCard(album: album)
                        .onAppear { if album.id == albums.last?.id { Task { await loadMore() } } }
                }
            }
            .padding()
            if isLoading { ProgressView().padding() }
        }
        .overlay {
            if !isLoading && albums.isEmpty {
                ContentUnavailableView("No albums", systemImage: "square.stack")
            }
        }
        .appBackground()
        .navigationTitle(title)
        .toolbar {
            if !fixedSort {
                Menu {
                    Picker("Sort by", selection: Binding(get: { currentSort }, set: { sort = $0 })) {
                        ForEach(AlbumSort.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .task(id: "\(appState.activeServerID?.uuidString ?? "")-\(currentSort.rawValue)") { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        albums = []
        hasMore = true
        await loadMore()
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await SubsonicClient.shared.getAlbumList(type: currentSort.rawValue, size: Self.pageSize,
                                                                    offset: albums.count)
            // Random returns a fresh pick each call; one page is enough.
            hasMore = page.count == Self.pageSize && currentSort != .random
            let known = Set(albums.map(\.id))
            albums += page.filter { !known.contains($0.id) }
        } catch {
            hasMore = false
            Messages.shared.showFailure("load albums", error)
        }
    }
}

/// Every song, loaded in pages (an empty search lists the whole library).
struct AllSongsView: View {
    @Environment(AppState.self) private var appState
    @State private var songs: [Song] = []
    @State private var hasMore = true
    @State private var isLoading = false
    private static let pageSize = 500

    var body: some View {
        List {
            Section {
                PlayShuffleButtons(play: { Playback.play(songs, shuffle: false, context: .mix) },
                                   shuffle: { Playback.play(songs, shuffle: true, context: .mix) })
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
                    .disabled(songs.isEmpty)
            }
            Section {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song, index: index, songs: songs)
                        .onAppear { if index == songs.count - 1 { Task { await loadMore() } } }
                }
                .listRowBackground(Palette.card)
                if isLoading { ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear) }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Songs")
        .task(id: appState.activeServerID) { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        songs = []
        hasMore = true
        await loadMore()
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await SubsonicClient.shared.search(query: "", artistCount: 0, albumCount: 0,
                                                              songCount: Self.pageSize, songOffset: songs.count).songs
            hasMore = page.count == Self.pageSize
            songs += page
        } catch {
            hasMore = false
            Messages.shared.showFailure("load songs", error)
        }
    }
}

/// Artists A–Z, with a filter.
struct ArtistListView: View {
    @Environment(AppState.self) private var appState
    @State private var artists: [Artist] = []
    @State private var filter = ""
    @State private var didLoad = false

    private var shown: [Artist] {
        filter.isEmpty ? artists : artists.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        List(shown) { artist in
            NavigationLink(value: Route.artist(artist)) {
                HStack(spacing: 14) {
                    Artwork(id: artist.coverArt, pixels: 120, cornerRadius: 24, placeholderSymbol: "music.mic")
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(artist.name).font(.body.weight(.medium))
                        if let count = artist.albumCount {
                            Text(count.counted("album")).font(.subheadline).foregroundStyle(Palette.secondaryText)
                        }
                    }
                }
            }
            .listRowBackground(Palette.card)
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .overlay {
            if didLoad && shown.isEmpty {
                ContentUnavailableView.search(text: filter)
            } else if !didLoad {
                ProgressView()
            }
        }
        .searchable(text: $filter, prompt: "Filter artists")
        .navigationTitle("Artists")
        .task(id: appState.activeServerID) {
            do {
                artists = try await SubsonicClient.shared.getArtists()
            } catch {
                Messages.shared.showFailure("load artists", error)
            }
            didLoad = true
        }
    }
}

/// Every genre, largest first, each with one of its covers.
struct GenreGridView: View {
    @Environment(AppState.self) private var appState
    @State private var genres: [Genre] = []
    @State private var covers = GenreCovers()

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                ForEach(genres) { genre in
                    GenreCard(genre: genre, coverArt: covers.coverArt[genre.value])
                        .task { await covers.load(genre.value) }
                }
            }
            .padding()
        }
        .appBackground()
        .navigationTitle("Genres")
        .task(id: appState.activeServerID) {
            do {
                genres = try await SubsonicClient.shared.getGenres()
                    .filter { ($0.songCount ?? 0) > 0 }
                    .sorted { ($0.songCount ?? 0, $1.value) > ($1.songCount ?? 0, $0.value) }
            } catch {
                Messages.shared.showFailure("load genres", error)
            }
        }
    }
}

/// The server's playlists, with a button to make a new one.
struct PlaylistGridView: View {
    @Environment(AppState.self) private var appState
    @State private var isNaming = false
    @State private var newName = ""

    var body: some View {
        let playlists = LibraryStore.shared.playlists
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(playlists) { PlaylistCard(playlist: $0) }
            }
            .padding()
        }
        .overlay {
            if playlists.isEmpty {
                ContentUnavailableView("No playlists", systemImage: "music.note.list",
                                       description: Text("Make one with the + button."))
            }
        }
        .appBackground()
        .navigationTitle("Playlists")
        .toolbar {
            Button("New Playlist", systemImage: "plus") {
                newName = ""
                isNaming = true
            }
        }
        .alert("New Playlist", isPresented: $isNaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task {
                    _ = await PlaylistAdder.shared.create(name: name, songIDs: [])
                    await LibraryStore.shared.loadPlaylists(force: true)
                }
            }
        }
        .task(id: appState.activeServerID) { await LibraryStore.shared.loadPlaylists() }
        .refreshable { await LibraryStore.shared.loadPlaylists(force: true) }
    }
}

/// Starred songs, albums and artists.
struct FavouritesView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case songs = "Songs", albums = "Albums", artists = "Artists"
        var id: String { rawValue }
    }

    @Environment(AppState.self) private var appState
    @State private var kind = Kind.songs
    @State private var songs: [Song] = []
    @State private var albums: [Album] = []
    @State private var artists: [Artist] = []
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Show", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch kind {
                case .songs:
                    if !songs.isEmpty {
                        PlayShuffleButtons(play: { Playback.play(songs, shuffle: false, context: .mix) },
                                           shuffle: { Playback.play(songs, shuffle: true, context: .mix) })
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            if index > 0 { Divider().padding(.leading, 62) }
                            SongRow(song: song, index: index, songs: songs)
                        }
                    }
                    .card(cornerRadius: 22, padding: 12)
                case .albums:
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                        ForEach(albums) { AlbumCard(album: $0) }
                    }
                case .artists:
                    LazyVStack(spacing: 0) {
                        ForEach(artists) { artist in
                            NavigationLink(value: Route.artist(artist)) {
                                HStack(spacing: 14) {
                                    Artwork(id: artist.coverArt, pixels: 120, cornerRadius: 24, placeholderSymbol: "music.mic")
                                        .frame(width: 48, height: 48)
                                    Text(artist.name).font(.body.weight(.medium))
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Palette.secondaryText)
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .card(cornerRadius: 22, padding: 12)
                }
            }
            .padding()
        }
        .overlay {
            if didLoad && songs.isEmpty && albums.isEmpty && artists.isEmpty {
                ContentUnavailableView("No favourites yet", systemImage: "heart",
                                       description: Text("Star songs, albums and artists to find them here."))
            }
        }
        .appBackground()
        .navigationTitle("Favourites")
        .task(id: appState.activeServerID) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            let starred = try await SubsonicClient.shared.getStarred()
            songs = starred.songs
            albums = starred.albums
            artists = starred.artists
        } catch {
            Messages.shared.showFailure("load Favourites", error)
        }
        didLoad = true
    }
}
