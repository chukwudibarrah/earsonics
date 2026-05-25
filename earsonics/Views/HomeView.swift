// Views/HomeView.swift
import SwiftUI

// CardlessButtonStyle is defined in Views/Shared/FocusStyle.swift

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = LibraryViewModel()
    @State private var navPath = NavigationPath()

    var body: some View {
        // Use path-based NavigationStack so we can push programmatically
        // from a plain Button — no NavigationLink card effect
        NavigationStack(path: $navPath) {
            Group {
                if !appState.isConnected && appState.serverStore.servers.isEmpty {
                    NoServerView()
                } else if vm.isLoading && vm.recentAlbums.isEmpty {
                    ProgressView("Loading library...")
                        .font(.headline)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 50) {
                            if !vm.recentAlbums.isEmpty {
                                AlbumShelf(title: "Recently played", albums: vm.recentAlbums, navPath: $navPath)
                            }
                            if !vm.newestAlbums.isEmpty {
                                AlbumShelf(title: "Newly added", albums: vm.newestAlbums, navPath: $navPath)
                            }
                            if !vm.randomAlbums.isEmpty {
                                AlbumShelf(title: "Discover", albums: vm.randomAlbums, navPath: $navPath)
                            }
                        }
                        // NO horizontal padding here — each shelf manages its own
//                        .padding(.vertical, 40)
                        .padding(.bottom, 120)
                        .padding(.top, layoutTopPadding)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            // Destination registered here — triggered by navPath.append(album)
            .navigationDestination(for: Album.self) { album in
                AlbumDetailView(album: album)
            }
            .task { await vm.loadHome() }
            .refreshable { await vm.loadHome() }
        }
    }
}

// MARK: - Album Shelf (horizontal scroll)
struct AlbumShelf: View {
    let title: String
    let albums: [Album]
    @Binding var navPath: NavigationPath
    @State private var playlists: [Playlist] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2).fontWeight(.medium)
//                .padding(.leading, 60)
                .foregroundColor(.primary.opacity(0.28))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 25) {
                    ForEach(albums) { album in
                        Button {
                            navPath.append(album)
                        } label: {
                            AlbumCard(album: album)
                        }
                        .buttonStyle(.card)
                        .contextMenu {
                            Button {
                                AudioPlayerService.shared.load(songs: album.songs ?? [], startIndex: 0)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            if !playlists.isEmpty {
                                Divider()
                                ForEach(playlists) { playlist in
                                    Button {
                                        Task {
                                            // Get the album detail to get all song IDs, if needed
                                            guard let detailed = try? await SubsonicClient.shared.getAlbum(id: album.id),
                                                  let songs = detailed.songs else { return }
                                            let songIds = songs.map { $0.id }
                                            try? await SubsonicClient.shared.updatePlaylist(
                                                id: playlist.id, songIdsToAdd: songIds)
                                        }
                                    } label: {
                                        Label("Add to \(playlist.name)", systemImage: "music.note.list")
                                    }
                                }
                            }
                        }
                    }
                }
//                .padding(.horizontal, 60)   // wide enough for card scale at edges
                .padding(.vertical, 60)
            }
        }
        .task {
            playlists = (try? await SubsonicClient.shared.getPlaylists()) ?? []
        }
    }
}

// MARK: - Album Card
struct AlbumCard: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoverArtView(id: album.coverArt, size: 260)
                .frame(width: 360, height: 360)
//                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 5) {
                Text(album.name)
                    .font(.subheadline).bold()
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let artist = album.artist {
                    Text(artist)
                        .font(.caption2)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .frame(width: 360)
    }
}

// MARK: - No Server View
struct NoServerView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            Text("No server configured")
                .font(.title).bold()
            Text("Go to settings to add your Navidrome/Subsonic server.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(60)
    }
}
