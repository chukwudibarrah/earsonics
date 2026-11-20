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

/// What's playing and what's next. Tap a song to play it; swipe to remove
/// it or play it next; drag (or tap Edit) to reorder; Clear empties Up Next.
/// Songs added automatically when the queue ran out are marked Autoplay.
struct QueuePanel: View {
    private let player = AudioPlayerService.shared
    @State private var editMode = EditMode.inactive
    @State private var confirmsClear = false

    var body: some View {
        let entries = player.playQueue.entries
        let current = player.playQueue.currentIndex
        let upNext = Array(entries.indices.dropFirst(current + 1))
        ScrollViewReader { proxy in
            List {
                if entries.indices.contains(current) {
                    Section("Now Playing") {
                        row(entries[current], index: current, isCurrent: true)
                    }
                }
                Section {
                    ForEach(upNext, id: \.self) { index in
                        row(entries[index], index: index, isCurrent: false)
                            .swipeActions(edge: .trailing) {
                                Button("Remove", systemImage: "minus.circle", role: .destructive) {
                                    player.removeFromQueue(at: [index])
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if index > current + 1 {
                                    Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                                        player.playNext(entryAt: index)
                                    }
                                    .tint(.accentColor)
                                }
                            }
                    }
                    .onMove { source, destination in player.moveUpNext(from: source, to: destination) }
                    .onDelete { offsets in player.removeFromUpNext(at: offsets) }
                } header: {
                    HStack {
                        Text(upNext.isEmpty ? "Nothing up next" : "Up Next")
                        Spacer()
                        if !upNext.isEmpty {
                            Button("Clear") { confirmsClear = true }
                            Button(editMode.isEditing ? "Done" : "Edit") {
                                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                            }
                        }
                    }
                    .textCase(nil)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, $editMode)
            .accessibilityIdentifier("queueList")
            .onAppear { proxy.scrollTo(current, anchor: .top) }
            .confirmationDialog("Clear Up Next?", isPresented: $confirmsClear, titleVisibility: .visible) {
                Button("Clear \(upNext.count.counted("song"))", role: .destructive) { player.clearUpNext() }
            } message: {
                Text("The song that’s playing keeps going.")
            }
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .accessibilityLabel("\(entry.song.title), \(entry.song.artist ?? "")\(entry.isAutoplay ? ", autoplay" : "")")
        .accessibilityHint(isCurrent ? "" : "Plays this song")
        .id(index)
    }
}
