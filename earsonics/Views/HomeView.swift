// Views/HomeView.swift
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = LibraryViewModel()
    @State private var selectedAlbum: Album? = nil

    var body: some View {
        NavigationStack {
            Group {
                if !appState.isConnected && appState.serverStore.servers.isEmpty {
                    NoServerView()
                } else if vm.isLoading && vm.recentAlbums.isEmpty {
                    ProgressView("Loading Library...")
                        .font(.headline)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 40) {
                            if !vm.recentAlbums.isEmpty {
                                AlbumShelf(title: "Recently Played", albums: vm.recentAlbums)
                            }
                            if !vm.newestAlbums.isEmpty {
                                AlbumShelf(title: "Newly Added", albums: vm.newestAlbums)
                            }
                            if !vm.randomAlbums.isEmpty {
                                AlbumShelf(title: "Discover", albums: vm.randomAlbums)
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.vertical, 40)
                    }
                }
            }
            .navigationTitle("earsonics")
            .task { await vm.loadHome() }
            .refreshable { await vm.loadHome() }
            .navigationDestination(item: $selectedAlbum) { album in
                AlbumDetailView(album: album)
            }
        }
    }
}

// MARK: - Album Shelf (horizontal scroll)
struct AlbumShelf: View {
    let title: String
    let albums: [Album]
    @State private var selectedAlbum: Album? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2).bold()
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(albums) { album in
                        AlbumCard(album: album)
                            .onTapGesture { selectedAlbum = album }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .navigationDestination(item: $selectedAlbum) { album in
            AlbumDetailView(album: album)
        }
    }
}

// MARK: - Album Card
struct AlbumCard: View {
    let album: Album
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverArtView(id: album.coverArt, size: 300)
                .frame(width: 220, height: 220)
                .scaleEffect(focused ? 1.07 : 1.0)
                .shadow(radius: focused ? 16 : 4)
                .animation(.easeInOut(duration: 0.15), value: focused)

            Text(album.name)
                .font(.callout).bold()
                .lineLimit(1)
                .frame(width: 220, alignment: .leading)
            if let artist = album.artist {
                Text(artist)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: 220, alignment: .leading)
            }
        }
        .focusable()
        .focused($focused)
        .buttonStyle(.plain)
    }
}

// MARK: - No Server View
struct NoServerView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            Text("No Server Configured")
                .font(.title).bold()
            Text("Go to Settings to add your Navidrome/Subsonic server.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(60)
    }
}
