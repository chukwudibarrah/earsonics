// earsonics-iOS/NowPlaying/LyricsAndQueue.swift
import SwiftUI
import EarsonicsCore

/// Lyrics for the playing song. Synced lyrics highlight the current line and
/// keep it in view; tap a line to jump there. Unsynced lyrics are plain text.
struct LyricsPanel: View {
    private let player = AudioPlayerService.shared
    @State private var synced: [StructuredLyrics.Line] = []
    @State private var plain: String?
    @State private var isLoading = false
    /// Set while the person scrolls, so following the song doesn't fight them.
    @State private var lastManualScroll = Date.distantPast

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if !synced.isEmpty {
                syncedView
            } else if let plain {
                ScrollView {
                    Text(plain)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical)
                }
                .scrollIndicators(.hidden)
            } else {
                ContentUnavailableView("No lyrics", systemImage: "quote.bubble",
                                       description: Text("Your server doesn’t have lyrics for this song."))
            }
        }
        .task(id: player.currentSong?.id) { await load() }
    }

    private var currentIndex: Int? {
        let ms = Int(player.currentTime * 1000)
        return synced.lastIndex { ($0.start ?? 0) <= ms }
    }

    private var syncedView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(synced.enumerated()), id: \.offset) { index, line in
                        Button {
                            if let start = line.start { player.seek(to: Double(start) / 1000) }
                        } label: {
                            Text(line.value.isEmpty ? "♪" : line.value)
                                .font(.title2.bold())
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(index == currentIndex ? .primary : .tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .animation(.easeOut(duration: 0.25), value: currentIndex)
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.vertical, 40)
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(DragGesture().onChanged { _ in lastManualScroll = .now })
            .onChange(of: currentIndex) { _, index in
                guard let index, Date.now.timeIntervalSince(lastManualScroll) > 4 else { return }
                withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func load() async {
        synced = []
        plain = nil
        guard let song = player.currentSong else { return }
        isLoading = true
        defer { isLoading = false }
        let structured = (try? await SubsonicClient.shared.getLyricsBySongId(id: song.id)) ?? []
        if let lines = structured.first(where: { $0.synced == true })?.lines, !lines.isEmpty {
            synced = lines
        } else if let lines = structured.first?.lines, !lines.isEmpty {
            plain = lines.map(\.value).joined(separator: "\n")
        } else if let text = (try? await SubsonicClient.shared.getLyrics(artist: song.artist, title: song.title))?.value,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            plain = text
        }
    }
}

/// What's playing and what's next. Tap a song to play it. Songs added
/// automatically when the queue ran out are marked Autoplay.
struct QueuePanel: View {
    private let player = AudioPlayerService.shared

    var body: some View {
        let entries = player.playQueue.entries
        let current = player.playQueue.currentIndex
        ScrollViewReader { proxy in
            List {
                if entries.indices.contains(current) {
                    Section("Now Playing") {
                        row(entries[current], index: current, isCurrent: true)
                    }
                }
                let upcoming = Array(entries.indices.dropFirst(current + 1))
                Section(upcoming.isEmpty ? "Nothing up next" : "Up Next") {
                    ForEach(upcoming, id: \.self) { index in
                        row(entries[index], index: index, isCurrent: false)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onAppear { proxy.scrollTo(current, anchor: .top) }
        }
    }

    private func row(_ entry: QueueEntry, index: Int, isCurrent: Bool) -> some View {
        Button {
            if !isCurrent { player.playFromQueue(index: index) }
        } label: {
            HStack(spacing: 12) {
                Artwork(id: entry.song.coverArt, pixels: 120, cornerRadius: 8)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.song.title)
                        .font(.body.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    Text(entry.song.artist ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if entry.isAutoplay {
                    Text("Autoplay")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.12), in: Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .id(index)
    }
}
