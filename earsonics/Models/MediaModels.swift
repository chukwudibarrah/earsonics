// Models/MediaModels.swift
import Foundation

// MARK: - Artist
struct Artist: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let albumCount: Int?
    let coverArt: String?
    var starred: Date?
}

// MARK: - Album
struct Album: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let songCount: Int?
    let duration: Int?
    let year: Int?
    let genre: String?
    var starred: Date?
    var songs: [Song]?
}

// MARK: - Song
struct Song: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let album: String?
    let albumId: String?
    let artist: String?
    let artistId: String?
    let track: Int?
    let year: Int?
    let genre: String?
    let coverArt: String?
    let size: Int?
    let contentType: String?
    let suffix: String?
    let duration: Int?
    let bitRate: Int?
    let path: String?
    var starred: Date?

    var durationFormatted: String {
        guard let d = duration else { return "--:--" }
        let m = d / 60; let s = d % 60
        return String(format: "%d:%02d", m, s)
    }

    var isLossless: Bool {
        guard let s = suffix?.lowercased() else { return false }
        return ["flac", "alac", "wav", "aiff", "aif", "ape", "dsf", "dff"].contains(s)
    }
}

// MARK: - Playlist
struct Playlist: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var comment: String?
    let owner: String?
    let songCount: Int?
    let duration: Int?
    let coverArt: String?
    var songs: [Song]?
    let created: Date?
    let changed: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, comment, owner, songCount, duration, coverArt, songs, created, changed
    }
}

// MARK: - Lyrics
struct Lyrics: Codable {
    let artist: String?
    let title: String?
    let value: String?
}

// MARK: - Structured Lyrics (LRC / word-by-word)
struct StructuredLyrics: Codable {
    struct Line: Codable, Identifiable {
        var id: Int { start ?? 0 }
        let start: Int?  // milliseconds
        let value: String
    }
    let displayArtist: String?
    let displayTitle: String?
    let lang: String?
    let lines: [Line]?
    let synced: Bool?
}

// MARK: - Genre
struct Genre: Identifiable, Codable, Hashable {
    var id: String { value }
    let value: String
    let songCount: Int?
    let albumCount: Int?

    enum CodingKeys: String, CodingKey {
        case value, songCount, albumCount
    }
}

// MARK: - MusicIndex (browse by tag)
struct IndexEntry: Identifiable, Codable, Hashable {
    var id: String { name }
    let name: String
    let artist: [Artist]?
}

// MARK: - Search Results
struct SearchResult {
    var artists: [Artist]
    var albums: [Album]
    var songs: [Song]
}

// MARK: - Bookmark
struct Bookmark: Codable {
    let position: Int   // ms
    let username: String?
    let comment: String?
    let created: Date?
    let changed: Date?
    let entry: Song?
}
