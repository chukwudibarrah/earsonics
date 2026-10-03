// Services/PlaylistAdder.swift
import SwiftUI
import Combine

/// Adds songs to playlists from anywhere in the app. Before adding, it checks
/// which songs the playlist already holds and asks for confirmation instead of
/// silently creating duplicates; afterwards it reports the outcome in a brief
/// banner. The confirmation alert and the banner are presented once, at the
/// app root (`ContentView`), so every "Add to playlist" entry point behaves
/// the same way.
@MainActor
final class PlaylistAdder: ObservableObject {
    static let shared = PlaylistAdder()

    /// An add waiting for confirmation because some (or all) of its songs are
    /// already in the playlist.
    struct PendingAdd: Identifiable {
        let id = UUID()
        let playlist: Playlist
        let songIDs: [String]
        let newSongIDs: [String]

        var duplicateCount: Int { songIDs.count - newSongIDs.count }

        var title: String {
            newSongIDs.isEmpty ? "Already in Playlist" : "Some Songs Already Added"
        }

        var message: String {
            let name = "“\(playlist.name)”"
            if songIDs.count == 1 { return "This song is already in \(name)." }
            if newSongIDs.isEmpty { return "All \(songIDs.count) songs are already in \(name)." }
            return "\(duplicateCount) of \(songIDs.count) songs are already in \(name)."
        }
    }

    @Published var pending: PendingAdd?
    @Published private(set) var banner: String?
    private var bannerTask: Task<Void, Never>?

    /// Adds songs, asking first if any are already in the playlist.
    func add(songIDs: [String], to playlist: Playlist) async {
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
    func addAlbum(id: String, to playlist: Playlist) async {
        do {
            let songs = try await SubsonicClient.shared.getAlbum(id: id).songs ?? []
            await add(songIDs: songs.map(\.id), to: playlist)
        } catch {
            showBanner("Couldn’t add to “\(playlist.name)”. \(error.localizedDescription)")
        }
    }

    /// Resolves a pending confirmation.
    func confirm(_ add: PendingAdd, includeDuplicates: Bool) {
        pending = nil
        Task { await commit(includeDuplicates ? add.songIDs : add.newSongIDs, to: add.playlist) }
    }

    /// Creates a playlist containing `songIDs` and reports the outcome.
    func create(name: String, songIDs: [String]) async -> Playlist? {
        do {
            let playlist = try await SubsonicClient.shared.createPlaylist(name: name, songIds: songIDs)
            showBanner("Created “\(name)”")
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
            showBanner(songIDs.count == 1
                       ? "Added to “\(playlist.name)”"
                       : "Added \(songIDs.count) songs to “\(playlist.name)”")
        } catch {
            showBanner("Couldn’t add to “\(playlist.name)”. \(error.localizedDescription)")
        }
    }

    private func showBanner(_ message: String) {
        bannerTask?.cancel()
        banner = message
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            banner = nil
        }
    }
}
