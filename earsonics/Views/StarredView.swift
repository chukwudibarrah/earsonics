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
                .padding(.top, 80)

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
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 20) {
                                        HStack(spacing: 16) {
                                            Button {
                                                appState.player.load(songs: starredSongs, startIndex: 0)
                                            } label: {
                                                Label("Play All", systemImage: "play.fill")
                                            }
                                            Button {
                                                var shuffled = starredSongs
                                                shuffled.shuffle()
                                                appState.player.load(songs: shuffled, startIndex: 0)
                                            } label: {
                                                Label("Shuffle Play", systemImage: "shuffle")
                                            }
                                        }
                                        .padding(.horizontal, 60)
                                        .padding(.top, 20)

                                        LazyVStack(spacing: 2) {
                                            ForEach(Array(starredSongs.enumerated()), id: \.element.id) { idx, song in
                                                Button {
                                                    appState.player.load(songs: starredSongs, startIndex: idx)
                                                } label: {
                                                    SongRow(song: song, index: idx, playlists: playlists, showTrackNumber: false)
                                                }
                                                .buttonStyle(.card)
                                            }
                                        }
                                        .padding(.horizontal, 60)
                                        .padding(.bottom, 100)
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
                                            NavigationLink {
                                                AlbumDetailView(album: album)
                                            } label: {
                                                AlbumCard(album: album)
                                            }
                                            .buttonStyle(.card)
                                        }
                                    }
                                    .padding(60)
                                }
                            }
                        case .artists:
                            if starredArtists.isEmpty {
                                EmptyStarredView(type: "Artists")
                            } else {
                                ScrollView {
                                    LazyVStack(spacing: 4) {
                                        ForEach(starredArtists) { artist in
                                            NavigationLink {
                                                ArtistDetailView(artist: artist)
                                            } label: {
                                                ArtistRow(artist: artist)
                                            }
                                            .buttonStyle(.card)
                                        }
                                    }
                                    .padding(.horizontal, 60)
                                    .padding(.vertical, 20)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .task { await loadStarred() }
        }
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
            Text("No starred \(type)").font(.title)
            Text("Tap the heart icon to save your favourites.").foregroundColor(.secondary)
        }
    }
}
