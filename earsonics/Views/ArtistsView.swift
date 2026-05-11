// Views/ArtistsView.swift
import SwiftUI

struct ArtistsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = LibraryViewModel()
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
                    ProgressView("Loading artists...")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filtered) { artist in
                                NavigationLink {
                                    ArtistDetailView(artist: artist)
                                        .environmentObject(appState)
                                } label: {
                                    ArtistRow(artist: artist)
                                }
                                .buttonStyle(.card)
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.vertical, 16)
                        .padding(.bottom, 100)
                    }
                    .searchable(text: $searchText, prompt: "Search artists")
                }
            }
            .task { if vm.artists.isEmpty { await vm.loadHome() } }
        }
    }
}

struct ArtistRow: View {
    let artist: Artist

    var body: some View {
        HStack(spacing: 16) {
            CoverArtView(id: artist.coverArt, size: 100)
                .frame(width: 60, height: 60)
                .cornerRadius(8)
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.headline)
                if let count = artist.albumCount {
                    Text("\(count) albums")
                        .font(.caption)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.callout)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Artist Detail
struct ArtistDetailView: View {
    let artist: Artist
    @EnvironmentObject var appState: AppState
    @State private var albums: [Album] = []
    @State private var isLoading = true
    @State private var isStarred: Bool
    @State private var navPath = NavigationPath()

    init(artist: Artist) {
        self.artist = artist
        _isStarred = State(initialValue: artist.starred != nil)
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack(alignment: .top) {
                // Background artist name
                Text(artist.name)
                    .font(.system(size: 240, weight: .black))
                    .foregroundColor(.white.opacity(0.05))
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
                    .padding(.top, 40)
                    .ignoresSafeArea()

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
                                    Text("\(count) albums").foregroundColor(.secondary)
                                }
                                HStack(spacing: 16) {
                                    Button {
                                        let allSongs = albums.flatMap { $0.songs ?? [] }
                                        if !allSongs.isEmpty {
                                            appState.player.load(songs: allSongs, startIndex: 0)
                                        }
                                    } label: {
                                        Label("Play all", systemImage: "play.fill")
                                    }

                                    StarButton(isStarred: isStarred, artistId: artist.id) { newVal in
                                        isStarred = newVal
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 60)

                        // Albums grid — Button + CardlessButtonStyle, no NavigationLink card
                        if isLoading {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 350), spacing: 24)], spacing: 32) {
                                ForEach(albums) { album in
                                    Button {
                                        navPath.append(album)
                                    } label: {
                                        AlbumCard(album: album)
                                    }
                                    .buttonStyle(.card)
                                }
                            }
                            .padding(.horizontal, 60)
                        }
                    }
                    .padding(.vertical, 60)
                    .padding(.bottom, 100)
                }
                .navigationDestination(for: Album.self) { album in
                    AlbumDetailView(album: album)
                }
                .task {
                    isLoading = true
                    albums = (try? await SubsonicClient.shared.getArtistAlbums(artistId: artist.id)) ?? []
                    isLoading = false
                }
            }
        }
    }
}
