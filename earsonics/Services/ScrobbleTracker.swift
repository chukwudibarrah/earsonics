// Services/ScrobbleTracker.swift
import Foundation

/// Decides when one play of a track counts as "played" on the server,
/// following the usual scrobbling rule (Last.fm's, which Navidrome and most
/// Subsonic clients follow): the track is longer than 30 seconds, and it's
/// been listened to for half its length or four minutes, whichever comes
/// first.
///
/// Only continuous listening counts. Seeking ahead doesn't, so skipping to the
/// end of a track isn't a play; seeking back and listening again does count
/// towards the threshold, but a single play is only ever submitted once.
struct ScrobbleTracker {
    /// The queue slot being listened to (one tracker per play of a slot).
    let entryID: UUID
    let songID: String
    /// When this play started; sent with the submission so the server
    /// records the play at the right time.
    let startedAt: Date
    private(set) var duration: Double
    private(set) var listened: Double = 0
    private(set) var submitted = false
    private var lastPosition: Double?

    static let minimumTrackLength: Double = 30
    static let maximumThreshold: Double = 240
    /// The player reports its position every half second; anything larger
    /// than this between two reports is a seek (or a stall), not listening.
    static let maximumTickGap: Double = 2

    init(entryID: UUID, songID: String, duration: Double?, startedAt: Date = Date()) {
        self.entryID = entryID
        self.songID = songID
        self.duration = duration ?? 0
        self.startedAt = startedAt
    }

    var isEligible: Bool { duration > Self.minimumTrackLength }
    var threshold: Double { min(duration / 2, Self.maximumThreshold) }

    /// The server's metadata can lack a duration; the player learns the real
    /// one once the track loads.
    mutating func updateDuration(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        duration = seconds
    }

    /// Records a playback position. Returns true exactly once per play: when
    /// listening first crosses the threshold.
    mutating func record(position: Double) -> Bool {
        guard position.isFinite else { return false }
        defer { lastPosition = position }
        guard let last = lastPosition else { return false }
        let delta = position - last
        guard delta > 0, delta <= Self.maximumTickGap else { return false }
        listened += delta
        guard !submitted, isEligible, listened >= threshold else { return false }
        submitted = true
        return true
    }
}
