// Views/MiniPlayerBar.swift
import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var player = AudioPlayerService.shared
    var onTap: () -> Void

    var body: some View {
        if let song = player.currentSong {
            Button(action: onTap) {
                HStack(spacing: 14) {
                    CoverArtView(id: song.coverArt, size: 120)
                        .frame(width: 46, height: 46)
                        .cornerRadius(6)
                        .shadow(radius: 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.caption2).bold()
                            .lineLimit(1)
                        Text(song.artist ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 200, alignment: .leading)

                    Spacer(minLength: 0)

                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.callout)
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(width: 360, height: 100)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            }
            .buttonStyle(.card)
        }
    }
}
