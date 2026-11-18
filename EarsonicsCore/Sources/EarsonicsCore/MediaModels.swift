// EarsonicsCore/MediaModels.swift
import Foundation

// MARK: - Artist
public nonisolated struct Artist: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let albumCount: Int?
    public let coverArt: String?
    public var starred: Date?
}

// MARK: - Album
public nonisolated struct Album: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let artist: String?
    public let artistId: String?
    public let coverArt: String?
    public let songCount: Int?
    public let duration: Int?
    public let year: Int?
    public let genre: String?
    public var starred: Date?
    public var songs: [Song]?
}

// MARK: - Song
public nonisolated struct Song: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let album: String?
    public let albumId: String?
    public let artist: String?
    public let artistId: String?
    public let track: Int?
    public let discNumber: Int?
    public let year: Int?
    public let genre: String?
    public let coverArt: String?
    public let size: Int?
    public let contentType: String?
    public let suffix: String?
    public let duration: Int?
    public let bitRate: Int?
    public let path: String?
    public let replayGain: ReplayGainData?
    public var starred: Date?

    public var durationFormatted: String {
        guard let d = duration else { return "--:--" }
        let m = d / 60; let s = d % 60
        return String(format: "%d:%02d", m, s)
    }

    public var isLossless: Bool {
        guard let s = suffix?.lowercased() else { return false }
        return ["flac", "alac", "wav", "aiff", "aif", "ape", "dsf", "dff"].contains(s)
    }
}

// MARK: - ReplayGain
public nonisolated struct ReplayGainData: Codable, Hashable, Sendable {
    public let trackGain: Double?
    public let trackPeak: Double?
    public let albumGain: Double?
    public let albumPeak: Double?
}

// MARK: - Playlist
public nonisolated struct Playlist: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var comment: String?
    public let owner: String?
    public let songCount: Int?
    public let duration: Int?
    public let coverArt: String?
    public var songs: [Song]?
    public let created: Date?
    public let changed: Date?

    public nonisolated enum CodingKeys: String, CodingKey, Sendable {
        case id, name, comment, owner, songCount, duration, coverArt, songs = "entry", created, changed
    }
}

// MARK: - Lyrics
public nonisolated struct Lyrics: Codable, Sendable {
    public let artist: String?
    public let title: String?
    public let value: String?
}

// MARK: - Structured Lyrics (LRC / word-by-word)
public nonisolated struct StructuredLyrics: Codable, Sendable {
    public nonisolated struct Line: Codable, Identifiable, Sendable {
        public var id: Int { start ?? 0 }
        public let start: Int?  // milliseconds
        public let value: String
    }
    public let displayArtist: String?
    public let displayTitle: String?
    public let lang: String?
    public let lines: [Line]?
    public let synced: Bool?
}

// MARK: - Genre
public nonisolated struct Genre: Identifiable, Codable, Hashable, Sendable {
    public var id: String { value }
    public let value: String
    public let songCount: Int?
    public let albumCount: Int?

    public nonisolated enum CodingKeys: String, CodingKey, Sendable {
        case value, songCount, albumCount
    }
}

// MARK: - MusicIndex (browse by tag)
public nonisolated struct IndexEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let artist: [Artist]?
}

// MARK: - Search Results
public nonisolated struct SearchResult: Sendable {
    public var artists: [Artist]
    public var albums: [Album]
    public var songs: [Song]

    public init(artists: [Artist], albums: [Album], songs: [Song]) {
        self.artists = artists
        self.albums = albums
        self.songs = songs
    }
}

// MARK: - Bookmark
public nonisolated struct Bookmark: Codable, Sendable {
    public let position: Int   // ms
    public let username: String?
    public let comment: String?
    public let created: Date?
    public let changed: Date?
    public let entry: Song?
}
