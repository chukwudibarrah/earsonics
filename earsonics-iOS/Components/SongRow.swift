// earsonics-iOS/Components/SongRow.swift
import SwiftUI
import EarsonicsCore

/// One song in a list. Tapping plays the list from this song; a long press
/// offers Play next, Add to queue, Favourite and links to the album and
/// artist.
struct SongRow: View {
    let song: Song
    let index: Int
    let songs: [Song]
    var context: PlayContext = .mix
    /// Show the track number instead of artwork (album pages).
    var showsTrackNumber = false
    /// The page, for mix lists (see `PlaySource`).
    var source: String? = nil
    private let player = AudioPlayerService.shared

    private var isCurrent: Bool { player.currentSong?.id == song.id }

    var body: some View {
        Button {
            player.load(songs: songs, startIndex: index, context: context)
            PlaySource.shared.record(source)
        } label: {
            HStack(spacing: 14) {
                if showsTrackNumber {
                    Group {
                        if isCurrent {
                            Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                                .foregroundStyle(.tint)
                        } else {
                            Text(song.track.map(String.init) ?? "–").foregroundStyle(Palette.secondaryText)
                        }
                    }
                    .font(.subheadline.monospacedDigit())
                    .frame(width: 28)
                } else {
                    Artwork(id: song.coverArt, pixels: 120, cornerRadius: 8)
                        .frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.body.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    Text(song.artist ?? "").font(.subheadline).foregroundStyle(Palette.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 8)
                SongDownloadBadge(songId: song.id)
                Text(song.durationFormatted)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { SongMenu(song: song) }
        .accessibilityLabel("\(song.title), \(song.artist ?? ""), \(song.durationFormatted)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Long-press actions for a song.
struct SongMenu: View {
    let song: Song
    private let player = AudioPlayerService.shared
    private var isStarred: Bool { LibraryStore.shared.isStarred(.song, id: song.id, fetched: song.starred) }

    var body: some View {
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { player.addToQueueNext(song) }
        Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { player.addToQueue(song) }
        Button(isStarred ? "Remove from Favourites" : "Add to Favourites", systemImage: isStarred ? "heart.slash" : "heart") {
            Task { await LibraryStore.shared.toggleStar(.song, id: song.id, isStarred: isStarred) }
        }
        AddToPlaylistMenu(songIDs: [song.id])
        SongDownloadMenuItem(song: song)
        Divider()
        if let albumId = song.albumId {
            NavigationLink(value: Route.albumID(id: albumId, name: song.album ?? "")) {
                Label("Go to Album", systemImage: "square.stack")
            }
        }
        if let artistId = song.artistId {
            NavigationLink(value: Route.artistID(id: artistId, name: song.artist ?? "")) {
                Label("Go to Artist", systemImage: "music.mic")
            }
        }
    }
}

/// Long-press actions for an album.
struct AlbumMenu: View {
    let album: Album

    var body: some View {
        Button("Play", systemImage: "play.fill") { Task { await Playback.playAlbum(album.id, shuffle: false) } }
        Button("Shuffle", systemImage: "shuffle") { Task { await Playback.playAlbum(album.id, shuffle: true) } }
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            Task { await Playback.queueAlbum(album.id, next: true) }
        }
        Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") {
            Task { await Playback.queueAlbum(album.id, next: false) }
        }
        if let artistId = album.artistId {
            Divider()
            NavigationLink(value: Route.artistID(id: artistId, name: album.artist ?? "")) {
                Label("Go to Artist", systemImage: "music.mic")
            }
        }
    }
}

/// "Add to Playlist" submenu, with the playlists the server has.
struct AddToPlaylistMenu: View {
    let songIDs: [String]

    var body: some View {
        let playlists = LibraryStore.shared.playlists
        if !playlists.isEmpty {
            Menu("Add to Playlist", systemImage: "music.note.list") {
                ForEach(playlists) { playlist in
                    Button(playlist.name) {
                        Task { await PlaylistAdder.shared.add(songIDs: songIDs, to: playlist) }
                    }
                }
            }
        }
    }
}

/// Fetch-then-play actions shared by pages and menus. Failures show the
/// app-wide message.
@MainActor
enum Playback {
    private static var player: AudioPlayerService { .shared }

    static func playAlbum(_ id: String, shuffle: Bool) async {
        do {
            let songs = try await SubsonicClient.shared.getAlbum(id: id).songs ?? []
            guard !songs.isEmpty else { return }
            player.load(songs: songs, startIndex: shuffle ? Int.random(in: songs.indices) : 0,
                        shuffle: shuffle, context: .album(id: id))
        } catch {
            Messages.shared.showFailure("play the album", error)
        }
    }

    static func queueAlbum(_ id: String, next: Bool) async {
        do {
            let songs = try await SubsonicClient.shared.getAlbum(id: id).songs ?? []
            if next { player.addToQueueNext(songs) } else { player.addToQueue(songs) }
            Messages.shared.show(next ? "Playing next" : "Added to the queue")
        } catch {
            Messages.shared.showFailure("queue the album", error)
        }
    }

    /// `source` names the page for lists that play as a mix (Songs,
    /// Favourites…), so the page can tell it's what's playing.
    static func play(_ songs: [Song], shuffle: Bool, context: PlayContext, source: String? = nil) {
        guard !songs.isEmpty else { return }
        player.load(songs: songs, startIndex: shuffle ? Int.random(in: songs.indices) : 0,
                    shuffle: shuffle, context: context)
        PlaySource.shared.record(source)
    }
}

/// Which mix page started the current queue. Albums, artists, playlists and
/// genres are known from the queue's context; a mix (Songs, Favourites,
/// Downloads) isn't, so the page that played it is noted here. The note is
/// tied to the queue's first entry, so it lapses as soon as anything else
/// replaces the queue.
@MainActor @Observable
final class PlaySource {
    static let shared = PlaySource()
    private var key: String?
    private var entryID: UUID?

    func record(_ key: String?) {
        self.key = key
        entryID = key == nil ? nil : AudioPlayerService.shared.playQueue.entries.first?.id
    }

    func isPlaying(_ key: String) -> Bool {
        guard key == self.key, let entryID else { return false }
        return AudioPlayerService.shared.playQueue.entries.contains { $0.id == entryID }
    }
}
