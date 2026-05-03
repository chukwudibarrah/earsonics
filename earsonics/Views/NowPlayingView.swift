// Views/NowPlayingView.swift
import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var player = AudioPlayerService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var lyrics: [StructuredLyrics] = []
    @State private var plainLyrics: Lyrics? = nil
    @State private var lyricsLoading = false
    @State private var isStarred: Bool = false

    var body: some View {
        ZStack {
            // Solid opaque base — prevents album detail bleeding through on tvOS
            Color.black.ignoresSafeArea()

            // Blurred cover art background on top of solid black
            CoverArtView(id: player.currentSong?.coverArt, size: 100)
                .scaleEffect(1.8)
                .blur(radius: 60)
                .opacity(0.5)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .padding(40)
                }
                Spacer()
            }
            .zIndex(10)

            if player.currentSong == nil {
                // Empty state
                VStack(spacing: 24) {
                    Image(systemName: "music.note.tv")
                        .font(.system(size: 100))
                        .foregroundColor(.secondary)
                    Text("Nothing Playing")
                        .font(.largeTitle).bold()
                    Text("Browse your library and start playing music.")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            } else if showQueue {
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
        .animation(.easeInOut(duration: 0.3), value: player.currentSong?.id)
        .onChange(of: player.currentSong?.id) { _ in
            showQueue = false
            showLyrics = false
            isStarred = player.currentSong?.starred != nil
            Task { await loadLyrics() }
        }
        .task {
            isStarred = player.currentSong?.starred != nil
            await loadLyrics()
        }
    }

    // MARK: - Main Player Layout
    var mainPlayerView: some View {
        HStack(alignment: .center, spacing: 80) {
            // Left: Cover Art
            CoverArtView(id: player.currentSong?.coverArt, size: 600)
                .frame(width: 420, height: 420)
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.6), radius: 40, y: 20)

            // Right: Controls
            VStack(alignment: .leading, spacing: 28) {

                // Track info
                if let song = player.currentSong {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.title)
                                    .font(.largeTitle).bold()
                                    .lineLimit(2)
                                Text(song.artist ?? "")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text(song.album ?? "")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(spacing: 8) {
                                FormatBadge(song: song)
                                StarButton(isStarred: isStarred, songId: song.id) { newVal in
                                    isStarred = newVal
                                }
                            }
                        }
                    }
                }

                // Progress bar + timestamps
                VStack(spacing: 10) {
                    ProgressSlider(value: player.currentTime, total: player.duration) { newVal in
                        player.seek(to: newVal)
                    }
                    HStack {
                        Text(formatTime(player.currentTime))
                            .font(.callout.monospacedDigit())
                            .foregroundColor(.secondary)
                        Spacer()
                        if player.isBuffering {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Buffering").font(.callout).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text(formatTime(player.duration))
                            .font(.callout.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }

                // Main transport controls
                HStack(spacing: 44) {
                    // Shuffle
                    Button { player.toggleShuffle() } label: {
                        Image(systemName: "shuffle")
                            .font(.title2)
                            .foregroundColor(player.isShuffled ? .accentColor : .white.opacity(0.7))
                    }
                    .buttonStyle(.plain)

                    // Previous
                    Button { player.skipPrevious() } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 36))
                    }
                    .buttonStyle(.plain)

                    // Play / Pause
                    Button { player.togglePlayPause() } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 88, height: 88)
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 34))
                                .foregroundColor(.black)
                        }
                    }
                    .buttonStyle(.plain)

                    // Next
                    Button { player.skipNext() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 36))
                    }
                    .buttonStyle(.plain)

                    // Repeat
                    Button { player.cycleRepeat() } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: player.repeatMode.icon)
                                .font(.title2)
                                .foregroundColor(player.repeatMode != .off ? .accentColor : .white.opacity(0.7))
                                .frame(width: 36, height: 36)
                            if player.repeatMode == .one {
                                Text("1")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(3)
                                    .background(Color.accentColor)
                                    .clipShape(Circle())
                                    .offset(x: 8, y: -6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Secondary actions: Queue & Lyrics
                HStack(spacing: 20) {
                    Button {
                        withAnimation { showQueue = true }
                    } label: {
                        Label("Queue", systemImage: "list.bullet.indent")
                            .font(.callout)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation { showLyrics = true }
                    } label: {
                        Label("Lyrics", systemImage: "text.quote")
                            .font(.callout)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(lyrics.isEmpty && plainLyrics?.value == nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 60)
    }

    // MARK: - Helpers
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
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
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
                Capsule()
                    .fill(Color.white.opacity(isFocused ? 0.35 : 0.2))
                    .frame(height: isFocused ? 10 : 6)
                Capsule()
                    .fill(isFocused ? Color.accentColor : Color.white)
                    .frame(width: geo.size.width * CGFloat(progress), height: isFocused ? 10 : 6)
                Circle()
                    .fill(Color.white)
                    .frame(width: isFocused ? 26 : 18, height: isFocused ? 26 : 18)
                    .shadow(radius: 4)
                    .offset(x: geo.size.width * CGFloat(progress) - (isFocused ? 13 : 9))
            }
            .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
        .frame(height: 30)
        .focusable()
        .focused($isFocused)
        .onMoveCommand { direction in
            let step: Double = 10
            switch direction {
            case .left:  onSeek(max(0, value - step))
            case .right: onSeek(min(total, value + step))
            default: break
            }
        }
    }
}
