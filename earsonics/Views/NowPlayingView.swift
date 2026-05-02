// Views/NowPlayingView.swift
import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var appState: AppState
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var lyrics: [StructuredLyrics] = []
    @State private var plainLyrics: Lyrics? = nil
    @State private var lyricsLoading = false

    var player: AudioPlayerService { appState.player }

    var body: some View {
        ZStack {
            // Background blur from cover art
            CoverArtView(id: player.currentSong?.coverArt, size: 100)
                .scaleEffect(1.5)
                .blur(radius: 40)
                .opacity(0.4)
                .ignoresSafeArea()

            if showQueue {
                QueueView { showQueue = false }
                    .transition(.move(edge: .trailing))
            } else if showLyrics {
                LyricsView(structured: lyrics, plain: plainLyrics, currentTime: player.currentTime) {
                    showLyrics = false
                }
                .transition(.move(edge: .trailing))
            } else {
                mainPlayerView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showQueue)
        .animation(.easeInOut(duration: 0.3), value: showLyrics)
        .onChange(of: player.currentSong?.id) { _ in
            Task { await loadLyrics() }
        }
        .task { await loadLyrics() }
    }

    var mainPlayerView: some View {
        HStack(spacing: 80) {
            // Cover Art
            VStack {
                Spacer()
                CoverArtView(id: player.currentSong?.coverArt, size: 600)
                    .frame(width: 400, height: 400)
                    .cornerRadius(20)
                    .shadow(radius: 30)
                Spacer()
            }

            // Controls
            VStack(alignment: .leading, spacing: 24) {
                // Track info
                VStack(alignment: .leading, spacing: 8) {
                    if let song = player.currentSong {
                        HStack {
                            Text(song.title)
                                .font(.largeTitle).bold()
                                .lineLimit(2)
                            Spacer()
                            FormatBadge(song: song)
                            StarButton(isStarred: song.starred != nil, songId: song.id)
                        }
                        Text(song.artist ?? "").font(.title3).foregroundColor(.secondary)
                        Text(song.album ?? "").font(.headline).foregroundColor(.secondary)
                    } else {
                        Text("Nothing Playing").font(.largeTitle).foregroundColor(.secondary)
                    }
                }

                // Progress bar
                VStack(spacing: 8) {
                    ProgressSlider(value: player.currentTime, total: player.duration) { newVal in
                        player.seek(to: newVal)
                    }
                    HStack {
                        Text(formatTime(player.currentTime)).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(formatTime(player.duration)).font(.caption).foregroundColor(.secondary)
                    }
                }

                // Main controls
                HStack(spacing: 40) {
                    // Shuffle
                    Button { player.toggleShuffle() } label: {
                        Image(systemName: "shuffle")
                            .font(.title2)
                            .foregroundColor(player.isShuffled ? .accentColor : .white)
                    }
                    .buttonStyle(.plain)

                    // Previous
                    Button { player.skipPrevious() } label: {
                        Image(systemName: "backward.fill").font(.largeTitle)
                    }
                    .buttonStyle(.plain)

                    // Play/Pause
                    Button { player.togglePlayPause() } label: {
                        ZStack {
                            Circle().fill(Color.white).frame(width: 80, height: 80)
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title)
                                .foregroundColor(.black)
                        }
                    }
                    .buttonStyle(.plain)

                    // Next
                    Button { player.skipNext() } label: {
                        Image(systemName: "forward.fill").font(.largeTitle)
                    }
                    .buttonStyle(.plain)

                    // Repeat
                    Button { player.cycleRepeat() } label: {
                        Image(systemName: player.repeatMode.icon)
                            .font(.title2)
                            .foregroundColor(player.repeatMode != .off ? .accentColor : .white)
                            .overlay(
                                player.repeatMode == .one ?
                                    Text("1").font(.caption2).offset(x: 6, y: -6) : nil
                                , alignment: .topTrailing
                            )
                    }
                    .buttonStyle(.plain)
                }

                // Secondary actions
                HStack(spacing: 24) {
                    Button {
                        withAnimation { showQueue.toggle() }
                    } label: {
                        Label("Queue", systemImage: "list.bullet")
                            .font(.callout)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation { showLyrics.toggle() }
                    } label: {
                        Label("Lyrics", systemImage: "text.quote")
                            .font(.callout)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(lyrics.isEmpty && plainLyrics?.value == nil)

                    if player.isBuffering {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text("Buffering...").font(.callout).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(80)
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
        let m = Int(seconds) / 60; let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Progress Slider
struct ProgressSlider: View {
    let value: Double
    let total: Double
    let onSeek: (Double) -> Void
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var progress: Double {
        guard total > 0 else { return 0 }
        return (isDragging ? dragValue : value) / total
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2)).frame(height: 6)
                Capsule()
                    .fill(Color.white)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, progress))), height: 6)
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .offset(x: geo.size.width * CGFloat(max(0, min(1, progress))) - 10)
            }
            .focusable()
            .focused($isFocused)
            .onMoveCommand { direction in
                if direction == .left {
                    onSeek(max(0, value - 10))
                } else if direction == .right {
                    onSeek(min(total, value + 10))
                }
            }
        }
        .frame(height: 20)
    }

    @FocusState private var isFocused: Bool
}
