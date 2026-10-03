// Views/QueueView.swift
import SwiftUI

struct QueueView: View {
    @EnvironmentObject var appState: AppState
    let onDismiss: () -> Void

    // Observed directly: changes inside the player don't propagate through appState.
    @ObservedObject private var player = AudioPlayerService.shared

    @FocusState private var focusedRow: Int?

    // A plain header rather than a NavigationStack toolbar: this screen is an
    // overlay, not a navigation destination, and a stack here would be nested
    // inside the tab's own. Menu is handled by NowPlayingView.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                        Text("Back")
                            .font(.headline)
                    }
                }
                .buttonStyle(AccentIconButtonStyle())

                Text("Queue")
                    .font(.largeTitle).bold()
                    .padding(.leading, 30)
                Spacer()

                Button {
                    // Stops playback too — emptying the array alone left the
                    // track playing with no way to control it. Now Playing
                    // closes itself once the queue is empty.
                    player.clearQueue()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(AccentIconButtonStyle())
            }
            .padding(.horizontal, AppLayout.horizontalPadding)
            .padding(.vertical, 30)

            ScrollView {
                LazyVStack(spacing: 2) {
                    // Keyed by position: the same song can be queued more than once.
                    ForEach(Array(player.queue.enumerated()), id: \.offset) { idx, song in
                        Button {
                            player.playFromQueue(index: idx)
                        } label: {
                            QueueRow(song: song, index: idx, isCurrent: idx == player.currentIndex)
                        }
                        .buttonStyle(CardlessButtonStyle())
                        .focused($focusedRow, equals: idx)
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, AppLayout.horizontalPadding)
            }
            // Open on the playing track rather than the top of the queue.
            .defaultFocus($focusedRow, player.currentIndex)
        }
    }
}

struct QueueRow: View {
    let song: Song
    let index: Int
    let isCurrent: Bool
    @EnvironmentObject var appState: AppState
    @Environment(\.appAccent) private var appAccent

    var body: some View {
        HStack(spacing: 16) {
            if isCurrent {
                Image(systemName: appState.player.isPlaying ? "waveform" : "play.fill")
                    .foregroundColor(appAccent)
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
                    .foregroundColor(isCurrent ? appAccent : .primary)
                Text(song.artist ?? "").font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            FormatBadge(song: song)

            Text(song.durationFormatted).font(.callout).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .cardSurface(cornerRadius: 10)
    }
}
