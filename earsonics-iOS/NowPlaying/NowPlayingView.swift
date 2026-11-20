// earsonics-iOS/NowPlaying/NowPlayingView.swift
import SwiftUI
import AVKit
import MediaPlayer
import EarsonicsCore

/// The full Now Playing screen, opened from the mini player. Narrow windows
/// stack everything, swapping the artwork for lyrics or the queue; with room
/// (iPad, an unfolded iPhone Duo, landscape) the controls sit beside a
/// lyrics or queue panel.
struct NowPlayingView: View {
    enum Panel { case lyrics, queue }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let player = AudioPlayerService.shared
    @State private var panel: Panel?

    var body: some View {
        Group {
            if let song = player.currentSong {
                if horizontalSizeClass == .regular {
                    HStack(spacing: 32) {
                        VStack(spacing: 28) {
                            header
                            Spacer(minLength: 0)
                            // Cover and controls stay together, centred in
                            // the column; the cover grows with the window.
                            Artwork(id: song.coverArt, pixels: 1000, cornerRadius: 24)
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: 520)
                                .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
                            controls(for: song)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: 540)
                        panelView(panel ?? .lyrics)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(28)
                } else {
                    VStack(spacing: 20) {
                        header
                        if let panel {
                            panelView(panel)
                                .frame(maxHeight: .infinity)
                        } else {
                            Artwork(id: song.coverArt, pixels: 900, cornerRadius: 24)
                                .aspectRatio(1, contentMode: .fit)
                                .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
                                .frame(maxHeight: .infinity)
                        }
                        controls(for: song)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
            }
        }
        .background { NowPlayingBackground(coverArt: player.currentSong?.coverArt) }
        .preferredColorScheme(.dark)
        // The queue ended or was cleared: nothing left to show.
        .onChange(of: player.currentSong == nil) { _, isEmpty in if isEmpty { dismiss() } }
    }

    private var header: some View {
        HStack {
            Button("Close", systemImage: "chevron.down") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
            Spacer()
            Text("Now Playing").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if let song = player.currentSong {
                Menu {
                    SongMenu(song: song)
                } label: {
                    Image(systemName: "ellipsis").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("More")
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func controls(for song: Song) -> some View {
        VStack(spacing: 22) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title).font(.title2.bold()).lineLimit(1)
                    Text(song.artist ?? "").font(.title3).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                FavouriteButton(song: song)
            }
            Scrubber()
            TransportControls()
            HStack {
                panelButton(.lyrics, symbol: "quote.bubble", label: "Lyrics")
                Spacer()
                RoutePicker()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("AirPlay")
                Spacer()
                panelButton(.queue, symbol: "list.bullet", label: "Queue")
            }
            SystemVolumeSlider()
                .frame(height: 34)
        }
    }

    private func panelButton(_ target: Panel, symbol: String, label: String) -> some View {
        let isOn = panel == target || (horizontalSizeClass == .regular && panel == nil && target == .lyrics)
        return Button(label, systemImage: symbol) {
            withAnimation(.snappy) { panel = (panel == target) ? nil : target }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .frame(width: 44, height: 44)
        .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder private func panelView(_ panel: Panel) -> some View {
        switch panel {
        case .lyrics: LyricsPanel()
        case .queue:  QueuePanel()
        }
    }
}

/// The cover, blurred and darkened, filling the screen behind everything.
private struct NowPlayingBackground: View {
    let coverArt: String?

    var body: some View {
        ZStack {
            Color.black
            Artwork(id: coverArt, pixels: 300, cornerRadius: 0)
                .scaledToFill()
                .blur(radius: 60)
                .opacity(0.6)
            LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

/// Elapsed and remaining time with a draggable position.
private struct Scrubber: View {
    private let player = AudioPlayerService.shared
    @State private var dragValue: Double?
    @State private var settle: Task<Void, Never>?

    var body: some View {
        let total = max(player.duration, 1)
        let current = dragValue ?? player.currentTime
        VStack(spacing: 4) {
            Slider(value: Binding(get: { min(current, total) }, set: drag), in: 0...total) { editing in
                if !editing, let value = dragValue { commit(value) }
            }
            .accessibilityLabel("Position")
            .accessibilityValue("\(Self.time(current)) of \(Self.time(total))")
            HStack {
                Text(Self.time(current))
                Spacer()
                Text("-" + Self.time(max(total - current, 0)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    /// The slider doesn't always report the end of a drag, so a seek also
    /// happens once the thumb has rested for a moment.
    private func drag(to value: Double) {
        dragValue = value
        settle?.cancel()
        settle = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            commit(value)
        }
    }

    private func commit(_ value: Double) {
        settle?.cancel()
        player.seek(to: value)
        // Keep showing where it was dragged until the player catches up.
        settle = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            dragValue = nil
        }
    }

    static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Shuffle, previous, play/pause, next and repeat.
private struct TransportControls: View {
    private let player = AudioPlayerService.shared

    var body: some View {
        HStack {
            Button("Shuffle", systemImage: "shuffle") { player.toggleShuffle() }
                .foregroundStyle(player.isShuffled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .accessibilityValue(player.isShuffled ? "On" : "Off")
            Spacer()
            Button("Previous", systemImage: "backward.fill") { player.skipPrevious() }
                .font(.title)
                .accessibilityIdentifier("nowPlaying.previous")
            Spacer()
            Button(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.circle.fill" : "play.circle.fill") {
                player.togglePlayPause()
            }
            .font(.system(size: 72))
            .contentTransition(.symbolEffect(.replace))
            .accessibilityIdentifier("nowPlaying.playPause")
            Spacer()
            Button("Next", systemImage: "forward.fill") { player.skipNext() }
                .font(.title)
                .accessibilityIdentifier("nowPlaying.next")
            Spacer()
            Button("Repeat", systemImage: player.repeatMode == .one ? "repeat.1" : "repeat") { player.cycleRepeat() }
                .foregroundStyle(player.repeatMode == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .accessibilityValue(player.repeatMode == .off ? "Off" : player.repeatMode == .all ? "All" : "One")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .font(.title3)
    }
}

/// The heart for the playing song.
private struct FavouriteButton: View {
    let song: Song
    private var isStarred: Bool { LibraryStore.shared.isStarred(.song, id: song.id, fetched: song.starred) }

    var body: some View {
        Button(isStarred ? "Remove from Favourites" : "Add to Favourites", systemImage: isStarred ? "heart.fill" : "heart") {
            Task { await LibraryStore.shared.toggleStar(.song, id: song.id, isStarred: isStarred) }
        }
        .labelStyle(.iconOnly)
        .font(.title2)
        .foregroundStyle(isStarred ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .buttonStyle(.plain)
        .contentTransition(.symbolEffect(.replace))
    }
}

/// The system AirPlay / output picker (AirPlay 2 speakers, HomePod,
/// Bluetooth).
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = .secondaryLabel
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.activeTintColor = UIColor(context.environment.appAccent)
    }
}

/// The system volume slider (follows the hardware buttons and the output).
private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        MPVolumeView()
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {}
}
