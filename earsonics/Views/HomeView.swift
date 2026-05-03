// Views/HomeView.swift
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = LibraryViewModel()

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
                        VStack(alignment: .leading, spacing: 56) {
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
                        .padding(.vertical, 50)
                        .padding(.bottom, 100) // space for mini player bar
                    }
                }
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .task { await vm.loadHome() }
            .refreshable { await vm.loadHome() }
        }
    }
}

// MARK: - Album Shelf (horizontal scroll)
struct AlbumShelf: View {
    let title: String
    let albums: [Album]
    @State private var selectedAlbum: Album? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title).bold()
                .padding(.leading, 8)
                .foregroundColor(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 32) {
                    ForEach(albums) { album in
                        NavigationLink {
                            AlbumDetailView(album: album)
                        } label: {
                            AlbumCard(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 16)
            }
        }
    }
}

// MARK: - Album Card
struct AlbumCard: View {
    let album: Album
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CoverArtView(id: album.coverArt, size: 400)
                .frame(width: 280, height: 280)
                .cornerRadius(12)
                .scaleEffect(focused ? 1.06 : 1.0)
                .shadow(color: .black.opacity(focused ? 0.6 : 0.2), radius: focused ? 24 : 8, y: focused ? 12 : 4)
                .animation(.easeInOut(duration: 0.18), value: focused)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.headline)
                    .bold()
                    .lineLimit(2)
                    .frame(width: 280, alignment: .leading)
                    .foregroundColor(focused ? .white : .primary)
                if let artist = album.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(width: 280, alignment: .leading)
                }
            }
        }
        .focusable()
        .focused($focused)
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
