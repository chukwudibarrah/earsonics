// Views/MiniPlayerBar.swift
import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var player = AudioPlayerService.shared
    @FocusState private var isFocused: Bool
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
                        ScrollingText(text: song.title, trackID: song.id, isFocused: isFocused)
                            .frame(height: 14)
                        ScrollingText(text: song.artist ?? "", trackID: song.id, isFocused: isFocused)
                            .frame(height: 14)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                    .frame(maxWidth: 200, alignment: .leading)

                    Spacer(minLength: 0)

                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.callout)
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 16)
                .frame(width: 350, height: AppLayout.miniPlayerHeight)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            }
            .buttonStyle(.card)
            .focused($isFocused)
        }
    }
}
