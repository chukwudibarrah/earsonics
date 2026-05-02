// Views/ArtistsView.swift
import SwiftUI

struct ArtistsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = LibraryViewModel()
    @State private var selectedArtist: Artist? = nil
    @State private var searchText: String = ""

    var filtered: [Artist] {
        searchText.isEmpty ? vm.artists : vm.artists.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.artists.isEmpty {
                    ProgressView("Loading Artists...")
                } else {
                    List(filtered) { artist in
                        ArtistRow(artist: artist)
                            .onTapGesture { selectedArtist = artist }
                    }
                    .searchable(text: $searchText, prompt: "Search artists")
                }
            }
            .navigationTitle("Artists")
            .task { if vm.artists.isEmpty { await vm.loadHome() } }
            .navigationDestination(item: $selectedArtist) { artist in
                ArtistDetailView(artist: artist)
            }
        }
    }
}

struct ArtistRow: View {
    let artist: Artist
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 16) {
            CoverArtView(id: artist.coverArt, size: 100)
                .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name).font(.headline)
                if let count = artist.albumCount {
                    Text("\(count) albums").font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(focused ? Color.white.opacity(0.1) : Color.clear)
        )
        .focusable()
        .focused($focused)
    }
}

// MARK: - Artist Detail
struct ArtistDetailView: View {
    let artist: Artist
    @EnvironmentObject var appState: AppState
    @State private var albums: [Album] = []
    @State private var isLoading = true
    @State private var isStarred: Bool
    @State private var selectedAlbum: Album? = nil

    init(artist: Artist) {
        self.artist = artist
        _isStarred = State(initialValue: artist.starred != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // Header
                HStack(spacing: 40) {
                    CoverArtView(id: artist.coverArt, size: 400)
                        .frame(width: 200, height: 200)
                        .cornerRadius(100)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(artist.name).font(.largeTitle).bold()
                        if let count = artist.albumCount {
                            Text("\(count) Albums").foregroundColor(.secondary)
                        }
                        HStack(spacing: 16) {
                            Button {
                                let allSongs = albums.flatMap { $0.songs ?? [] }
                                if !allSongs.isEmpty {
                                    appState.player.load(songs: allSongs, startIndex: 0)
                                }
                            } label: {
                                Label("Play All", systemImage: "play.fill")
                                    .padding(.horizontal, 20).padding(.vertical, 10)
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)

                            StarButton(isStarred: isStarred, artistId: artist.id) { newVal in
                                isStarred = newVal
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 60)

                // Albums grid
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 24)], spacing: 32) {
                        ForEach(albums) { album in
                            AlbumCard(album: album)
                                .onTapGesture { selectedAlbum = album }
                        }
                    }
                    .padding(.horizontal, 60)
                }
            }
            .padding(.vertical, 40)
        }
        .navigationTitle(artist.name)
        .task {
            isLoading = true
            albums = (try? await SubsonicClient.shared.getArtistAlbums(artistId: artist.id)) ?? []
            isLoading = false
        }
        .navigationDestination(item: $selectedAlbum) { album in
            AlbumDetailView(album: album)
        }
    }
}
