// Views/StarredView.swift
import SwiftUI

struct StarredView: View {
    @EnvironmentObject var appState: AppState
    @State private var starredSongs: [Song] = []
    @State private var starredAlbums: [Album] = []
    @State private var starredArtists: [Artist] = []
    @State private var isLoading = true
    @State private var selectedTab: StarredTab = .songs
    @State private var selectedAlbum: Album? = nil
    @State private var selectedArtist: Artist? = nil

    enum StarredTab: String, CaseIterable {
        case songs = "Songs"
        case albums = "Albums"
        case artists = "Artists"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(StarredTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 60)
                .padding(.top, 20)

                Group {
                    if isLoading {
                        ProgressView("Loading Favourites...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        switch selectedTab {
                        case .songs:
                            if starredSongs.isEmpty {
                                EmptyStarredView(type: "Songs")
                            } else {
                                List {
                                    ForEach(Array(starredSongs.enumerated()), id: \.element.id) { idx, song in
                                        SongRow(song: song, index: idx) {
                                            appState.player.load(songs: starredSongs, startIndex: idx)
                                        }
                                    }
                                }
                            }
                        case .albums:
                            if starredAlbums.isEmpty {
                                EmptyStarredView(type: "Albums")
                            } else {
                                ScrollView {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 24)], spacing: 32) {
                                        ForEach(starredAlbums) { album in
                                            AlbumCard(album: album)
                                                .onTapGesture { selectedAlbum = album }
                                        }
                                    }
                                    .padding(60)
                                }
                            }
                        case .artists:
                            if starredArtists.isEmpty {
                                EmptyStarredView(type: "Artists")
                            } else {
                                List(starredArtists) { artist in
                                    ArtistRow(artist: artist)
                                        .onTapGesture { selectedArtist = artist }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Favourites")
            .task { await loadStarred() }
            .navigationDestination(item: $selectedAlbum) { AlbumDetailView(album: $0) }
            .navigationDestination(item: $selectedArtist) { ArtistDetailView(artist: $0) }
        }
    }

    private func loadStarred() async {
        isLoading = true
        if let (artists, albums, songs) = try? await SubsonicClient.shared.getStarred() {
            starredArtists = artists
            starredAlbums  = albums
            starredSongs   = songs
        }
        isLoading = false
    }
}

struct EmptyStarredView: View {
    let type: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart").font(.system(size: 60)).foregroundColor(.secondary)
            Text("No Starred \(type)").font(.title)
            Text("Tap the heart icon to save your favourites.").foregroundColor(.secondary)
        }
    }
}
