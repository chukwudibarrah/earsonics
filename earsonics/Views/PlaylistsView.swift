// Views/PlaylistsView.swift
import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var appState: AppState
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var showCreate = false
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && playlists.isEmpty {
                    ProgressView("Loading Playlists...")
                } else if playlists.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 60)).foregroundColor(.secondary)
                        Text("No Playlists").font(.title)
                        Text("Create a playlist to get started").foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(playlists) { playlist in
                                NavigationLink {
                                    PlaylistDetailView(playlist: playlist)
                                        .environmentObject(appState)
                                } label: {
                                    PlaylistRow(playlist: playlist) {
                                        Task { await loadPlaylists() }
                                    }
                                }
                                .buttonStyle(.card)
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
                        .padding(.horizontal, 80)
                        .padding(.vertical, 24)
                        .padding(.bottom, 120)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
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
    }
}

// MARK: - Playlist Detail
struct PlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var appState: AppState
    @State private var loadedPlaylist: Playlist? = nil
    @State private var isLoading = true
    @State private var isEditing = false
    @State private var editName = ""
    @State private var playlists: [Playlist] = [] // for add-to-playlist from songs

    var songs: [Song] { loadedPlaylist?.songs ?? [] }

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            VStack(alignment: .leading, spacing: 16) {
                CoverArtView(id: playlist.coverArt, size: 600)
                    .frame(width: 320, height: 320)
                    .cornerRadius(16)

                Text(loadedPlaylist?.name ?? playlist.name)
                    .font(.title2).bold()

                if let comment = playlist.comment {
                    Text(comment).foregroundColor(.secondary).font(.callout)
                }

                // Actions
                VStack(spacing: 14) {
                    Button {
                        if !songs.isEmpty { appState.player.load(songs: songs, startIndex: 0) }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        var shuffled = songs; shuffled.shuffle()
                        appState.player.load(songs: shuffled, startIndex: 0)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .frame(maxWidth: .infinity)
                    }

                    Button { isEditing = true } label: {
                        Label("Rename", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                }

                Spacer()
            }
            .frame(width: 350)

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 16) {
                            Button {
                                if !songs.isEmpty { appState.player.load(songs: songs, startIndex: 0) }
                            } label: {
                                Label("Play All", systemImage: "play.fill")
                            }
                            Button {
                                var shuffled = songs; shuffled.shuffle()
                                appState.player.load(songs: shuffled, startIndex: 0)
                            } label: {
                                Label("Shuffle Play", systemImage: "shuffle")
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        LazyVStack(spacing: 2) {
                            ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                                Button {
                                    appState.player.load(songs: songs, startIndex: idx)
                                } label: {
                                    SongRow(song: song, index: idx, playlists: playlists, showTrackNumber: false)
                                }
                                .buttonStyle(.card)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task {
                                            try? await SubsonicClient.shared.updatePlaylist(
                                                id: playlist.id, indexesToRemove: [idx])
                                            await reload()
                                        }
                                    } label: { Label("Remove from Playlist", systemImage: "minus.circle") }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
            }
        }
        .padding(60)
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
