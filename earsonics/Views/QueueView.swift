// Views/QueueView.swift
import SwiftUI

struct QueueView: View {
    @EnvironmentObject var appState: AppState
    let onDismiss: () -> Void

    var player: AudioPlayerService { appState.player }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                Text("Queue")
                    .font(.largeTitle).bold()
                    .padding(.leading, 16)
                Spacer()
                Button {
                    player.queue.removeAll(keepingCapacity: false)
                } label: {
                    Text("Clear").foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 30)

            Divider().background(Color.white.opacity(0.2))

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { idx, song in
                        QueueRow(song: song, index: idx,
                                 isCurrent: idx == player.currentIndex) {
                            player.playFromQueue(index: idx)
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 60)
            }
        }
    }
}

struct QueueRow: View {
    let song: Song
    let index: Int
    let isCurrent: Bool
    let onTap: () -> Void
    @EnvironmentObject var appState: AppState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 16) {
            if isCurrent {
                Image(systemName: appState.player.isPlaying ? "waveform" : "play.fill")
                    .foregroundColor(.accentColor)
                    .frame(width: 32)
            } else {
                Text("\(index + 1)")
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .center)
            }

            CoverArtView(id: song.coverArt, size: 80)
                .frame(width: 50, height: 50)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.callout)
                    .fontWeight(isCurrent ? .bold : .regular)
                    .foregroundColor(isCurrent ? .accentColor : .primary)
                Text(song.artist ?? "").font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            FormatBadge(song: song)

            Button {
                appState.player.queue.remove(at: index)
                appState.player.rebuildPlayerItems()
            } label: {
                Image(systemName: "xmark.circle").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isCurrent ? 0 : 1)

            Text(song.durationFormatted).font(.callout).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(focused || isCurrent ? Color.white.opacity(0.12) : Color.clear)
        )
        .focusable()
        .focused($focused)
        .onTapGesture { onTap() }
    }
}
