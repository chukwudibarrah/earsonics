// Views/HomeView.swift
import SwiftUI

// CardlessButtonStyle is defined in Views/Shared/FocusStyle.swift

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = LibraryViewModel()
    @State private var navPath = NavigationPath()
    @ObservedObject private var player = AudioPlayerService.shared

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
                        VStack(alignment: .leading, spacing: AppLayout.verticalSpacing) {
                            if !vm.newestAlbums.isEmpty {
                                AlbumShelf(title: "Just arrived", albums: vm.newestAlbums, navPath: $navPath)
                            }
                            if !vm.keepSpinningSongs.isEmpty {
                                TrackShelf(title: "Keep spinning", songs: vm.keepSpinningSongs)
                            }
                            if !vm.recentAlbums.isEmpty {
                                AlbumShelf(title: "Recently played", albums: vm.recentAlbums, navPath: $navPath)
                            }
                            if !vm.randomAlbums.isEmpty {
                                AlbumShelf(title: "Discover", albums: vm.randomAlbums, navPath: $navPath)
                            }
                        }
                        .padding(.top, AppLayout.contentTopPadding)
                        .padding(.bottom, 50)
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
                .padding(.leading, AppLayout.horizontalPadding)
                .foregroundColor(.primary.opacity(0.28))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 40) {
                    ForEach(albums) { album in
                        Button {
                            navPath.append(album)
                        } label: {
                            AlbumCard(album: album)
                        }
                        .buttonStyle(CardlessButtonStyle())
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
                .padding(.horizontal, AppLayout.horizontalPadding)
                .padding(.vertical, 60)
            }
            .clipShape(Rectangle())
            .contentShape(Rectangle())
        }
        .task {
            playlists = (try? await SubsonicClient.shared.getPlaylists()) ?? []
        }
    }
}

// MARK: - Album Card
/// Fixed-height card: square artwork on a clipped rounded surface, one
/// marquee line each for title and artist so every card matches.
struct AlbumCard: View {
    let album: Album
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoverArtView(id: album.coverArt, size: 260)
                .frame(width: 360, height: 360)
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                ScrollingText(text: album.name, trackID: album.id, isFocused: isFocused, mode: .whenFocused)
                    .font(.subheadline)
                    .fontWeight(.bold)
                ScrollingText(text: album.artist ?? "", trackID: album.id, isFocused: isFocused, mode: .whenFocused)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 360)
        .cardSurface()
    }
}

// MARK: - Track Shelf (horizontal scroll of track cards)
struct TrackShelf: View {
    let title: String
    let songs: [Song]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2).fontWeight(.medium)
                .padding(.leading, AppLayout.horizontalPadding)
                .foregroundColor(.primary.opacity(0.28))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 40) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        TrackCard(song: song, contextSongs: songs, index: index)
                    }
                }
                .padding(.horizontal, AppLayout.horizontalPadding)
                .padding(.vertical, 50)
            }
            .clipShape(Rectangle())
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Track Card
/// A wide card for a single track: artwork with a play/pause badge, then
/// title, artist and album. Pressing plays the track immediately (queueing
/// the rest of the shelf after it); pressing the current track toggles pause.
struct TrackCard: View {
    let song: Song
    let contextSongs: [Song]
    let index: Int
    @ObservedObject private var player = AudioPlayerService.shared
    @Environment(\.appAccent) private var appAccent
    @Environment(\.isFocused) private var isFocused

    private var isCurrent: Bool { player.currentSong?.id == song.id }

    var body: some View {
        Button {
            if isCurrent {
                player.togglePlayPause()
            } else {
                player.load(songs: contextSongs, startIndex: index)
            }
        } label: {
            HStack(spacing: 16) {
                // Artwork sits flush against the card edge; the card's
                // clip shape rounds its outer corners
                CoverArtView(id: song.coverArt, size: 120)
                    .frame(width: 110, height: 110)
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.caption)
                            .foregroundColor(appAccent)
                            .padding(7)
                            .background(.black.opacity(0.6), in: Circle())
                            .padding(5)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    ScrollingText(text: song.title, trackID: song.id, isFocused: isFocused, mode: .whenFocused)
                        .font(.caption)
                        .fontWeight(.bold)
                    ScrollingText(text: song.artist ?? "", trackID: song.id, isFocused: isFocused, mode: .whenFocused)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ScrollingText(text: song.album ?? "", trackID: song.id, isFocused: isFocused, mode: .whenFocused)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 16)
            }
            .frame(width: 420, height: 110, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(CardlessButtonStyle())
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
