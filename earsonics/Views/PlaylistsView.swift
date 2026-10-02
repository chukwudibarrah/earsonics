// Views/PlaylistsView.swift
import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var appState: AppState
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var showCreate = false
    @State private var newPlaylistName = ""
    @ObservedObject private var player = AudioPlayerService.shared

    var body: some View {
        NavigationStack {
            if isLoading && playlists.isEmpty {
                ProgressView("Loading Playlists...")
            } else if playlists.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 60)).foregroundColor(.secondary)
                    Text("No Playlists").font(.title)
                    Text("Create a playlist to get started").foregroundColor(.secondary)
                    newPlaylistButton
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        newPlaylistButton
                            .padding(.bottom, 12)
                        ForEach(playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(playlist: playlist)
                                    .environmentObject(appState)
                            } label: {
                                PlaylistRow(playlist: playlist) {
                                    Task { await loadPlaylists() }
                                }
                            }
                            .buttonStyle(CardlessButtonStyle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task {
                                        try? await SubsonicClient.shared.deletePlaylist(id: playlist.id)
                                        await loadPlaylists()
                                    }
                                } label: { Label("Delete Playlist", systemImage: "trash") }
                            }
                        }
                    }
                    .padding(.top, AppLayout.contentTopPadding)
                    .padding(.horizontal, AppLayout.horizontalPadding)
                    .padding(.bottom, 120)
                }
            }
        }
        .task { await loadPlaylists() }
        .alert("New playlist", isPresented: $showCreate) {
            TextField("Name", text: $newPlaylistName)
            Button("Create") {
                Task {
                    if !newPlaylistName.isEmpty {
                        _ = try? await SubsonicClient.shared.createPlaylist(name: newPlaylistName)
                        newPlaylistName = ""
                        await loadPlaylists()
                    }
                }
            }
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
        }
    }

    // In the content rather than a toolbar item: the screen has no visible
    // navigation bar, so a toolbar button never appeared.
    private var newPlaylistButton: some View {
        Button { showCreate = true } label: {
            Label("New playlist", systemImage: "plus")
        }
        .buttonStyle(AccentPillButtonStyle())
    }

    private func loadPlaylists() async {
        isLoading = true
        playlists = (try? await SubsonicClient.shared.getPlaylists()) ?? []
        isLoading = false
    }
}

// MARK: - Playlist Row
struct PlaylistRow: View {
    let playlist: Playlist
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            CoverArtView(id: playlist.coverArt, size: 100)
                .frame(width: 80, height: 80)
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.name)
                    .font(.title3).bold()
                HStack(spacing: 12) {
                    if let count = playlist.songCount {
                        Label("\(count) tracks", systemImage: "music.note")
                            .font(.callout)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.callout)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .cardSurface(cornerRadius: 10)
    }
}

// MARK: - Playlist Detail
struct PlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var appState: AppState
    @ObservedObject private var player = AudioPlayerService.shared
    @Environment(\.appAccent) private var appAccent
    @State private var loadedPlaylist: Playlist? = nil
    @State private var isLoading = true
    @State private var isEditing = false
    @State private var editName = ""
    @State private var playlists: [Playlist] = []

    var songs: [Song] { loadedPlaylist?.songs ?? [] }

    var isThisPlaylistPlaying: Bool {
        guard let current = player.currentSong else { return false }
        return songs.contains { $0.id == current.id }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 50) {
            // Left panel
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 10) {
                    Button {
                        if isThisPlaylistPlaying {
                            player.togglePlayPause()
                        } else if !songs.isEmpty {
                            appState.player.isShuffled = false
                            appState.player.load(songs: songs, startIndex: 0)
                        }
                    } label: {
                        Label(isThisPlaylistPlaying && player.isPlaying ? "Pause" : "Play",
                              systemImage: isThisPlaylistPlaying && player.isPlaying ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                            .font(.caption2)
                    }

                    Button {
                        if isThisPlaylistPlaying {
                            player.toggleShuffle()
                        } else if !songs.isEmpty {
                            appState.player.isShuffled = false
                            appState.player.load(songs: songs, startIndex: 0)
                            player.toggleShuffle()
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .frame(maxWidth: .infinity)
                            .font(.caption2)
                    }

                    Button { isEditing = true } label: {
                        Label("Rename", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                            .font(.caption2)
                    }
                }
                .buttonStyle(AccentPillButtonStyle())

                CoverArtView(id: playlist.coverArt, size: 400)
                    .frame(width: 250, height: 250)
                    .cornerRadius(16)

                Text(loadedPlaylist?.name ?? playlist.name)
                    .font(.headline)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)

                if let comment = playlist.comment {
                    Text(comment).foregroundColor(.secondary).font(.caption2)
                }

                if let count = playlist.songCount {
                    Text("\(count) tracks")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .frame(width: 250)

            // Right panel: track list
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        // Keyed by position because a playlist can hold the same
                        // song twice; the inner `.id` recreates a row (and its
                        // star state) when a removal shifts a different song
                        // into that position.
                        ForEach(Array(songs.enumerated()), id: \.offset) { idx, song in
                            SongRow(
                                song: song,
                                index: idx,
                                contextSongs: songs,
                                playlists: playlists,
                                showTrackNumber: false
                            ) {
                                Task {
                                    try? await SubsonicClient.shared.updatePlaylist(
                                        id: playlist.id, indexesToRemove: [idx])
                                    await reload()
                                }
                            }
                            .id(song.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
            }
        }
        .padding(.top, AppLayout.detailTopPadding)
        .padding(.horizontal, AppLayout.horizontalPadding)
        .task {
            await reload()
            playlists = (try? await SubsonicClient.shared.getPlaylists()) ?? []
        }
        .alert("Rename Playlist", isPresented: $isEditing) {
            TextField("Name", text: $editName)
            Button("Save") {
                Task {
                    try? await SubsonicClient.shared.updatePlaylist(id: playlist.id, name: editName)
                    await reload()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { editName = playlist.name }
    }

    private func reload() async {
        isLoading = true
        loadedPlaylist = try? await SubsonicClient.shared.getPlaylist(id: playlist.id)
        isLoading = false
    }
}
