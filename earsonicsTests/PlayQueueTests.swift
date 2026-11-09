import Foundation
import Testing
@testable import earsonics

@MainActor
@Suite("PlayQueue")
struct PlayQueueTests {

    private func ids(_ queue: PlayQueue) -> [String] { queue.songs.map(\.id) }

    // MARK: Loading

    @Test func loadUnshuffledStartsAtTheChosenTrack() {
        var q = PlayQueue()
        let loaded = q.load(makeSongs("a", "b", "c"), startIndex: 1, context: .album(id: "x"))
        #expect(loaded)
        #expect(ids(q) == ["a", "b", "c"])
        #expect(q.currentIndex == 1)
        #expect(q.currentSong?.id == "b")
        #expect(q.context == .album(id: "x"))
        #expect(!q.isShuffled)
    }

    @Test func loadClampsTheStartIndex() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b"), startIndex: 9)
        #expect(q.currentIndex == 1)
        q.load(makeSongs("a", "b"), startIndex: -3)
        #expect(q.currentIndex == 0)
    }

    @Test func loadingAnEmptyListKeepsTheCurrentQueue() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b"), startIndex: 1)
        let loaded = q.load([], startIndex: 0)
        #expect(!loaded)
        #expect(ids(q) == ["a", "b"])
        #expect(q.currentIndex == 1)
    }

    @Test func loadShuffledPlaysTheChosenTrackFirst() {
        var q = PlayQueue()
        let songs = (0..<30).map { makeSong("s\($0)") }
        q.load(songs, startIndex: 7, shuffle: true)
        #expect(q.isShuffled)
        #expect(q.currentIndex == 0)
        #expect(q.currentSong?.id == "s7")
        #expect(Set(ids(q)) == Set(songs.map(\.id)))
        #expect(q.count == 30)
    }

    @Test func loadWithNilShuffleKeepsTheCurrentSetting() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b", "c"), shuffle: true)
        q.load(makeSongs("d", "e", "f"), startIndex: 2)
        #expect(q.isShuffled)
        #expect(q.currentSong?.id == "f")
        q.load(makeSongs("a", "b"), shuffle: false)
        #expect(!q.isShuffled)
    }

    @Test func clearKeepsShuffleAndRepeatPreferences() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b"), shuffle: true, context: .playlist(id: "p"))
        q.cycleRepeat()
        q.clear()
        #expect(q.isEmpty)
        #expect(q.isShuffled)
        #expect(q.repeatMode == .all)
        #expect(q.context == .mix)
    }

    // MARK: Next / previous

    @Test func nextAndPreviousFollowRepeatMode() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b", "c"), startIndex: 2)
        #expect(q.nextIndex == nil)
        #expect(q.isAtEnd)
        let moved = q.moveToNext()
        #expect(!moved)

        q.cycleRepeat()   // .all
        #expect(q.repeatMode == .all)
        #expect(q.nextIndex == 0)
        #expect(!q.isAtEnd)

        q.jump(to: 0)
        #expect(q.previousIndex == 2)
        q.cycleRepeat()   // .one — skips still move on
        #expect(q.repeatMode == .one)
        #expect(q.nextIndex == 1)
        #expect(q.previousIndex == nil)
        q.cycleRepeat()
        #expect(q.repeatMode == .off)
    }

    @Test func singleTrackRepeatAllHasNoDifferentNext() {
        var q = PlayQueue()
        q.load(makeSongs("a"))
        q.cycleRepeat()
        #expect(q.nextIndex == 0)
        #expect(!q.hasDifferentNext)
    }

    @Test func jumpRejectsOutOfRangeIndexes() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b"))
        let jumped = q.jump(to: 5)
        #expect(!jumped)
        #expect(q.currentIndex == 0)
    }

    // MARK: Editing

    @Test func insertNextKeepsTheSongsInOrderAfterTheCurrentTrack() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b", "c"), startIndex: 0)
        q.insertNext(makeSongs("x", "y", "z"))
        #expect(ids(q) == ["a", "x", "y", "z", "b", "c"])
        #expect(q.currentSong?.id == "a")
    }

    @Test func insertNextSkippingIncomingGoesAfterTheCrossfadingTrack() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b", "c"), startIndex: 0)
        q.insertNext(makeSongs("x"), skippingIncoming: true)
        #expect(ids(q) == ["a", "b", "x", "c"])
    }

    @Test func userSongsGoBeforeUpcomingAutoplaySongs() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b"), startIndex: 1)
        q.appendAutoplay(makeSongs("r1", "r2"))
        q.append(makeSongs("u"))
        #expect(ids(q) == ["a", "b", "u", "r1", "r2"])
        #expect(q.entries.map(\.isAutoplay) == [false, false, false, true, true])
    }

    @Test func userSongsGoToTheEndOnceAutoplayIsPlaying() {
        var q = PlayQueue()
        q.load(makeSongs("a"))
        q.appendAutoplay(makeSongs("r1", "r2"))
        q.jump(to: 2)   // playing the last autoplay song
        q.append(makeSongs("u"))
        #expect(ids(q) == ["a", "r1", "r2", "u"])
    }

    @Test func removingEarlierSongsShiftsTheCurrentIndex() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b", "c", "d"), startIndex: 2)
        let outcome = q.remove(at: [0, 3])
        #expect(outcome == .keptCurrent)
        #expect(ids(q) == ["b", "c"])
        #expect(q.currentSong?.id == "c")
    }

    @Test func removingTheCurrentSongPlaysTheOneThatSlidIntoPlace() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b", "c"), startIndex: 1)
        let outcome = q.remove(at: [1])
        #expect(outcome == .removedCurrent)
        #expect(q.currentSong?.id == "c")
    }

    @Test func removingTheCurrentLastSongFallsBackToTheNewLast() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b", "c"), startIndex: 2)
        let outcome = q.remove(at: [2])
        #expect(outcome == .removedCurrent)
        #expect(q.currentSong?.id == "b")
    }

    @Test func removingEverythingEmptiesTheQueue() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b"))
        let outcome = q.remove(at: [0, 1])
        #expect(outcome == .emptied)
        #expect(q.isEmpty)
        #expect(q.currentSong == nil)
    }

    @Test func outOfRangeRemovalIsIgnored() {
        var q = PlayQueue()
        q.load(makeSongs("a"))
        let outcome = q.remove(at: [4])
        #expect(outcome == .keptCurrent)
        #expect(q.count == 1)
    }

    @Test func movingKeepsTheCurrentSongPlaying() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b", "c", "d"), startIndex: 1)
        q.move(fromOffsets: [1], toOffset: 4)      // move the current song to the end
        #expect(ids(q) == ["a", "c", "d", "b"])
        #expect(q.currentSong?.id == "b")
        q.move(fromOffsets: [0], toOffset: 4)      // move a song from before it to after it
        #expect(ids(q) == ["c", "d", "b", "a"])
        #expect(q.currentSong?.id == "b")
    }

    // MARK: Shuffle

    @Test func shuffleOffRestoresTheOriginalOrderAndPosition() {
        var q = PlayQueue()
        let songs = (0..<20).map { makeSong("s\($0)") }
        q.load(songs, startIndex: 5)
        q.toggleShuffle()
        #expect(q.currentSong?.id == "s5")
        #expect(q.currentIndex == 0)
        q.moveToNext()
        let playing = q.current
        q.toggleShuffle()
        #expect(ids(q) == songs.map(\.id))
        #expect(q.current == playing)
    }

    /// Regression: shuffle used to drop every duplicate of the playing song,
    /// because it removed "the current song" by song id.
    @Test func shuffleKeepsDuplicatesOfThePlayingSong() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b", "a", "c", "a"), startIndex: 0)
        q.toggleShuffle()
        #expect(q.count == 5)
        #expect(ids(q).filter { $0 == "a" }.count == 3)
    }

    /// Regression: turning shuffle off matched the playing song by song id, so
    /// with duplicates it could jump to the wrong copy.
    @Test func shuffleOffReturnsToTheCorrectCopyOfADuplicate() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b", "a"), startIndex: 2, shuffle: true)
        let playing = q.current
        q.toggleShuffle()
        #expect(ids(q) == ["a", "b", "a"])
        #expect(q.currentIndex == 2)
        #expect(q.current == playing)
    }

    @Test func editsWhileShuffledSurviveTurningShuffleOff() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b", "c"), startIndex: 0, shuffle: true)
        q.insertNext(makeSongs("n"))
        q.append(makeSongs("z"))
        let removeIndex = q.entries.firstIndex { $0.song.id == "b" }!
        q.remove(at: [removeIndex])
        q.toggleShuffle()
        // "n" goes straight after the song that was playing when it was
        // queued; "z" goes to the end; "b" stays removed.
        #expect(ids(q) == ["a", "n", "c", "z"])
        #expect(q.currentSong?.id == "a")
    }

    @Test func removingADuplicateWhileShuffledRemovesOnlyThatCopy() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b", "b", "c"), startIndex: 0, shuffle: true)
        let index = q.entries.firstIndex { $0.song.id == "b" }!
        q.remove(at: [index])
        q.toggleShuffle()
        #expect(ids(q) == ["a", "b", "c"])
    }

    @Test func shuffleKeepsAutoplaySongsAfterTheUsersSongs() {
        var q = PlayQueue()
        q.load(makeSongs("a", "b", "c", "d"))
        q.appendAutoplay(makeSongs("r1", "r2"))
        q.toggleShuffle()
        #expect(q.currentSong?.id == "a")
        #expect(Array(ids(q).suffix(2)) == ["r1", "r2"])
        #expect(Set(ids(q)[1...3]) == ["b", "c", "d"])
    }

    @Test func shufflingAnEmptyQueueIsHarmless() {
        var q = PlayQueue()
        q.toggleShuffle()
        #expect(q.isShuffled)
        #expect(q.isEmpty)
        q.toggleShuffle()
        #expect(!q.isShuffled)
    }

    // MARK: Persistence

    @Test func roundTripsThroughCodable() throws {
        var q = PlayQueue()
        q.load(makeSongs("a", "b", "a", "c"), startIndex: 2, shuffle: true, context: .playlist(id: "p1"))
        q.appendAutoplay(makeSongs("r"))
        q.cycleRepeat()
        let data = try JSONEncoder().encode(q)
        var decoded = try JSONDecoder().decode(PlayQueue.self, from: data)
        #expect(decoded == q)
        // The hidden unshuffled order survives too.
        decoded.toggleShuffle()
        q.toggleShuffle()
        #expect(decoded == q)
    }

    @Test func restoringInitClampsTheIndex() {
        let entries = makeSongs("a", "b").map { QueueEntry(song: $0) }
        #expect(PlayQueue(entries: entries, currentIndex: 7).currentIndex == 1)
        #expect(PlayQueue(entries: entries, currentIndex: -1).currentIndex == 0)
        #expect(PlayQueue(entries: [], currentIndex: 3).currentIndex == 0)
    }

    @Test func contextGroups() {
        #expect(PlayContext.album(id: "1").group == .albums)
        #expect(PlayContext.artist(id: "1").group == .albums)
        #expect(PlayContext.playlist(id: "1").group == .playlistsAndMixes)
        #expect(PlayContext.mix.group == .playlistsAndMixes)
    }
}
