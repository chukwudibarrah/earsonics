// Views/MiniPlayerBar.swift
import SwiftUI

/// Floating now-playing pill shown at the top-right of the screen.
/// The leading end is fully curved around the circular artwork; the glow
/// takes the user-selected accent colour.
struct MiniPlayerBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var player = AudioPlayerService.shared
    @FocusState private var isFocused: Bool
    @Environment(\.appAccent) private var appAccent
    var onTap: () -> Void

    private var pillShape: UnevenRoundedRectangle {
        let height = AppLayout.miniPlayerHeight
        return UnevenRoundedRectangle(
            topLeadingRadius: height / 2,
            bottomLeadingRadius: height / 2,
            bottomTrailingRadius: 16,
            topTrailingRadius: 16
        )
    }

    /// "Title, Artist, playing" — plus the player's error, if a track
    /// couldn't be played (otherwise only shown on the Now Playing screen).
    private func accessibilityState(for song: Song) -> String {
        var parts = [song.title, song.artist ?? ""]
        if let error = player.playbackError { parts.append(error) }
        parts.append(player.isPlaying ? "playing" : "paused")
        return parts.joined(separator: ", ")
    }

    var body: some View {
        if let song = player.currentSong {
            Button(action: onTap) {
                HStack(spacing: 14) {
                    CoverArtView(id: song.coverArt, size: 120)
                        .frame(width: AppLayout.miniPlayerHeight - 12,
                               height: AppLayout.miniPlayerHeight - 12)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        ScrollingText(text: song.title, trackID: song.id, isFocused: isFocused)
                            .frame(height: 22)
                        ScrollingText(text: song.artist ?? "", trackID: song.id, isFocused: isFocused)
                            .frame(height: 22)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                    .frame(maxWidth: 220, alignment: .leading)

                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.callout)
                        .foregroundColor(appAccent)
                }
                .padding(.leading, 6)
                .padding(.trailing, 20)
                .frame(height: AppLayout.miniPlayerHeight)
                .background(.regularMaterial, in: pillShape)
                .shadow(color: appAccent.opacity(0.55), radius: 16, y: 4)
                .accentFocusRing(pillShape)
            }
            .buttonStyle(CardlessButtonStyle())
            .focused($isFocused)
            .accessibilityIdentifier("miniPlayer")
            .accessibilityLabel("Now playing")
            .accessibilityValue(accessibilityState(for: song))
            .accessibilityHint("Opens the player")
        }
    }
}
