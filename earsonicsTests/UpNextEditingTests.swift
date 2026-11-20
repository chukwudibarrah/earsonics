import Foundation
import Testing
@testable import earsonics
@testable import EarsonicsCore

/// Editing Up Next (the songs after the current one) by Up Next's own
/// positions, as the iPhone queue screen does.
@MainActor
@Suite("Up Next editing")
struct UpNextEditingTests {
    /// a b [c] d e f, playing c.
    private func queue() -> PlayQueue {
        var q = PlayQueue()
        q.load(makeSongs("a", "b", "c", "d", "e", "f"), startIndex: 2)
        return q
    }

    private func ids(_ q: PlayQueue) -> [String] { q.songs.map(\.id) }

    @Test func upNextPositionsMapPastTheCurrentSong() {
        let q = queue()
        #expect(q.entryOffsets(fromUpNext: [0, 2]) == [3, 5])
        #expect(q.entryOffsets(fromUpNext: [9]) == [], "out of range positions are dropped")
        #expect(q.upNextOffsets == IndexSet(3..<6))
    }

    @Test func removingFromUpNextKeepsTheCurrentSong() {
        var q = queue()
        _ = q.remove(at: q.entryOffsets(fromUpNext: [1]))   // e
        #expect(ids(q) == ["a", "b", "c", "d", "f"])
        #expect(q.currentSong?.id == "c")
    }

    @Test func movingWithinUpNext() {
        var q = queue()
        q.moveUpNext(fromOffsets: [2], toOffset: 0)          // f to the front of Up Next
        #expect(ids(q) == ["a", "b", "c", "f", "d", "e"])
        #expect(q.currentSong?.id == "c")
        q.moveUpNext(fromOffsets: [0], toOffset: 3)          // f to the end
        #expect(ids(q) == ["a", "b", "c", "d", "e", "f"])
        #expect(q.currentSong?.id == "c")
    }

    @Test func playNextMovesASongUpBehindTheCurrentOne() {
        var q = queue()
        q.moveToPlayNext(entryAt: 5)                         // f
        #expect(ids(q) == ["a", "b", "c", "f", "d", "e"])
        #expect(q.next?.song.id == "f")
        // Already next, or not in Up Next: nothing changes.
        q.moveToPlayNext(entryAt: 3)
        q.moveToPlayNext(entryAt: 1)
        #expect(ids(q) == ["a", "b", "c", "f", "d", "e"])
    }

    @Test func clearingUpNextLeavesHistoryAndTheCurrentSong() {
        var q = queue()
        _ = q.remove(at: q.upNextOffsets)
        #expect(ids(q) == ["a", "b", "c"])
        #expect(q.currentSong?.id == "c")
        #expect(q.upNextOffsets.isEmpty)
    }

    @Test func lastSongPlayingHasAnEmptyUpNext() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b"), startIndex: 1)
        #expect(q.upNextOffsets.isEmpty)
        #expect(q.entryOffsets(fromUpNext: [0]).isEmpty)
    }
}
