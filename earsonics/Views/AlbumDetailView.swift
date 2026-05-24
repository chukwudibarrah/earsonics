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
        HStack(alignment: .top, spacing: 50) {
            // Left: Cover + info
            VStack(alignment: .leading, spacing: 16) {
                CoverArtView(id: album.coverArt, size: 600)
                    .frame(width: 340, height: 340)
                    .cornerRadius(16)

                Text(album.name)
                    .font(.headline).bold()
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)

                if let artist = album.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 5) {
                    if let year = album.year { 
                        Text(String(format: "%d", year)).foregroundColor(.secondary)
                        if album.genre != nil || album.songCount != nil {
                            Text("•").foregroundColor(.secondary)
                        }
                    }
                    if let genre = album.genre { 
                        Text(genre).foregroundColor(.secondary)
                        if album.songCount != nil {
                            Text("•").foregroundColor(.secondary)
                        }
                    }
                    if let count = album.songCount { 
                        Text("\(count) tracks").foregroundColor(.secondary) 
                    }
                }
                .font(.body)

                // Actions
                VStack(spacing: 12) {
                    Button {
                        if isThisAlbumPlaying {
                            player.togglePlayPause()
                        } else if !songs.isEmpty {
                            appState.player.load(songs: songs, startIndex: 0)
                        }
                    } label: {
                        Label(isThisAlbumPlaying && player.isPlaying ? "Pause" : "Play", systemImage: isThisAlbumPlaying && player.isPlaying ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        var shuffled = songs
                        shuffled.shuffle()
                        appState.player.load(songs: shuffled, startIndex: 0)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .frame(maxWidth: .infinity)
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
                    }
                    
                    Button {
                        if !songs.isEmpty {
                            appState.player.addToQueueNext(songs[0])
                            for song in songs.dropFirst() {
                                appState.player.addToQueue(song)
                            }
                        }
                    } label: {
                        Label("Play Next", systemImage: "text.insert")
                            .frame(maxWidth: .infinity)
                    }
                    
                    Button {
                        for song in songs {
                            appState.player.addToQueue(song)
                        }
                    } label: {
                        Label("Add to Queue", systemImage: "text.badge.plus")
                            .frame(maxWidth: .infinity)
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
                        }
                    }
                }

                Spacer()
            }
            .frame(width: 360)

            // Right: Track list
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)   // prevent top card from clipping on first focus
                    .padding(.bottom, 120)
                }
            }
        }
//        .padding(60)
        .padding(.top, 100) // add padding to top of tracklist
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
    var playlists: [Playlist] = []
    @EnvironmentObject var appState: AppState
    @State private var isStarred: Bool

    init(song: Song, index: Int, playlists: [Playlist] = []) {
        self.song = song
        self.index = index
        self.playlists = playlists
        _isStarred = State(initialValue: song.starred != nil)
    }

    var isCurrentSong: Bool {
        appState.player.currentSong?.id == song.id
    }

    var body: some View {
        HStack(spacing: 16) {
            // Track number / playing indicator
            ZStack {
                if isCurrentSong {
                    Image(systemName: appState.player.isPlaying ? "waveform" : "pause.fill")
                        .foregroundColor(.accentColor)
                        .font(.caption2)
                } else {
                    Text(String(format: "%d", song.track ?? (index + 1)))
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 32, alignment: .center)

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

//            FormatBadge(song: song)

            // Plain image, NOT a button, to prevent focus trapping
            Image(systemName: isStarred ? "heart.fill" : "heart")
                .foregroundColor(isStarred ? .red : .primary.opacity(0.8))
                .font(.callout)

            Text(song.durationFormatted)
                .font(.caption.monospacedDigit())
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onPlayPauseCommand { appState.player.togglePlayPause() }
        // Context menu: Star + Play Next + Add to Queue + Add to playlist
        .contextMenu {
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
                Label("Play Next", systemImage: "text.insert")
            }
            Button {
                appState.player.addToQueue(song)
            } label: {
                Label("Add to Queue", systemImage: "text.badge.plus")
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
}
