// Views/StarredView.swift
import SwiftUI

struct StarredView: View {
    @EnvironmentObject var appState: AppState
    @State private var starredSongs: [Song] = []
    @State private var starredAlbums: [Album] = []
    @State private var starredArtists: [Artist] = []
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var selectedTab: StarredTab = .songs
    @State private var navPath = NavigationPath()
    @ObservedObject private var player = AudioPlayerService.shared

    enum StarredTab: String, CaseIterable {
        case songs = "Songs"
        case albums = "Albums"
        case artists = "Artists"
    }

    // Pages open by value through `navPath`, resolved by the
    // navigationDestination modifiers below. Opening them with
    // `NavigationLink { destination }` instead left the album/artist page on
    // screen after switching tabs from the sidebar (the new tab only showed
    // after pressing Menu) — see the tab-switch UI tests.
    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(StarredTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppLayout.horizontalPadding)
                .padding(.top, 20)

                Group {
                    if isLoading {
                        ProgressView("Loading favourites...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        switch selectedTab {
                        case .songs:
                            if starredSongs.isEmpty {
                                EmptyStarredView(type: "Songs")
                            } else {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 20) {
                                        HStack(spacing: 16) {
                                            Button {
                                                appState.player.isShuffled = false
                                                appState.player.load(songs: starredSongs, startIndex: 0)
                                            } label: {
                                                Label("Play all", systemImage: "play.fill")
                                            }
                                            Button {
                                                appState.player.isShuffled = false
                                                appState.player.load(songs: starredSongs, startIndex: 0)
                                                appState.player.toggleShuffle()
                                            } label: {
                                                Label("Shuffle play", systemImage: "shuffle")
                                            }
                                        }
                                        .buttonStyle(AccentPillButtonStyle())
                                        .padding(.horizontal, AppLayout.horizontalPadding)

                                        LazyVStack(spacing: 2) {
                                            ForEach(Array(starredSongs.enumerated()), id: \.element.id) { idx, song in
                                                SongRow(song: song, index: idx, contextSongs: starredSongs, playlists: playlists, showTrackNumber: false)
                                            }
                                        }
                                        .padding(.horizontal, AppLayout.horizontalPadding)
                                        .padding(.bottom, 100)
                                    }
                                    .padding(.top, 20)
                                }
                            }
                        case .albums:
                            if starredAlbums.isEmpty {
                                EmptyStarredView(type: "Albums")
                            } else {
                                ScrollView {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 80)], spacing: 80) {
                                        ForEach(starredAlbums) { album in
                                            NavigationLink(value: album) {
                                                AlbumCard(album: album)
                                            }
                                            .buttonStyle(CardlessButtonStyle())
                                        }
                                    }
                                    .padding(.top, 20)
                                    .padding(.horizontal, AppLayout.horizontalPadding)
                                    .padding(.bottom, 120)
                                }
                            }
                        case .artists:
                            if starredArtists.isEmpty {
                                EmptyStarredView(type: "Artists")
                            } else {
                                ScrollView {
                                    LazyVStack(spacing: 4) {
                                        ForEach(starredArtists) { artist in
                                            NavigationLink(value: artist) {
                                                ArtistRow(artist: artist)
                                            }
                                            .buttonStyle(CardlessButtonStyle())
                                        }
                                    }
                                    .padding(.top, 20)
                                    .padding(.horizontal, AppLayout.horizontalPadding)
                                    .padding(.bottom, 120)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationDestination(for: Album.self) { album in
                AlbumDetailView(album: album)
            }
            .navigationDestination(for: Artist.self) { artist in
                ArtistDetailView(artist: artist)
            }
            .task { await loadStarred() }
        }
        .padding(.top, AppLayout.contentTopPadding)
    }

    private func loadStarred() async {
        isLoading = true
        async let starredLoad = SubsonicClient.shared.getStarred()
        async let playlistLoad = SubsonicClient.shared.getPlaylists()
        if let (artists, albums, songs) = try? await starredLoad {
            starredArtists = artists
            starredAlbums  = albums
            starredSongs   = songs
        }
        playlists = (try? await playlistLoad) ?? []
        isLoading = false
    }
}

struct EmptyStarredView: View {
    let type: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart").font(.system(size: 60)).foregroundColor(.secondary)
            Text("No starred \(type.lowercased())").font(.title)
            Text("Select the heart on any song, album or artist to save it here.").foregroundColor(.secondary)
        }
    }
}
