// Views/MiniPlayerBar.swift
import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var player = AudioPlayerService.shared
    var onTap: () -> Void

    var body: some View {
        guard let song = player.currentSong else { return AnyView(EmptyView()) }
        return AnyView(content(song: song))
    }

    @ViewBuilder
    private func content(song: Song) -> some View {
        HStack(spacing: 0) {

            // Song info — tappable to open full Now Playing
            Button(action: onTap) {
                HStack(spacing: 16) {
                    CoverArtView(id: song.coverArt, size: 80)
                        .frame(width: 48, height: 48)
                        .cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.callout).bold()
                            .lineLimit(1)
                            .foregroundColor(.white)
                        Text(song.artist ?? "")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.leading, 24)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            // Transport controls
            HStack(spacing: 8) {
                // Previous
                MiniControlButton(icon: "backward.fill") {
                    player.skipPrevious()
                }

                // Play / Pause
                MiniControlButton(
                    icon: player.isPlaying ? "pause.fill" : "play.fill",
                    prominent: true
                ) {
                    player.togglePlayPause()
                }

                // Next
                MiniControlButton(icon: "forward.fill") {
                    player.skipNext()
                }
            }
            .padding(.trailing, 24)

            // Progress indicator + format badge
            VStack(alignment: .trailing, spacing: 4) {
                FormatBadge(song: song)
                if player.duration > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.2)).frame(height: 3)
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(
                                    width: geo.size.width * CGFloat(min(1, player.currentTime / player.duration)),
                                    height: 3
                                )
                        }
                    }
                    .frame(width: 120, height: 3)
                }
            }
            .padding(.trailing, 30)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
    }
}

// MARK: - Mini Control Button
private struct MiniControlButton: View {
    let icon: String
    var prominent: Bool = false
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            ZStack {
                if prominent {
                    Circle()
                        .fill(focused ? Color.accentColor : Color.white.opacity(0.9))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(focused ? .white : .black)
                } else {
                    Circle()
                        .fill(focused ? Color.white.opacity(0.25) : Color.white.opacity(0.08))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .scaleEffect(focused ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: focused)
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focused)
    }
}
