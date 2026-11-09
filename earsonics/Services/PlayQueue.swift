// Services/PlayQueue.swift
import Foundation
import SwiftUI   // `move(fromOffsets:toOffset:)` / `remove(atOffsets:)` on collections

// MARK: - Repeat Mode
enum RepeatMode: String, CaseIterable, Codable {
    case off, one, all
    var icon: String {
        switch self {
        case .off: return "repeat"
        case .one: return "repeat.1"
        case .all: return "repeat"
        }
    }
}

// MARK: - Play Context
/// Where a queue came from. Decides what happens when it runs out (see
/// `QueueContinuation`): albums and artists can stop while playlists and
/// mixes carry on, or the other way round, as the user prefers.
enum PlayContext: Codable, Hashable {
    case album(id: String)
    case artist(id: String)
    case playlist(id: String)
    /// Home shelves, Favourites, Tracks, Search results, and queues restored
    /// from another app (whose origin is unknown).
    case mix

    enum Group: String {
        case albums
        case playlistsAndMixes
    }

    var group: Group {
        switch self {
        case .album, .artist: return .albums
        case .playlist, .mix: return .playlistsAndMixes
        }
    }
}

// MARK: - Queue Entry
/// One slot in the queue. The same song can be queued more than once, so each
/// slot has its own id; anything that needs to find "this copy" of a song
/// (shuffle, removal, the Queue screen) uses the entry id, never the song id.
struct QueueEntry: Identifiable, Hashable, Codable {
    let id: UUID
    let song: Song
    /// Added automatically when the queue ran out, rather than by the user.
    let isAutoplay: Bool

    init(song: Song, isAutoplay: Bool = false, id: UUID = UUID()) {
        self.id = id
        self.song = song
        self.isAutoplay = isAutoplay
    }
}

// MARK: - Play Queue
/// The play order and position, plus shuffle and repeat. A plain value with no
/// playback side effects, so its rules can be unit tested; `AudioPlayerService`
/// owns one and turns changes into player actions.
struct PlayQueue: Codable, Equatable {
    private(set) var entries: [QueueEntry] = []
    private(set) var currentIndex: Int = 0
    private(set) var isShuffled = false
    private(set) var repeatMode: RepeatMode = .off
    private(set) var context: PlayContext = .mix
    /// The order to return to when shuffle is turned off. Only kept up to date
    /// while shuffled.
    private var unshuffledEntries: [QueueEntry] = []

    init() {}

    /// A queue restored as-is, e.g. from the server. Shuffle starts off: the
    /// saved order is already the order things play in.
    init(entries: [QueueEntry], currentIndex: Int, repeatMode: RepeatMode = .off, context: PlayContext = .mix) {
        self.entries = entries
        self.currentIndex = entries.isEmpty ? 0 : min(max(currentIndex, 0), entries.count - 1)
        self.repeatMode = repeatMode
        self.context = context
    }

    // MARK: Reading

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }
    var songs: [Song] { entries.map(\.song) }

    var current: QueueEntry? {
        entries.indices.contains(currentIndex) ? entries[currentIndex] : nil
    }
    var currentSong: Song? { current?.song }

    /// The slot that plays after the current one; Repeat All wraps to the
    /// start. Repeat One isn't considered here: it loops at the end of the
    /// track (see `AudioPlayerService`), but an explicit skip still moves on.
    var nextIndex: Int? {
        guard !entries.isEmpty else { return nil }
        let next = currentIndex + 1
        if next < entries.count { return next }
        return repeatMode == .all ? 0 : nil
    }
    var next: QueueEntry? { nextIndex.map { entries[$0] } }

    /// The slot a "previous" press goes to; Repeat All wraps to the end.
    var previousIndex: Int? {
        guard !entries.isEmpty else { return nil }
        if currentIndex > 0 { return currentIndex - 1 }
        return repeatMode == .all ? entries.count - 1 : nil
    }

    /// True when something other than the current slot comes next. A failed
    /// track is only skipped when this holds, so a one-track Repeat All queue
    /// doesn't retry the same failing track forever.
    var hasDifferentNext: Bool {
        guard let next = nextIndex else { return false }
        return next != currentIndex
    }

    /// True when the current slot is the last one and nothing follows it —
    /// the point where autoplay (if enabled) adds more.
    var isAtEnd: Bool { !entries.isEmpty && nextIndex == nil }

    // MARK: Loading

    /// Replaces the queue. `shuffle: nil` keeps the current shuffle setting.
    /// When shuffled, the chosen start track plays first and the rest follow
    /// in random order. Returns false (leaving the queue untouched) for an
    /// empty list, so nothing that's playing is thrown away.
    @discardableResult
    mutating func load(_ songs: [Song], startIndex: Int = 0, shuffle: Bool? = nil,
                       context: PlayContext = .mix) -> Bool {
        guard !songs.isEmpty else { return false }
        let start = min(max(startIndex, 0), songs.count - 1)
        let loaded = songs.map { QueueEntry(song: $0) }
        self.context = context
        isShuffled = shuffle ?? isShuffled
        if isShuffled {
            unshuffledEntries = loaded
            var rest = loaded
            let first = rest.remove(at: start)
            rest.shuffle()
            entries = [first] + rest
            currentIndex = 0
        } else {
            unshuffledEntries = []
            entries = loaded
            currentIndex = start
        }
        return true
    }

    /// Empties the queue. Shuffle and repeat are preferences, so they stay.
    mutating func clear() {
        entries = []
        unshuffledEntries = []
        currentIndex = 0
        context = .mix
    }

    // MARK: Moving through the queue

    @discardableResult
    mutating func moveToNext() -> Bool {
        guard let next = nextIndex else { return false }
        currentIndex = next
        return true
    }

    @discardableResult
    mutating func moveToPrevious() -> Bool {
        guard let previous = previousIndex else { return false }
        currentIndex = previous
        return true
    }

    @discardableResult
    mutating func jump(to index: Int) -> Bool {
        guard entries.indices.contains(index) else { return false }
        currentIndex = index
        return true
    }

    // MARK: Editing

    /// Adds songs the user queued. They go after the user's own upcoming songs
    /// but before any upcoming autoplay songs, so autoplay never delays them.
    mutating func append(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        let added = songs.map { QueueEntry(song: $0) }
        entries.insert(contentsOf: added, at: firstUpcomingAutoplayIndex(in: entries, after: currentIndex) ?? entries.count)
        if isShuffled {
            let anchor = current.flatMap { c in unshuffledEntries.firstIndex { $0.id == c.id } } ?? -1
            unshuffledEntries.insert(contentsOf: added,
                                     at: firstUpcomingAutoplayIndex(in: unshuffledEntries, after: anchor) ?? unshuffledEntries.count)
        }
    }

    /// Adds songs fetched by autoplay at the very end.
    mutating func appendAutoplay(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        let added = songs.map { QueueEntry(song: $0, isAutoplay: true) }
        entries.append(contentsOf: added)
        if isShuffled { unshuffledEntries.append(contentsOf: added) }
    }

    /// Queues songs, in order, to play straight after the current one.
    ///
    /// `skippingIncoming` is for the first half of a crossfade: the incoming
    /// track is already committed as "next", so the songs go after it.
    mutating func insertNext(_ songs: [Song], skippingIncoming: Bool = false) {
        guard !songs.isEmpty else { return }
        let added = songs.map { QueueEntry(song: $0) }
        let anchorEntry = skippingIncoming ? next : current
        let position = min(currentIndex + (skippingIncoming ? 2 : 1), entries.count)
        entries.insert(contentsOf: added, at: position)
        if isShuffled {
            let anchor = anchorEntry.flatMap { a in unshuffledEntries.firstIndex { $0.id == a.id } }
            unshuffledEntries.insert(contentsOf: added, at: anchor.map { $0 + 1 } ?? unshuffledEntries.count)
        }
    }

    enum RemovalOutcome: Equatable {
        /// Nothing is left.
        case emptied
        /// The playing slot was removed; whatever slid into its place (or the
        /// new last slot) is now current and needs loading.
        case removedCurrent
        /// The current slot survived; only its index may have shifted.
        case keptCurrent
    }

    @discardableResult
    mutating func remove(at offsets: IndexSet) -> RemovalOutcome {
        let valid = offsets.filteredIndexSet { $0 < entries.count }
        guard !valid.isEmpty else { return .keptCurrent }

        let removesCurrent = valid.contains(currentIndex)
        let removedBefore = valid.count(in: 0..<currentIndex)
        if isShuffled {
            let removedIDs = Set(valid.map { entries[$0].id })
            unshuffledEntries.removeAll { removedIDs.contains($0.id) }
        }
        entries.remove(atOffsets: valid)

        if entries.isEmpty {
            clear()
            return .emptied
        }
        if removesCurrent {
            currentIndex = min(currentIndex - removedBefore, entries.count - 1)
            return .removedCurrent
        }
        currentIndex -= removedBefore
        return .keptCurrent
    }

    /// Moves slots; the current slot keeps playing at its new index.
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var positions = Array(entries.indices)
        positions.move(fromOffsets: source, toOffset: destination)
        entries.move(fromOffsets: source, toOffset: destination)
        if let newIndex = positions.firstIndex(of: currentIndex) { currentIndex = newIndex }
    }

    // MARK: Modes

    /// Turning shuffle on keeps the current song playing first, shuffles the
    /// user's songs behind it, and keeps any autoplay songs after those in
    /// their own order. Turning it off restores the unshuffled order (including
    /// any edits made meanwhile) and keeps the current song playing.
    mutating func toggleShuffle() {
        if isShuffled {
            isShuffled = false
            let currentID = current?.id
            entries = unshuffledEntries
            unshuffledEntries = []
            currentIndex = currentID.flatMap { id in entries.firstIndex { $0.id == id } } ?? 0
        } else {
            isShuffled = true
            unshuffledEntries = entries
            guard let playing = current else { return }
            var rest = entries
            rest.remove(at: currentIndex)
            var user = rest.filter { !$0.isAutoplay }
            user.shuffle()
            entries = [playing] + user + rest.filter(\.isAutoplay)
            currentIndex = 0
        }
    }

    mutating func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    /// Restores a saved repeat mode (e.g. after a launch).
    mutating func setRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
    }

    // MARK: Helpers

    private func firstUpcomingAutoplayIndex(in list: [QueueEntry], after index: Int) -> Int? {
        let start = index + 1
        guard start < list.count else { return nil }
        return list[start...].firstIndex(where: \.isAutoplay)
    }
}
