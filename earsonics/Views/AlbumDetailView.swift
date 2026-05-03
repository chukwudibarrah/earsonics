// Views/AlbumDetailView.swift
import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    @EnvironmentObject var appState: AppState
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var loadedAlbum: Album? = nil
    @State private var isLoading = true
    @State private var isStarred: Bool = false

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

                if let artist = album.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    if let year = album.year { Text(String(format: "%d", year)).foregroundColor(.secondary) }
                    if let genre = album.genre { Text(genre).foregroundColor(.secondary) }
                    if let count = album.songCount { Text("\(count) tracks").foregroundColor(.secondary) }
                }
                .font(.callout)

                // Play / Shuffle stacked vertically — guaranteed no truncation
                VStack(spacing: 10) {
                    Button {
                        if isThisAlbumPlaying {
                            player.togglePlayPause()
                        } else if !songs.isEmpty {
                            appState.player.load(songs: songs, startIndex: 0)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isThisAlbumPlaying && player.isPlaying ? "pause.fill" : "play.fill")
                            Text(isThisAlbumPlaying && player.isPlaying ? "Pause" : "Play")
                                .lineLimit(1)
                        }
                        .font(.callout).bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
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
                        HStack(spacing: 8) {
                            Image(systemName: "shuffle")
                            Text("Shuffle")
                                .lineLimit(1)
                        }
                        .font(.callout).bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.15))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }

                // Star on its own row so it doesn't crowd the buttons
                StarButton(isStarred: isStarred, albumId: album.id) { newVal in
                    isStarred = newVal
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
                        .font(.caption2)
                } else {
                    Text(String(format: "%d", song.track ?? (index + 1)))
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 36, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.footnote)
                    .fontWeight(isCurrentSong ? .bold : .regular)
                    .foregroundColor(isCurrentSong ? .accentColor : .primary)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
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
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Text(song.durationFormatted)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
