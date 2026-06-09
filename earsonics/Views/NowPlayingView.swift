// Views/NowPlayingView.swift
import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var player = AudioPlayerService.shared
    var dismiss: () -> Void = {}
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var lyrics: [StructuredLyrics] = []
    @State private var plainLyrics: Lyrics? = nil
    @State private var lyricsLoading = false
    @State private var isStarred: Bool = false
    @State private var playlists: [Playlist] = []
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CoverArtView(id: player.currentSong?.coverArt, size: 100)
                .scaleEffect(1.8)
                .blur(radius: 60)
                .opacity(0.45)
                .ignoresSafeArea()

            if player.currentSong == nil {
                VStack(spacing: 24) {
                    Image(systemName: "music.note.tv")
                        .font(.system(size: 100)).foregroundColor(.secondary)
                    Text("Nothing playing").font(.largeTitle).bold()
                    Text("Browse your library and start playing music.")
                        .font(.title3).foregroundColor(.secondary)
                }
            } else if showQueue {
                QueueView { showQueue = false }
                    .transition(.move(edge: .trailing))
                    .onExitCommand { showQueue = false }
            } else if showLyrics {
                LyricsView(structured: lyrics, plain: plainLyrics, currentTime: player.currentTime) {
                    showLyrics = false
                }
                .transition(.move(edge: .trailing))
            } else {
                mainPlayerView.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showQueue)
        .animation(.easeInOut(duration: 0.3), value: showLyrics)
        .onChange(of: player.currentSong?.id) {
            showQueue = false; showLyrics = false
            isStarred = player.currentSong?.starred != nil
            Task { await loadLyrics() }
        }
        .task {
            isStarred = player.currentSong?.starred != nil
            playlists = (try? await SubsonicClient.shared.getPlaylists()) ?? []
            await loadLyrics()
        }
        .alert("New playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Create") {
                if !newPlaylistName.isEmpty {
                    Task {
                        if let song = player.currentSong {
                            if let newPl = try? await SubsonicClient.shared.createPlaylist(name: newPlaylistName, songIds: [song.id]) {
                                playlists.append(newPl)
                            }
                        }
                        newPlaylistName = ""
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                newPlaylistName = ""
            }
        }
    }

    // MARK: - Main Player Layout
    var mainPlayerView: some View {
        HStack(alignment: .center, spacing: 60) {
            // Left: Cover Art
            CoverArtView(id: player.currentSong?.coverArt, size: 600)
                .frame(width: 400, height: 400)
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.6), radius: 40, y: 20)

            // Right: Info + Controls
            VStack(alignment: .leading, spacing: 24) {

                // Track info + dismiss button row
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let song = player.currentSong {
                            Text(song.title)
                                .font(.largeTitle).bold().lineLimit(2)
                            Text(song.artist ?? "")
                                .font(.title2).foregroundColor(.secondary)
                            Text(song.album ?? "")
                                .font(.headline).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 12) {
                        // Dismiss — clearly interactive button, no allowsHitTesting wrapping
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.title).foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)

//                        if let song = player.currentSong { FormatBadge(song: song) }

                        // Star button — tappable
                        Button {
                            Task {
                                if let song = player.currentSong {
                                    if isStarred {
                                        try? await SubsonicClient.shared.unstar(songId: song.id)
                                        isStarred = false
                                    } else {
                                        try? await SubsonicClient.shared.star(songId: song.id)
                                        isStarred = true
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: isStarred ? "heart.fill" : "heart")
                                .foregroundColor(isStarred ? .red : .white.opacity(0.7))
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Progress bar + timestamps
                VStack(spacing: 8) {
                    ProgressSlider(value: player.currentTime, total: player.duration) { player.seek(to: $0) }
                    HStack {
                        Text(formatTime(player.currentTime))
                            .font(.callout.monospacedDigit()).foregroundColor(.secondary)
                        Spacer()
                        if player.isBuffering {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Buffering").font(.callout).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text(formatTime(player.duration))
                            .font(.callout.monospacedDigit()).foregroundColor(.secondary)
                    }
                }

                // Transport controls — use .buttonStyle(.plain) + .focusable()
                // They live inside a full-screen view with TabView disabled,
                // so the focus engine will find ONLY these buttons
                HStack(spacing: 60) {
                    TransportButton(icon: "shuffle", isToggled: player.isShuffled) { player.toggleShuffle() }
                    TransportButton(icon: "backward.fill") { player.skipPrevious() }
                    PlayPauseButton(isPlaying: player.isPlaying) { player.togglePlayPause() }
                    TransportButton(icon: "forward.fill") { player.skipNext() }
                    RepeatTransportButton(mode: player.repeatMode) { player.cycleRepeat() }
                }

                // Secondary: Queue + Lyrics + Add to playlist
                HStack(spacing: 80) {
                    SecondaryActionButton(title: "Queue", icon: "list.bullet.indent") {
                        withAnimation { showQueue = true }
                    }
                    SecondaryActionButton(title: "Lyrics", icon: "text.quote") {
                        withAnimation { showLyrics = true }
                    }
                    .disabled(lyrics.isEmpty && plainLyrics?.value == nil)

                    Menu {
                        Button {
                            newPlaylistName = ""
                            showNewPlaylistAlert = true
                        } label: {
                            Label("New playlist...", systemImage: "plus.circle")
                        }
                        if !playlists.isEmpty {
                            Divider()
                            ForEach(playlists) { playlist in
                                Button {
                                    if let song = player.currentSong {
                                        Task {
                                            try? await SubsonicClient.shared.updatePlaylist(
                                                id: playlist.id, songIdsToAdd: [song.id])
                                        }
                                    }
                                } label: {
                                    Label(playlist.name, systemImage: "music.note.list")
                                }
                            }
                        }
                    } label: {
                        Label("Add to playlist", systemImage: "text.badge.plus")
                            .font(.callout)
                            .padding(.horizontal, 5).padding(.vertical, 12)
//                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
//                            .foregroundColor(.white.opacity(0.97))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 50)
    }

    private func loadLyrics() async {
        guard let song = player.currentSong else { return }
        lyricsLoading = true
        async let structured = try? SubsonicClient.shared.getLyricsBySongId(id: song.id)
        async let plain = try? SubsonicClient.shared.getLyrics(artist: song.artist, title: song.title)
        lyrics = await structured ?? []
        plainLyrics = await plain
        lyricsLoading = false
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "--:--" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

// MARK: - Secondary Action Button
struct SecondaryActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.callout)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(Color.clear))
                .foregroundColor(isFocused ? .accentColor : .white.opacity(0.85))
                .scaleEffect(isFocused ? 1.06 : 1.0)
                .animation(.easeInOut(duration: 0.12), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }
}

// MARK: - Transport Button
struct TransportButton: View {
    let icon: String
    var isToggled: Bool = false
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundColor((isFocused || isToggled) ? .accentColor : .white.opacity(0.85))
                    .frame(width: 72, height: 72)
                    .background(Color.clear)
                    .clipShape(Circle())
                
                Circle()
                    .fill(isToggled ? Color.accentColor : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .scaleEffect(isFocused ? 1.12 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }
}

// MARK: - Play/Pause Button
struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 86, height: 86)
                    .scaleEffect(isFocused ? 1.1 : 1.0)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 36, weight: .black))
                    .foregroundColor(isFocused ? .accentColor : .white.opacity(0.85))
            }
            .animation(.easeInOut(duration: 0.12), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }
}

// MARK: - Repeat Button
struct RepeatTransportButton: View {
    let mode: RepeatMode
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 72, height: 72)
                        Image(systemName: mode.icon)
                            .font(.system(size: 30))
                            .foregroundColor((isFocused || mode != .off) ? .accentColor : .white.opacity(0.85))
                    }
                    if mode == .one {
                        Text("1")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white).padding(3)
                            .background(Color.accentColor).clipShape(Circle())
                            .offset(x: -16, y: 16)
                    }
                }
                
                Circle()
                    .fill(mode != .off ? Color.accentColor : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .scaleEffect(isFocused ? 1.12 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }
}

// MARK: - Progress Slider
struct ProgressSlider: View {
    let value: Double
    let total: Double
    let onSeek: (Double) -> Void
    @FocusState private var isFocused: Bool

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, value / total))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(isFocused ? 0.35 : 0.2))
                    .frame(height: isFocused ? 10 : 6)
                Capsule().fill(isFocused ? Color.accentColor : Color.white)
                    .frame(width: geo.size.width * CGFloat(progress), height: isFocused ? 10 : 6)
                Circle().fill(Color.white)
                    .frame(width: isFocused ? 26 : 16, height: isFocused ? 26 : 16)
                    .shadow(radius: 4)
                    .offset(x: geo.size.width * CGFloat(progress) - (isFocused ? 13 : 8))
            }
            .animation(.easeInOut(duration: 0.12), value: isFocused)
        }
        .frame(height: 30)
        .focusable()
        .focused($isFocused)
        .onMoveCommand { direction in
            switch direction {
            case .left:  onSeek(max(0, value - 10))
            case .right: onSeek(min(total, value + 10))
            default: break
            }
        }
    }
}
