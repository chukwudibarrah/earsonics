// EarsonicsCore/LibraryStore.swift
import Foundation
import Observation

/// Library state shared by every screen: the list of playlists, and the
/// stars the user has changed during this session.
///
/// Playlists are fetched once per server instead of by each screen, and
/// reloaded after anything that changes them. Starring is recorded here, so a
/// song starred in Now Playing shows as starred in every list — the songs,
/// albums and artists other screens hold are copies from when they were
/// fetched, and don't change by themselves.
@MainActor
@Observable
public final class LibraryStore {
    public static let shared = LibraryStore()

    public private(set) var playlists: [Playlist] = []

    /// The server `playlists` belongs to.
    @ObservationIgnored private var playlistsServerID: UUID?
    @ObservationIgnored private var playlistLoad: Task<Void, Never>?

    public enum StarKind: Hashable, Sendable {
        case song, album, artist
    }

    private struct StarKey: Hashable {
        public let kind: StarKind
        public let id: String
    }

    /// Stars changed this session, which win over what an older copy says.
    private var starChanges: [StarKey: Bool] = [:]

    // MARK: Playlists

    /// Loads the playlists if they haven't been loaded for the active server
    /// yet; `force` reloads them (after a playlist was created, renamed,
    /// deleted or added to). Concurrent calls share one request.
    public func loadPlaylists(force: Bool = false) async {
        let client = SubsonicClient.shared
        guard let server = client.server else {
            playlists = []
            return
        }
        if !force, playlistsServerID == server.id, playlistLoad == nil { return }
        if !force, let running = playlistLoad {
            await running.value
            return
        }
        let task = Task { [weak self] in
            do {
                let loaded = try await client.getPlaylists(server: server)
                guard let self, client.server?.id == server.id else { return }
                self.playlists = loaded
                self.playlistsServerID = server.id
            } catch {
                // Keep showing what we had; screens that need the list show
                // their own error (see `Messages` for actions).
            }
        }
        playlistLoad = task
        await task.value
        if playlistLoad == task { playlistLoad = nil }
    }

    /// Forgets everything: the active server changed.
    public func reset() {
        playlistLoad?.cancel()
        playlistLoad = nil
        playlists = []
        playlistsServerID = nil
        starChanges = [:]
    }

    // MARK: Stars

    /// Whether something is starred: this session's change if there is one,
    /// otherwise what the server said when the item was fetched.
    public func isStarred(_ kind: StarKind, id: String, fetched: Date?) -> Bool {
        starChanges[StarKey(kind: kind, id: id)] ?? (fetched != nil)
    }

    /// Stars or un-stars on the server, then records it so every screen
    /// agrees. Throws if the server refuses (the star then stays as it was).
    public func setStarred(_ starred: Bool, _ kind: StarKind, id: String) async throws {
        let client = SubsonicClient.shared
        switch (kind, starred) {
        case (.song, true):    try await client.star(songId: id)
        case (.song, false):   try await client.unstar(songId: id)
        case (.album, true):   try await client.star(albumId: id)
        case (.album, false):  try await client.unstar(albumId: id)
        case (.artist, true):  try await client.star(artistId: id)
        case (.artist, false): try await client.unstar(artistId: id)
        }
        starChanges[StarKey(kind: kind, id: id)] = starred
    }

    /// Flips a star from a button, saying so if the server refuses.
    public func toggleStar(_ kind: StarKind, id: String, isStarred: Bool) async {
        do {
            try await setStarred(!isStarred, kind, id: id)
        } catch {
            Messages.shared.showFailure(isStarred ? "remove it from Favourites" : "add it to Favourites", error)
        }
    }
}
