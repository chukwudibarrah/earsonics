// Views/AlbumDetailView.swift
import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    @EnvironmentObject var appState: AppState
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var loadedAlbum: Album? = nil
    @State private var isLoading = true
    @State private var isStarred: Bool = false
    @State private var playlists: [Playlist] = []

    var songs: [Song] { loadedAlbum?.songs ?? [] }

    var isThisAlbumPlaying: Bool {
        player.currentSong?.albumId == album.id
    }

    var body: some View {
        HStack(alignment: .top, spacing: 30) {
            // Left: Cover + info
            VStack(alignment: .leading, spacing: 16) {
                // Actions
                VStack(spacing: 7) {
                    Button {
                        if isThisAlbumPlaying {
                            player.togglePlayPause()
                        } else if !songs.isEmpty {
                            appState.player.load(songs: songs, startIndex: 0)
                        }
                    } label: {
                        Label(isThisAlbumPlaying && player.isPlaying ? "Pause" : "Play", systemImage: isThisAlbumPlaying && player.isPlaying ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                            .font(.caption2)
                    }
                    

                    Button {
                        var shuffled = songs
                        shuffled.shuffle()
                        appState.player.load(songs: shuffled, startIndex: 0)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .frame(maxWidth: .infinity)
                            .font(.caption2)
                    }

                    Button {
                        Task {
                            if isStarred {
                                try? await SubsonicClient.shared.unstar(albumId: album.id)
                                isStarred = false
                            } else {
                                try? await SubsonicClient.shared.star(albumId: album.id)
                                isStarred = true
                            }
                        }
                    } label: {
                        Label(isStarred ? "Unstar" : "Star", systemImage: isStarred ? "heart.fill" : "heart")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(isStarred ? .red : .primary)
                            .font(.caption2)
                    }
                    
                    Button {
                        if !songs.isEmpty {
                            appState.player.addToQueueNext(songs[0])
                            for song in songs.dropFirst() {
                                appState.player.addToQueue(song)
                            }
                        }
                    } label: {
                        Label("Play next", systemImage: "text.insert")
                            .frame(maxWidth: .infinity)
                            .font(.caption2)
                    }
                    
                    Button {
                        for song in songs {
                            appState.player.addToQueue(song)
                        }
                    } label: {
                        Label("Add to queue", systemImage: "text.badge.plus")
                            .frame(maxWidth: .infinity)
                            .font(.caption2)
                    }

                    if !playlists.isEmpty {
                        Menu {
                            ForEach(playlists) { playlist in
                                Button {
                                    Task {
                                        let ids = songs.map { $0.id }
                                        try? await SubsonicClient.shared.updatePlaylist(
                                            id: playlist.id, songIdsToAdd: ids)
                                    }
                                } label: {
                                    Label("Add to \(playlist.name)", systemImage: "music.note.list")
                                }
                            }
                        } label: {
                            Label("Add to playlist", systemImage: "text.badge.plus")
                                .frame(maxWidth: .infinity)
                                .font(.caption2)
                        }
                    }
                }
                .controlSize(.small)

                CoverArtView(id: album.coverArt, size: 400)
                    .frame(width: 230, height: 230)
                    .cornerRadius(16)

                Text(album.name)
                    .font(.callout)
                    .lineLimit(3)
//                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
//                    .lineHeight(.tight)

                if let artist = album.artist {
                    Text(artist)
                        .font(.caption2)
                        .foregroundColor(.secondary)
//                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 2) {
                    if let year = album.year {
                        Text(String(format: "%d", year)).foregroundColor(.secondary)
                        if album.genre != nil || album.songCount != nil {
                            Text("•").foregroundColor(.secondary)
                        }
                    }
                    if let genre = album.genre {
                        Text(genre).foregroundColor(.secondary)
//                        if album.songCount != nil {
//                           Text("•").foregroundColor(.secondary)
//                        }
                    }
 //                   if let count = album.songCount {
 //                       Text("\(count) tracks").foregroundColor(.secondary)
 //                   }
                }
                .font(.caption2)

                Spacer()
            }
            .frame(width: 230)
            .padding(.top, 200)

            // Right: Track list
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                            Button {
                                appState.player.load(songs: songs, startIndex: idx)
                            } label: {
                                SongRow(song: song, index: idx, playlists: playlists)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 200)
                    .padding(.bottom, 120)
                }
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, AppLayout.horizontalPadding)
        .task {
            isLoading = true
            async let albumLoad = SubsonicClient.shared.getAlbum(id: album.id)
            async let playlistLoad = SubsonicClient.shared.getPlaylists()
            if let detailed = try? await albumLoad {
                loadedAlbum = detailed
                isStarred = detailed.starred != nil
            }
            playlists = (try? await playlistLoad) ?? []
            isLoading = false
        }
    }
}

// MARK: - Song Row
struct SongRow: View {
    let song: Song
    let index: Int
    var contextSongs: [Song] = []
    var playlists: [Playlist] = []
    var showTrackNumber: Bool = true
    var onRemove: (() -> Void)? = nil
    @EnvironmentObject var appState: AppState
    @State private var isStarred: Bool

    init(song: Song, index: Int, contextSongs: [Song] = [], playlists: [Playlist] = [], showTrackNumber: Bool = true, onRemove: (() -> Void)? = nil) {
        self.song = song
        self.index = index
        self.contextSongs = contextSongs
        self.playlists = playlists
        self.showTrackNumber = showTrackNumber
        self.onRemove = onRemove
        _isStarred = State(initialValue: song.starred != nil)
    }

    var isCurrentSong: Bool {
        appState.player.currentSong?.id == song.id
    }

    var body: some View {
        if contextSongs.isEmpty {
            rowContent
                .contextMenu { contextMenuItems }
        } else {
            Button {
                appState.player.load(songs: contextSongs, startIndex: index)
            } label: {
                rowContent
            }
            .buttonStyle(.card)
            .contextMenu { contextMenuItems }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(spacing: 16) {
            // Track number / playing indicator
            if isCurrentSong || showTrackNumber {
                ZStack {
                    if isCurrentSong {
                        Image(systemName: appState.player.isPlaying ? "waveform" : "pause.fill")
                            .foregroundColor(.accentColor)
                            .font(.caption2)
                    } else if showTrackNumber {
                        Text(String(format: "%d", song.track ?? (index + 1)))
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(width: 32, alignment: .center)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.footnote)
                    .fontWeight(isCurrentSong ? .bold : .regular)
                    .foregroundColor(isCurrentSong ? .accentColor : .primary)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Vertical trailing alignment: heart button + duration in fixed width containers
            HStack(spacing: 20) {
                Image(systemName: isStarred ? "heart.fill" : "heart")
                    .foregroundColor(isStarred ? .red : .primary.opacity(0.8))
                    .font(.callout)
                    .frame(width: 30, alignment: .center)

                Text(song.durationFormatted)
                    .font(.caption2.monospacedDigit())
                    .frame(width: 65, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onPlayPauseCommand { appState.player.togglePlayPause() }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            Task {
                if isStarred {
                    try? await SubsonicClient.shared.unstar(songId: song.id)
                    isStarred = false
                } else {
                    try? await SubsonicClient.shared.star(songId: song.id)
                    isStarred = true
                }
            }
        } label: {
            Label(isStarred ? "Unstar" : "Star", systemImage: isStarred ? "heart.slash" : "heart")
        }
        Button {
            appState.player.addToQueueNext(song)
        } label: {
            Label("Play next", systemImage: "text.insert")
        }
        Button {
            appState.player.addToQueue(song)
        } label: {
            Label("Add to queue", systemImage: "text.badge.plus")
        }
        if let onRemove {
            Divider()
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove from playlist", systemImage: "minus.circle")
            }
        }
        if !playlists.isEmpty {
            Divider()
            ForEach(playlists) { playlist in
                Button {
                    Task {
                        try? await SubsonicClient.shared.updatePlaylist(
                            id: playlist.id, songIdsToAdd: [song.id])
                    }
                } label: {
                    Label("Add to \(playlist.name)", systemImage: "music.note.list")
                }
            }
        }
    }
}
