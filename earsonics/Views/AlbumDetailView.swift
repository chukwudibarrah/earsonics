// Views/AlbumDetailView.swift
import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    @EnvironmentObject var appState: AppState
    @State private var loadedAlbum: Album? = nil
    @State private var isLoading = true
    @State private var isStarred: Bool = false

    var songs: [Song] { loadedAlbum?.songs ?? [] }

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            // Left: Cover + info
            VStack(alignment: .leading, spacing: 16) {
                CoverArtView(id: album.coverArt, size: 600)
                    .frame(width: 360, height: 360)
                    .cornerRadius(16)

                Text(album.name)
                    .font(.title2).bold()
                    .lineLimit(2)

                if let artist = album.artist {
                    Text(artist)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    if let year = album.year { Text("\(year)").foregroundColor(.secondary) }
                    if let genre = album.genre { Text(genre).foregroundColor(.secondary) }
                    if let count = album.songCount { Text("\(count) tracks").foregroundColor(.secondary) }
                }
                .font(.callout)

                HStack(spacing: 20) {
                    Button {
                        if !songs.isEmpty {
                            appState.player.load(songs: songs, startIndex: 0)
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 24).padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        var shuffled = songs
                        shuffled.shuffle()
                        appState.player.load(songs: shuffled, startIndex: 0)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.headline)
                            .padding(.horizontal, 24).padding(.vertical, 12)
                            .background(Color.white.opacity(0.15))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    StarButton(isStarred: isStarred, albumId: album.id) { newVal in
                        isStarred = newVal
                    }
                }

                Spacer()
            }
            .frame(width: 380)

            // Right: Track list
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                            SongRow(song: song, index: idx, onTap: {
                                appState.player.load(songs: songs, startIndex: idx)
                            })
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(60)
        .task {
            isLoading = true
            if let detailed = try? await SubsonicClient.shared.getAlbum(id: album.id) {
                loadedAlbum = detailed
                isStarred = detailed.starred != nil
            }
            isLoading = false
        }
    }
}

// MARK: - Song Row
struct SongRow: View {
    let song: Song
    let index: Int
    let onTap: () -> Void
    @EnvironmentObject var appState: AppState
    @FocusState private var focused: Bool
    @State private var isStarred: Bool

    init(song: Song, index: Int, onTap: @escaping () -> Void) {
        self.song = song
        self.index = index
        self.onTap = onTap
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
                        .font(.caption)
                } else {
                    Text("\(song.track ?? (index + 1))")
                        .foregroundColor(.secondary)
                        .font(.callout)
                }
            }
            .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.callout)
                    .fontWeight(isCurrentSong ? .bold : .regular)
                    .foregroundColor(isCurrentSong ? .accentColor : .primary)
                if let artist = song.artist, artist != appState.player.currentSong?.album {
                    Text(artist).font(.caption).foregroundColor(.secondary)
                }
            }

            Spacer()

            FormatBadge(song: song)

            StarButton(isStarred: isStarred, songId: song.id) { newVal in isStarred = newVal }

            // Add to queue button
            Button {
                appState.player.addToQueue(song)
            } label: {
                Image(systemName: "text.badge.plus")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Text(song.durationFormatted)
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(focused ? Color.white.opacity(0.12) : Color.clear)
        )
        .focusable()
        .focused($focused)
        .onPlayPauseCommand { appState.player.togglePlayPause() }
        .onTapGesture { onTap() }
        .animation(.easeInOut(duration: 0.1), value: focused)
    }
}
