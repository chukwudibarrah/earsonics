#!/usr/bin/env python3
"""
Patch AlbumDetailView.swift:
  1. Fix Shuffle button (toggleShuffle, scoped active indicator)
  2. Remove outer Button wrapper from track list ForEach (SongRow is now self-contained)
  3. Normalise top padding to layoutTopPadding
  4. Rewrite SongRow: accepts songs[] + onRemove closure, wraps its own Button + contextMenu
"""

import sys

PATH = 'earsonics/Views/AlbumDetailView.swift'

with open(PATH, 'r') as f:
    content = f.read()

# ── Patch 1: Fix Shuffle button ───────────────────────────────────────────────
old1 = (
    '                    Button {\n'
    '                        var shuffled = songs\n'
    '                        shuffled.shuffle()\n'
    '                        appState.player.load(songs: shuffled, startIndex: 0)\n'
    '                    } label: {\n'
    '                        Label("Shuffle", systemImage: "shuffle")\n'
    '                            .frame(maxWidth: .infinity)\n'
    '                            .font(.caption2)\n'
    '                    }'
)
new1 = (
    '                    Button {\n'
    '                        if isThisAlbumPlaying {\n'
    '                            player.toggleShuffle()\n'
    '                        } else if !songs.isEmpty {\n'
    '                            appState.player.isShuffled = false\n'
    '                            appState.player.load(songs: songs, startIndex: 0)\n'
    '                            player.toggleShuffle()\n'
    '                        }\n'
    '                    } label: {\n'
    '                        Label("Shuffle", systemImage: "shuffle")\n'
    '                            .frame(maxWidth: .infinity)\n'
    '                            .font(.caption2)\n'
    '                            .foregroundColor(isThisAlbumPlaying && player.isShuffled ? .accentColor : .primary)\n'
    '                    }'
)
assert old1 in content, "PATCH 1 NOT FOUND"
content = content.replace(old1, new1, 1)
print("Patch 1 applied: Shuffle button fixed")

# ── Patch 2: Remove outer Button wrapper from track list ──────────────────────
old2 = (
    '                        ForEach(Array(songs.enumerated()), id: \\.element.id) { idx, song in\n'
    '                            Button {\n'
    '                                appState.player.load(songs: songs, startIndex: idx)\n'
    '                            } label: {\n'
    '                                SongRow(song: song, index: idx, playlists: playlists)\n'
    '                            }\n'
    '                            .buttonStyle(.card)\n'
    '                        }'
)
new2 = (
    '                        ForEach(Array(songs.enumerated()), id: \\.element.id) { idx, song in\n'
    '                            SongRow(song: song, index: idx, songs: songs, playlists: playlists)\n'
    '                        }'
)
assert old2 in content, "PATCH 2 NOT FOUND"
content = content.replace(old2, new2, 1)
print("Patch 2 applied: outer Button removed from track list")

# ── Patch 3: Normalise top padding ────────────────────────────────────────────
old3 = '        .padding(.top, 200) // add padding to top of tracklist'
new3 = '        .padding(.top, layoutTopPadding)'
assert old3 in content, "PATCH 3 NOT FOUND"
content = content.replace(old3, new3, 1)
print("Patch 3 applied: top padding normalised")

# ── Patch 4: Replace entire SongRow struct ────────────────────────────────────
marker = '// MARK: - Song Row'
idx = content.index(marker)

new_songrow = r'''// MARK: - Song Row
struct SongRow: View {
    let song: Song
    let index: Int
    let songs: [Song]                          // full queue for tap-to-play
    var playlists: [Playlist] = []
    var showTrackNumber: Bool = true
    var onRemove: (() -> Void)? = nil          // playlist-specific remove action
    @EnvironmentObject var appState: AppState
    @State private var isStarred: Bool

    init(song: Song, index: Int, songs: [Song],
         playlists: [Playlist] = [], showTrackNumber: Bool = true,
         onRemove: (() -> Void)? = nil) {
        self.song = song
        self.index = index
        self.songs = songs
        self.playlists = playlists
        self.showTrackNumber = showTrackNumber
        self.onRemove = onRemove
        _isStarred = State(initialValue: song.starred != nil)
    }

    var isCurrentSong: Bool {
        appState.player.currentSong?.id == song.id
    }

    var body: some View {
        Button {
            appState.player.load(songs: songs, startIndex: index)
        } label: {
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
        }
        .buttonStyle(.card)
        .onPlayPauseCommand { appState.player.togglePlayPause() }
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
                Label("Play next", systemImage: "text.insert")
            }
            Button {
                appState.player.addToQueue(song)
            } label: {
                Label("Add to queue", systemImage: "text.badge.plus")
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
            if let onRemove {
                Divider()
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove from Playlist", systemImage: "minus.circle")
                }
            }
        }
    }
}
'''

content = content[:idx] + new_songrow
print("Patch 4 applied: SongRow rewritten (self-contained Button + contextMenu)")

with open(PATH, 'w') as f:
    f.write(content)

print("\nAll patches applied successfully to", PATH)
