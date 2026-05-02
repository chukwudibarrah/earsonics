// Views/PlaylistsView.swift
import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var appState: AppState
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var showCreate = false
    @State private var newPlaylistName = ""
    @State private var selectedPlaylist: Playlist? = nil

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
                    List(playlists) { playlist in
                        PlaylistRow(playlist: playlist) {
                            Task { await loadPlaylists() }
                        }
                        .onTapGesture { selectedPlaylist = playlist }
                        .contextMenu {
                            Button(role: .destructive) {
                                Task {
                                    try? await SubsonicClient.shared.deletePlaylist(id: playlist.id)
                                    await loadPlaylists()
                                }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
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
            .alert("New Playlist", isPresented: $showCreate) {
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
            .navigationDestination(item: $selectedPlaylist) { playlist in
                PlaylistDetailView(playlist: playlist)
            }
        }
    }

    private func loadPlaylists() async {
        isLoading = true
        playlists = (try? await SubsonicClient.shared.getPlaylists()) ?? []
        isLoading = false
    }
}

struct PlaylistRow: View {
    let playlist: Playlist
    let onRefresh: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 16) {
            CoverArtView(id: playlist.coverArt, size: 100)
                .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name).font(.headline)
                HStack(spacing: 8) {
                    if let count = playlist.songCount {
                        Text("\(count) tracks").font(.caption).foregroundColor(.secondary)
                    }
                    if let owner = playlist.owner {
                        Text("by \(owner)").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .focusable()
        .focused($focused)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(focused ? Color.white.opacity(0.1) : Color.clear)
        )
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
                        Label("Play", systemImage: "play.fill")
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(Color.accentColor).foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        var shuffled = songs; shuffled.shuffle()
                        appState.player.load(songs: shuffled, startIndex: 0)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
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
                            SongRow(song: song, index: idx) {
                                appState.player.load(songs: songs, startIndex: idx)
                            }
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
                }
            }
        }
        .padding(60)
        .task { await reload() }
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
