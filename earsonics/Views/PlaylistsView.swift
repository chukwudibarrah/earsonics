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
            .navigationTitle("Playlists")
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
                    if let owner = playlist.owner {
                        Text("by \(owner)")
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

                HStack(spacing: 12) {
                    Button {
                        if !songs.isEmpty { appState.player.load(songs: songs, startIndex: 0) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Play")
                        }
                        .font(.callout).bold()
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.8)).foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        var shuffled = songs; shuffled.shuffle()
                        appState.player.load(songs: shuffled, startIndex: 0)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "shuffle")
                            Text("Shuffle")
                        }
                        .font(.callout).bold()
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Color.white.opacity(0.15)).foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    Button { isEditing = true } label: {
                        Image(systemName: "pencil")
                            .padding(12)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .frame(width: 350)

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                            Button {
                                appState.player.load(songs: songs, startIndex: idx)
                            } label: {
                                SongRow(song: song, index: idx, playlists: playlists)
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
                    .padding(.vertical, 8)
                    .padding(.bottom, 100)
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
