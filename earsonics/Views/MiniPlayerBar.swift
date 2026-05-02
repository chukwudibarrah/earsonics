// Views/MiniPlayerBar.swift
import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject var appState: AppState
    @Binding var showNowPlaying: Bool
    @FocusState private var focused: Bool

    var player: AudioPlayerService { appState.player }

    var body: some View {
        guard let song = player.currentSong else { return AnyView(EmptyView()) }
        return AnyView(
            HStack(spacing: 20) {
                CoverArtView(id: song.coverArt, size: 100)
                    .frame(width: 56, height: 56)
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title).font(.callout).bold().lineLimit(1)
                    Text(song.artist ?? "").font(.caption).foregroundColor(.secondary).lineLimit(1)
                }

                Spacer()

                // Progress
                if player.duration > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.2)).frame(height: 4)
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * CGFloat(player.currentTime / player.duration), height: 4)
                        }
                    }
                    .frame(width: 200, height: 4)
                }

                Button { player.skipPrevious() } label: {
                    Image(systemName: "backward.fill").font(.title3)
                }
                .buttonStyle(.plain)

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button { player.skipNext() } label: {
                    Image(systemName: "forward.fill").font(.title3)
                }
                .buttonStyle(.plain)

                Button { showNowPlaying = true } label: {
                    Image(systemName: "chevron.up.circle")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                FormatBadge(song: song)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        )
    }
}
