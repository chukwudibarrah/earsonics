// EarsonicsCore/PlayQueue.swift
import Foundation

// MARK: - Repeat Mode
public nonisolated enum RepeatMode: String, CaseIterable, Codable, Sendable {
    case off, one, all
    public var icon: String {
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
public nonisolated enum PlayContext: Codable, Hashable, Sendable {
    case album(id: String)
    case artist(id: String)
    case playlist(id: String)
    /// A genre's songs (Genres tab). When it runs out it carries on with
    /// more from the same genre; see `PlaybackPreferences.continuation(for:)`.
    case genre(name: String)
    /// Home shelves, Favourites, Tracks, Search results, and queues restored
    /// from another app (whose origin is unknown).
    case mix

    public nonisolated enum Group: String, Sendable {
        case albums
        case playlistsAndMixes
    }

    /// The genre of a genre mix.
    public var genreName: String? {
        if case .genre(let name) = self { return name }
        return nil
    }

    public var group: Group {
        switch self {
        case .album, .artist: return .albums
        case .playlist, .genre, .mix: return .playlistsAndMixes
        }
    }
}

// MARK: - Queue Entry
/// One slot in the queue. The same song can be queued more than once, so each
/// slot has its own id; anything that needs to find "this copy" of a song
/// (shuffle, removal, the Queue screen) uses the entry id, never the song id.
public nonisolated struct QueueEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let song: Song
    /// Added automatically when the queue ran out, rather than by the user.
    public let isAutoplay: Bool

    public init(song: Song, isAutoplay: Bool = false, id: UUID = UUID()) {
        self.id = id
        self.song = song
        self.isAutoplay = isAutoplay
    }
}

// MARK: - Play Queue
/// The play order and position, plus shuffle and repeat. A plain value with no
/// playback side effects, so its rules can be unit tested; `AudioPlayerService`
/// owns one and turns changes into player actions.
public nonisolated struct PlayQueue: Codable, Equatable, Sendable {
    public private(set) var entries: [QueueEntry] = []
    public private(set) var currentIndex: Int = 0
    public private(set) var isShuffled = false
    public private(set) var repeatMode: RepeatMode = .off
    public private(set) var context: PlayContext = .mix
    /// The order to return to when shuffle is turned off. Only kept up to date
    /// while shuffled.
    private var unshuffledEntries: [QueueEntry] = []

    public init() {}

    /// A queue restored as-is, e.g. from the server. Shuffle starts off: the
    /// saved order is already the order things play in.
    public init(entries: [QueueEntry], currentIndex: Int, repeatMode: RepeatMode = .off, context: PlayContext = .mix) {
        self.entries = entries
        self.currentIndex = entries.isEmpty ? 0 : min(max(currentIndex, 0), entries.count - 1)
        self.repeatMode = repeatMode
        self.context = context
    }

    // MARK: Reading

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }
    public var songs: [Song] { entries.map(\.song) }

    public var current: QueueEntry? {
        entries.indices.contains(currentIndex) ? entries[currentIndex] : nil
    }
    public var currentSong: Song? { current?.song }

    /// The slot that plays after the current one; Repeat All wraps to the
    /// start. Repeat One isn't considered here: it loops at the end of the
    /// track (see `AudioPlayerService`), but an explicit skip still moves on.
    public var nextIndex: Int? {
        guard !entries.isEmpty else { return nil }
        let next = currentIndex + 1
        if next < entries.count { return next }
        return repeatMode == .all ? 0 : nil
    }
    public var next: QueueEntry? { nextIndex.map { entries[$0] } }

    /// The slot a "previous" press goes to; Repeat All wraps to the end.
    public var previousIndex: Int? {
        guard !entries.isEmpty else { return nil }
        if currentIndex > 0 { return currentIndex - 1 }
        return repeatMode == .all ? entries.count - 1 : nil
    }

    /// True when something other than the current slot comes next. A failed
    /// track is only skipped when this holds, so a one-track Repeat All queue
    /// doesn't retry the same failing track forever.
    public var hasDifferentNext: Bool {
        guard let next = nextIndex else { return false }
        return next != currentIndex
    }

    /// True when the current slot is the last one and nothing follows it —
    /// the point where autoplay (if enabled) adds more.
    public var isAtEnd: Bool { !entries.isEmpty && nextIndex == nil }

    // MARK: Loading

    /// Replaces the queue. `shuffle: nil` keeps the current shuffle setting.
    /// When shuffled, the chosen start track plays first and the rest follow
    /// in random order. Returns false (leaving the queue untouched) for an
    /// empty list, so nothing that's playing is thrown away.
    @discardableResult
    public mutating func load(_ songs: [Song], startIndex: Int = 0, shuffle: Bool? = nil,
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
    public mutating func clear() {
        entries = []
        unshuffledEntries = []
        currentIndex = 0
        context = .mix
    }

    // MARK: Moving through the queue

    @discardableResult
    public mutating func moveToNext() -> Bool {
        guard let next = nextIndex else { return false }
        currentIndex = next
        return true
    }

    @discardableResult
    public mutating func moveToPrevious() -> Bool {
        guard let previous = previousIndex else { return false }
        currentIndex = previous
        return true
    }

    @discardableResult
    public mutating func jump(to index: Int) -> Bool {
        guard entries.indices.contains(index) else { return false }
        currentIndex = index
        return true
    }

    // MARK: Editing

    /// Adds songs the user queued. They go after the user's own upcoming songs
    /// but before any upcoming autoplay songs, so autoplay never delays them.
    public mutating func append(_ songs: [Song]) {
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
    public mutating func appendAutoplay(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        let added = songs.map { QueueEntry(song: $0, isAutoplay: true) }
        entries.append(contentsOf: added)
        if isShuffled { unshuffledEntries.append(contentsOf: added) }
    }

    /// Queues songs, in order, to play straight after the current one.
    ///
    /// `skippingIncoming` is for the first half of a crossfade: the incoming
    /// track is already committed as "next", so the songs go after it.
    public mutating func insertNext(_ songs: [Song], skippingIncoming: Bool = false) {
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

    public nonisolated enum RemovalOutcome: Equatable, Sendable {
        /// Nothing is left.
        case emptied
        /// The playing slot was removed; whatever slid into its place (or the
        /// new last slot) is now current and needs loading.
        case removedCurrent
        /// The current slot survived; only its index may have shifted.
        case keptCurrent
    }

    @discardableResult
    public mutating func remove(at offsets: IndexSet) -> RemovalOutcome {
        let valid = offsets.filteredIndexSet { $0 < entries.count }
        guard !valid.isEmpty else { return .keptCurrent }

        let removesCurrent = valid.contains(currentIndex)
        let removedBefore = valid.count(in: 0..<currentIndex)
        if isShuffled {
            let removedIDs = Set(valid.map { entries[$0].id })
            unshuffledEntries.removeAll { removedIDs.contains($0.id) }
        }
        entries.removeElements(atOffsets: valid)

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
    // MARK: Up Next
    // Screens show only the songs after the current one ("Up Next"), so
    // their positions start at 0 there. These convert to queue positions.

    /// Queue positions for positions in Up Next.
    public func entryOffsets(fromUpNext offsets: IndexSet) -> IndexSet {
        IndexSet(offsets.map { $0 + currentIndex + 1 }.filter { $0 < entries.count })
    }

    /// Moves songs within Up Next (positions as Up Next shows them).
    public mutating func moveUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        move(fromOffsets: entryOffsets(fromUpNext: source),
             toOffset: min(destination + currentIndex + 1, entries.count))
    }

    /// Moves the song at `index` (a queue position after the current song)
    /// so it plays next.
    public mutating func moveToPlayNext(entryAt index: Int) {
        guard index > currentIndex + 1, index < entries.count else { return }
        move(fromOffsets: [index], toOffset: currentIndex + 1)
    }

    /// Queue positions of everything after the current song.
    public var upNextOffsets: IndexSet {
        IndexSet(integersIn: min(currentIndex + 1, entries.count)..<entries.count)
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var positions = Array(entries.indices)
        positions.moveElements(fromOffsets: source, toOffset: destination)
        entries.moveElements(fromOffsets: source, toOffset: destination)
        if let newIndex = positions.firstIndex(of: currentIndex) { currentIndex = newIndex }
    }

    // MARK: Modes

    /// Turning shuffle on keeps the current song playing first, shuffles the
    /// user's songs behind it, and keeps any autoplay songs after those in
    /// their own order. Turning it off restores the unshuffled order (including
    /// any edits made meanwhile) and keeps the current song playing.
    public mutating func toggleShuffle() {
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

    public mutating func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    /// Restores a saved repeat mode (e.g. after a launch).
    public mutating func setRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
    }

    // MARK: Helpers

    private func firstUpcomingAutoplayIndex(in list: [QueueEntry], after index: Int) -> Int? {
        let start = index + 1
        guard start < list.count else { return nil }
        return list[start...].firstIndex(where: \.isAutoplay)
    }
}

// MARK: - Collection helpers
// The same behaviour as SwiftUI's `remove(atOffsets:)` and
// `move(fromOffsets:toOffset:)`, so the queue doesn't depend on SwiftUI.
nonisolated extension Array {
    /// Removes the elements at `offsets` (ignoring any out of range).
    public mutating func removeElements(atOffsets offsets: IndexSet) {
        for index in offsets.reversed() where indices.contains(index) {
            remove(at: index)
        }
    }

    /// Moves the elements at `source` to before the element that was at
    /// `destination`, keeping their order (as a list's drag-to-reorder does).
    public mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filteredIndexSet { indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { self[$0] }
        let movedBefore = valid.count(in: 0..<Swift.min(destination, count))
        removeElements(atOffsets: valid)
        let target = Swift.min(Swift.max(destination - movedBefore, 0), count)
        insert(contentsOf: moving, at: target)
    }
}
