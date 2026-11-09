//
//  earsonicsTests.swift
//  earsonicsTests
//
//  Shared helpers for the unit tests. The suites themselves live in the
//  other files in this target.
//

import Foundation
@testable import earsonics

/// A minimal song for tests; only the id and title matter to the queue.
func makeSong(_ id: String, duration: Int? = 200, artistId: String? = nil, genre: String? = nil) -> Song {
    Song(id: id, title: "Song \(id)", album: nil, albumId: nil, artist: nil, artistId: artistId,
         track: nil, discNumber: nil, year: nil, genre: genre, coverArt: nil, size: nil,
         contentType: nil, suffix: nil, duration: duration, bitRate: nil, path: nil,
         replayGain: nil)
}

func makeSongs(_ ids: String...) -> [Song] {
    ids.map { makeSong($0) }
}
