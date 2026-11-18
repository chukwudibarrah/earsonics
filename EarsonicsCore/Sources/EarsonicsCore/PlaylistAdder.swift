// EarsonicsCore/PlaylistAdder.swift
import Foundation
import Observation

/// Adds songs to playlists from anywhere in the app. Before adding, it checks
/// which songs the playlist already holds and asks for confirmation instead of
/// silently creating duplicates; afterwards it reports the outcome in a brief
/// banner (`Messages`). The confirmation alert and the banner are presented once, at the
/// app root (`ContentView`), so every "Add to playlist" entry point behaves
/// the same way.
@MainActor
@Observable
public final class PlaylistAdder {
    public static let shared = PlaylistAdder()

    /// An add waiting for confirmation because some (or all) of its songs are
    /// already in the playlist.
    public struct PendingAdd: Identifiable, Sendable {
        public let id = UUID()
        public let playlist: Playlist
        public let songIDs: [String]
        public let newSongIDs: [String]

        public var duplicateCount: Int { songIDs.count - newSongIDs.count }

        public var title: String {
            newSongIDs.isEmpty ? "Already in Playlist" : "Some Songs Already Added"
        }

        public var message: String {
            let name = "“\(playlist.name)”"
            if songIDs.count == 1 { return "This song is already in \(name)." }
            if newSongIDs.isEmpty { return "All \(songIDs.count) songs are already in \(name)." }
            return "\(duplicateCount) of \(songIDs.count) songs are already in \(name)."
        }
    }

    public var pending: PendingAdd?

    /// Adds songs, asking first if any are already in the playlist.
    public func add(songIDs: [String], to playlist: Playlist) async {
        guard !songIDs.isEmpty else { return }
        let existing: Set<String>
        do {
            let current = try await SubsonicClient.shared.getPlaylist(id: playlist.id)
            existing = Set(current.songs?.map(\.id) ?? [])
        } catch {
            showBanner("Couldn’t add to “\(playlist.name)”. \(error.localizedDescription)")
            return
        }
        let newIDs = songIDs.filter { !existing.contains($0) }
        if newIDs.count == songIDs.count {
            await commit(songIDs, to: playlist)
        } else {
            pending = PendingAdd(playlist: playlist, songIDs: songIDs, newSongIDs: newIDs)
        }
    }

    /// Adds a whole album. Album-list results don't include tracks, so the
    /// album is fetched first.
    public func addAlbum(id: String, to playlist: Playlist) async {
        do {
            let songs = try await SubsonicClient.shared.getAlbum(id: id).songs ?? []
            await add(songIDs: songs.map(\.id), to: playlist)
        } catch {
            showBanner("Couldn’t add to “\(playlist.name)”. \(error.localizedDescription)")
        }
    }

    /// Resolves a pending confirmation.
    public func confirm(_ add: PendingAdd, includeDuplicates: Bool) {
        pending = nil
        Task { await commit(includeDuplicates ? add.songIDs : add.newSongIDs, to: add.playlist) }
    }

    /// Creates a playlist containing `songIDs` and reports the outcome.
    public func create(name: String, songIDs: [String]) async -> Playlist? {
        do {
            let playlist = try await SubsonicClient.shared.createPlaylist(name: name, songIds: songIDs)
            showBanner("Created “\(name)”")
            await LibraryStore.shared.loadPlaylists(force: true)
            return playlist
        } catch {
            showBanner("Couldn’t create “\(name)”. \(error.localizedDescription)")
            return nil
        }
    }

    private func commit(_ songIDs: [String], to playlist: Playlist) async {
        guard !songIDs.isEmpty else { return }
        do {
            try await SubsonicClient.shared.updatePlaylist(id: playlist.id, songIdsToAdd: songIDs)
            Task { await LibraryStore.shared.loadPlaylists(force: true) }   // song counts changed
            showBanner(songIDs.count == 1
                       ? "Added to “\(playlist.name)”"
                       : "Added \(songIDs.count) songs to “\(playlist.name)”")
        } catch {
            showBanner("Couldn’t add to “\(playlist.name)”. \(error.localizedDescription)")
        }
    }

    private func showBanner(_ message: String) {
        Messages.shared.show(message)
    }
}
