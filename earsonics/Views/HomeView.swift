// Views/HomeView.swift
import SwiftUI

// CardlessButtonStyle is defined in Views/Shared/FocusStyle.swift

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = LibraryViewModel()
    @State private var navPath = NavigationPath()
    @ObservedObject private var player = AudioPlayerService.shared

    /// Whether Home is the selected tab (set by ContentView).
    var isSelectedTab = true
    @FocusState private var firstAlbumFocused: Bool
    @State private var didPlaceInitialFocus = false

    /// The shelf whose first album receives initial focus.
    private var focusShelfIsNewest: Bool { !vm.newestAlbums.isEmpty }

    var body: some View {
        // Use path-based NavigationStack so we can push programmatically
        // from a plain Button — no NavigationLink card effect
        NavigationStack(path: $navPath) {
            Group {
                if !appState.isConnected && appState.serverStore.servers.isEmpty {
                    NoServerView()
                } else if vm.isLoading && vm.recentAlbums.isEmpty {
                    FocusableProgressView(title: "Loading library...")
                } else if let error = vm.error,
                          vm.newestAlbums.isEmpty,
                          vm.recentAlbums.isEmpty,
                          vm.randomAlbums.isEmpty {
                    HomeLoadErrorView(
                        serverName: appState.serverStore.activeServer?.name,
                        message: error,
                        retry: { Task { await vm.loadHome() } }
                    )
                } else if vm.newestAlbums.isEmpty && vm.recentAlbums.isEmpty
                            && vm.randomAlbums.isEmpty && vm.keepSpinningSongs.isEmpty {
                    // Loaded fine but nothing to show (e.g. an empty library).
                    // Needs a focusable control, or Menu would exit the app.
                    VStack(spacing: 20) {
                        Image(systemName: "music.note.house")
                            .font(.system(size: 70))
                            .foregroundColor(.secondary)
                        Text("Your library is empty")
                            .font(.title2.bold())
                        Text("Albums will appear here once your server has scanned some music.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            Task { await vm.loadHome() }
                        } label: {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(AccentPillButtonStyle())
                    }
                    .padding(60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppLayout.verticalSpacing) {
                            if !vm.newestAlbums.isEmpty {
                                AlbumShelf(title: "Just arrived", albums: vm.newestAlbums, playlists: vm.playlists, navPath: $navPath,
                                           focusFirstCard: $firstAlbumFocused)
                            }
                            if !vm.keepSpinningSongs.isEmpty {
                                TrackShelf(title: "Keep spinning", songs: vm.keepSpinningSongs)
                            }
                            if !vm.recentAlbums.isEmpty {
                                AlbumShelf(title: "Recently played", albums: vm.recentAlbums, playlists: vm.playlists, navPath: $navPath,
                                           focusFirstCard: focusShelfIsNewest ? nil : $firstAlbumFocused)
                            }
                            if !vm.randomAlbums.isEmpty {
                                AlbumShelf(title: "Discover", albums: vm.randomAlbums, playlists: vm.playlists, navPath: $navPath)
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
            // At launch tvOS gives focus to a sidebar item — even though the
            // sidebar is collapsed and invisible — because Home has nothing to
            // focus yet. Select then just re-picks the tab, Menu exits the
            // app, and tvOS only moves focus into the content ~8s later. So
            // once the first shelf exists, put focus on its first album.
            // Once per Home instance, so later reloads never move focus.
            .onChange(of: vm.newestAlbums.isEmpty && vm.recentAlbums.isEmpty) { _, noShelves in
                guard !noShelves, isSelectedTab, !didPlaceInitialFocus, navPath.isEmpty else { return }
                didPlaceInitialFocus = true
                Task {
                    await Task.yield()   // let the shelf join the hierarchy first
                    firstAlbumFocused = true
                }
            }
        }
    }
}

// MARK: - Home Load Error
struct HomeLoadErrorView: View {
    let serverName: String?
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 70))
                .foregroundColor(.secondary)
            Text("Couldn’t load your library")
                .font(.title2.bold())
            if let serverName {
                Text("The active server, \(serverName), did not respond successfully.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(AccentPillButtonStyle())
            Text("Check the server in Settings, or choose a different active server.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Album Shelf (horizontal scroll)
struct AlbumShelf: View {
    let title: String
    let albums: [Album]
    let playlists: [Playlist]
    @Binding var navPath: NavigationPath
    /// Bound to the first card, so Home can give it initial focus.
    var focusFirstCard: FocusState<Bool>.Binding? = nil

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
                        .modifier(OptionalFocus(binding: album.id == albums.first?.id ? focusFirstCard : nil))
                        .contextMenu {
                            Button {
                                // Album-list results don't include tracks, so
                                // fetch the album before playing it.
                                Task {
                                    guard let detailed = try? await SubsonicClient.shared.getAlbum(id: album.id),
                                          let songs = detailed.songs, !songs.isEmpty else { return }
                                    AudioPlayerService.shared.load(songs: songs, startIndex: 0)
                                }
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            if !playlists.isEmpty {
                                Divider()
                                ForEach(playlists) { playlist in
                                    Button {
                                        Task { await PlaylistAdder.shared.addAlbum(id: album.id, to: playlist) }
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
    }
}

/// Applies `.focused(binding)` only when a binding is given.
private struct OptionalFocus: ViewModifier {
    let binding: FocusState<Bool>.Binding?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let binding {
            content.focused(binding)
        } else {
            content
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
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            Text("No server configured")
                .font(.title).bold()
            Text("Add your Navidrome/Subsonic server in Settings.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            // Also the screen's only focusable element — without it, nothing
            // can take focus and Menu exits the app.
            Button {
                openSettings()
            } label: {
                Label("Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(AccentPillButtonStyle())
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
