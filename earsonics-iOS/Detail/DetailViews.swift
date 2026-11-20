// earsonics-iOS/Detail/DetailViews.swift
import SwiftUI
import EarsonicsCore

/// Header beside the content when the window has room (iPad, an unfolded
/// iPhone Duo, landscape), above it otherwise. Decided by the space this
/// page has, never by the device.
struct DetailLayout<Header: View, Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 28) {
                    header()
                        .frame(maxWidth: 340)
                    content()
                        .frame(maxWidth: .infinity)
                }
                .padding()
            } else {
                VStack(spacing: 24) {
                    header()
                    content()
                }
                .padding()
            }
        }
        .appBackground()
    }
}

/// A big cover with title lines under it, sized to the space it's given.
struct DetailHeader<Actions: View>: View {
    let coverArt: String?
    var placeholder = "music.note"
    var round = false
    let title: String
    var subtitle: Route? = nil
    var subtitleText: String? = nil
    var detail: String? = nil
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 14) {
            Artwork(id: coverArt, pixels: 800, cornerRadius: round ? 400 : 24, placeholderSymbol: placeholder)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 320)
                .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
            VStack(spacing: 4) {
                Text(title).font(.title2.bold()).multilineTextAlignment(.center)
                if let subtitle, let subtitleText {
                    NavigationLink(value: subtitle) {
                        Text(subtitleText).font(.headline)
                    }
                } else if let subtitleText {
                    Text(subtitleText).font(.headline).foregroundStyle(.tint)
                }
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(Palette.secondaryText)
                }
            }
            actions()
        }
        .frame(maxWidth: .infinity)
    }
}

/// A list of songs on a card, with optional disc headings.
struct SongList: View {
    let songs: [Song]
    var context: PlayContext = .mix
    var showsTrackNumbers = false
    var groupsByDisc = false
    /// The page, for mix lists (see `PlaySource`).
    var source: String? = nil

    var body: some View {
        let discs = Set(songs.compactMap(\.discNumber))
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                if groupsByDisc, discs.count > 1, let disc = song.discNumber,
                   index == 0 || songs[index - 1].discNumber != disc {
                    Text("Disc \(disc)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.top, index == 0 ? 4 : 16)
                        .padding(.bottom, 4)
                } else if index > 0 {
                    Divider().padding(.leading, showsTrackNumbers ? 42 : 62)
                }
                SongRow(song: song, index: index, songs: songs, context: context, showsTrackNumber: showsTrackNumbers,
                        source: source)
            }
        }
        .card(cornerRadius: 22, padding: 12)
    }
}

// MARK: - Album

struct AlbumDetailView: View {
    let albumID: String
    /// What the list it was opened from already knows, shown while loading.
    let preview: Album?
    @State private var album: Album?
    @State private var failed = false

    private var shown: Album? { album ?? preview }
    private var songs: [Song] { album?.songs ?? [] }
    private var isStarred: Bool {
        LibraryStore.shared.isStarred(.album, id: albumID, fetched: album?.starred ?? preview?.starred)
    }

    var body: some View {
        DetailLayout {
            DetailHeader(coverArt: shown?.coverArt, title: shown?.name ?? "",
                         subtitle: shown?.artistId.map { .artistID(id: $0, name: shown?.artist ?? "") },
                         subtitleText: shown?.artist, detail: detailLine) {
                PlayShuffleRow(play: { Playback.play(songs, shuffle: false, context: .album(id: albumID)) },
                               shuffle: { Playback.play(songs, shuffle: true, context: .album(id: albumID)) },
                               isBusy: album == nil, context: .album(id: albumID)) {
                    CollectionDownloadButton(collection: album.map { $0.downloadCollection(songs: songs) }, songs: songs)
                    Button(isStarred ? "Remove from Favourites" : "Add to Favourites",
                           systemImage: isStarred ? "heart.fill" : "heart") {
                        Task { await LibraryStore.shared.toggleStar(.album, id: albumID, isStarred: isStarred) }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
            }
        } content: {
            if !songs.isEmpty {
                SongList(songs: songs, context: .album(id: albumID), showsTrackNumbers: true, groupsByDisc: true)
            } else if failed {
                ContentUnavailableView("Couldn’t load this album", systemImage: "wifi.exclamationmark")
            } else {
                ProgressView().padding(40)
            }
        }
        .navigationTitle(shown?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu("More", systemImage: "ellipsis") {
                if let shown { AlbumMenu(album: shown) }
                AddToPlaylistMenu(songIDs: songs.map(\.id))
            }
        }
        .task(id: albumID) {
            do {
                album = try await SubsonicClient.shared.getAlbum(id: albumID)
            } catch {
                failed = true
                Messages.shared.showFailure("load the album", error)
            }
        }
    }

    private var detailLine: String? {
        guard let shown else { return nil }
        let count = songs.isEmpty ? shown.songCount : songs.count
        return [shown.year.map(String.init), shown.genre, count.map { $0.counted("song") },
                shown.duration.map { durationText(seconds: $0) }].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Artist

struct ArtistDetailView: View {
    let artistID: String
    let preview: Artist?
    @State private var artist: Artist?
    @State private var albums: [Album] = []
    @State private var topSongs: [Song] = []
    @State private var isFetching = false

    private var shown: Artist? { artist ?? preview }
    private var isStarred: Bool {
        LibraryStore.shared.isStarred(.artist, id: artistID, fetched: shown?.starred)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                DetailHeader(coverArt: shown?.coverArt, placeholder: "music.mic", round: true,
                             title: shown?.name ?? "", detail: (shown?.albumCount ?? albums.count).counted("album")) {
                    HStack(spacing: 12) {
                        PlayShuffleButtons(play: { Task { await playAll(shuffle: false) } },
                                           shuffle: { Task { await playAll(shuffle: true) } },
                                           isBusy: isFetching || albums.isEmpty, context: .artist(id: artistID))
                        Button(isStarred ? "Remove from Favourites" : "Add to Favourites",
                               systemImage: isStarred ? "heart.fill" : "heart") {
                            Task { await LibraryStore.shared.toggleStar(.artist, id: artistID, isStarred: isStarred) }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                    .frame(maxWidth: 480)
                }

                if !topSongs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Top Songs", subtitle: "Their most popular tracks")
                        SongList(songs: topSongs)
                    }
                }
                if !albums.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Albums")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                            ForEach(albums) { AlbumCard(album: $0) }
                        }
                    }
                }
            }
            .padding()
        }
        .appBackground()
        .navigationTitle(shown?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: artistID) { await load() }
    }

    private func load() async {
        async let artist = SubsonicClient.shared.getArtist(id: artistID)
        async let albums = SubsonicClient.shared.getArtistAlbums(artistId: artistID)
        do {
            self.albums = try await albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        } catch {
            Messages.shared.showFailure("load the artist’s albums", error)
        }
        self.artist = try? await artist
        if let name = shown?.name {
            topSongs = Array(((try? await SubsonicClient.shared.getTopSongs(artist: name, count: 5)) ?? []).prefix(5))
        }
    }

    /// Every album, oldest first and in track order.
    private func playAll(shuffle: Bool) async {
        isFetching = true
        defer { isFetching = false }
        var songs: [Song] = []
        for album in albums.reversed() {
            songs += (try? await SubsonicClient.shared.getAlbum(id: album.id).songs) ?? []
        }
        Playback.play(songs, shuffle: shuffle, context: .artist(id: artistID))
    }
}

// MARK: - Playlist

struct PlaylistDetailView: View {
    let playlist: Playlist
    @State private var loaded: Playlist?

    private var songs: [Song] { loaded?.songs ?? [] }

    var body: some View {
        DetailLayout {
            DetailHeader(coverArt: playlist.coverArt, placeholder: "music.note.list", title: loaded?.name ?? playlist.name,
                         subtitleText: playlist.comment, detail: (loaded ?? playlist).summary) {
                PlayShuffleRow(play: { Playback.play(songs, shuffle: false, context: .playlist(id: playlist.id)) },
                               shuffle: { Playback.play(songs, shuffle: true, context: .playlist(id: playlist.id)) },
                               isBusy: loaded == nil, context: .playlist(id: playlist.id)) {
                    CollectionDownloadButton(collection: loaded.map { $0.downloadCollection(songs: songs) }, songs: songs)
                }
                .frame(maxWidth: 540)
            }
        } content: {
            if loaded == nil {
                ProgressView().padding(40)
            } else if songs.isEmpty {
                ContentUnavailableView("This playlist is empty", systemImage: "music.note.list")
            } else {
                SongList(songs: songs, context: .playlist(id: playlist.id))
            }
        }
        .navigationTitle(loaded?.name ?? playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: playlist.id) {
            do {
                loaded = try await SubsonicClient.shared.getPlaylist(id: playlist.id)
            } catch {
                Messages.shared.showFailure("load the playlist", error)
            }
        }
    }
}

// MARK: - Genre

struct GenreDetailView: View {
    let genre: Genre
    @State private var albums: [Album] = []
    @State private var isFetching = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(genre.value).font(.largeTitle.bold())
                    Text(genre.countsText).foregroundStyle(Palette.secondaryText)
                }
                PlayShuffleButtons(play: { Task { await play(shuffle: false) } },
                                   shuffle: { Task { await play(shuffle: true) } }, isBusy: isFetching,
                                   context: .genre(name: genre.value))
                    .frame(maxWidth: 480)
                if !albums.isEmpty {
                    SectionHeader(title: "Albums")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                        ForEach(albums) { AlbumCard(album: $0) }
                    }
                }
            }
            .padding()
        }
        .appBackground()
        .navigationTitle(genre.value)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: genre.value) {
            do {
                albums = try await SubsonicClient.shared.getAlbumsByGenre(genre: genre.value)
            } catch {
                Messages.shared.showFailure("load \(genre.value) albums", error)
            }
        }
    }

    /// Play: the genre's songs in the server's order. Shuffle: a random pick
    /// from the whole genre. Either way the mix carries on in the genre.
    private func play(shuffle: Bool) async {
        isFetching = true
        defer { isFetching = false }
        do {
            let songs = shuffle
                ? try await SubsonicClient.shared.getRandomSongs(size: 200, genre: genre.value)
                : try await SubsonicClient.shared.getSongsByGenre(genre: genre.value, count: 200)
            Playback.play(songs, shuffle: shuffle, context: .genre(name: genre.value))
        } catch {
            Messages.shared.showFailure("play \(genre.value)", error)
        }
    }
}
