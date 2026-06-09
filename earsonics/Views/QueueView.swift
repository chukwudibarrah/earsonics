// Views/QueueView.swift
import SwiftUI

struct QueueView: View {
    @EnvironmentObject var appState: AppState
    let onDismiss: () -> Void

    var player: AudioPlayerService { appState.player }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { idx, song in
                        Button {
                            player.playFromQueue(index: idx)
                        } label: {
                            QueueRow(song: song, index: idx, isCurrent: idx == player.currentIndex)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.top, 350)
                .padding(.bottom, 600)
                .padding(.horizontal, AppLayout.horizontalPadding)
            }
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        player.queue.removeAll(keepingCapacity: false)
                    } label: {
                        Text("Clear").foregroundColor(.red)
                    }
                }
            }
        }
    }
}

struct QueueRow: View {
    let song: Song
    let index: Int
    let isCurrent: Bool
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            if isCurrent {
                Image(systemName: appState.player.isPlaying ? "waveform" : "play.fill")
                    .foregroundColor(.accentColor)
                    .frame(width: 32)
            } else {
                Text("\(index + 1)")
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .center)
            }

            CoverArtView(id: song.coverArt, size: 80)
                .frame(width: 50, height: 50)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 5) {
                Text(song.title)
                    .font(.callout)
                    .fontWeight(isCurrent ? .bold : .regular)
                    .foregroundColor(isCurrent ? .accentColor : .primary)
                Text(song.artist ?? "").font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            FormatBadge(song: song)

            Text(song.durationFormatted).font(.callout).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
