import Foundation
import Testing
@testable import earsonics

@Suite("ScrobbleTracker")
struct ScrobbleTrackerTests {

    /// Feeds positions at the player's half-second tick rate from `from` to
    /// `to`; returns how many times the tracker reported crossing.
    private func play(_ tracker: inout ScrobbleTracker, from: Double, to: Double, step: Double = 0.5) -> Int {
        var crossings = 0
        var position = from
        while position <= to + 0.0001 {
            if tracker.record(position: position) { crossings += 1 }
            position += step
        }
        return crossings
    }

    private func tracker(duration: Double?) -> ScrobbleTracker {
        ScrobbleTracker(entryID: UUID(), songID: "s", duration: duration)
    }

    @Test func halfOfAShortTrackCounts() {
        var t = tracker(duration: 200)
        #expect(t.threshold == 100)
        let r1 = play(&t, from: 0, to: 99)
        #expect(r1 == 0)
        let r2 = play(&t, from: 99.5, to: 101)
        #expect(r2 == 1)
        #expect(t.submitted)
    }

    @Test func fourMinutesOfALongTrackCounts() {
        var t = tracker(duration: 1200)
        #expect(t.threshold == 240)
        let r3 = play(&t, from: 0, to: 239)
        #expect(r3 == 0)
        let r4 = play(&t, from: 239.5, to: 245)
        #expect(r4 == 1)
    }

    @Test func submitsOnlyOncePerPlay() {
        var t = tracker(duration: 100)
        let r5 = play(&t, from: 0, to: 100)
        #expect(r5 == 1)
        // Seeking back and listening again doesn't submit a second time.
        let r6 = play(&t, from: 0, to: 100)
        #expect(r6 == 0)
    }

    @Test func seekingAheadDoesNotCountAsListening() {
        var t = tracker(duration: 200)
        _ = play(&t, from: 0, to: 10)
        // Jump to near the end, as if the user scrubbed forward.
        let r7 = t.record(position: 190)
        #expect(!r7)
        let r8 = play(&t, from: 190.5, to: 200)
        #expect(r8 == 0)
        #expect(t.listened < 25)
        #expect(!t.submitted)
    }

    @Test func skippingEarlyNeverSubmits() {
        var t = tracker(duration: 200)
        let r9 = play(&t, from: 0, to: 2)
        #expect(r9 == 0)
        #expect(!t.submitted)
    }

    @Test func listeningAcrossASeekBackStillAddsUp() {
        var t = tracker(duration: 200)
        _ = play(&t, from: 0, to: 60)
        _ = t.record(position: 10)            // seek back
        let r10 = play(&t, from: 10.5, to: 51)   // 60s + ~40s heard
        #expect(r10 == 1)
    }

    @Test func tracksOf30SecondsOrLessNeverCount() {
        var t = tracker(duration: 30)
        #expect(!t.isEligible)
        let r11 = play(&t, from: 0, to: 30)
        #expect(r11 == 0)
    }

    @Test func unknownDurationWaitsForThePlayersDuration() {
        var t = tracker(duration: nil)
        #expect(!t.isEligible)
        let r12 = play(&t, from: 0, to: 50)
        #expect(r12 == 0)
        t.updateDuration(100)
        #expect(t.isEligible)
        // Already heard 50s of a 100s track: the next tick crosses.
        let r13 = t.record(position: 50.5)
        #expect(r13)
    }

    @Test func invalidPositionsAreIgnored() {
        var t = tracker(duration: 100)
        let r14 = t.record(position: .nan)
        #expect(!r14)
        let r15 = t.record(position: .infinity)
        #expect(!r15)
        t.updateDuration(.nan)
        #expect(t.duration == 100)
    }
}
