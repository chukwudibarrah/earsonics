// Views/GenresView.swift
import SwiftUI
import EarsonicsCore

/// Every genre on the server, largest first. Opens a genre's page by value
/// (see SettingsView/HomeView for why pages never use `NavigationLink { }`).
struct GenresView: View {
    @Environment(AppState.self) var appState
    @State private var genres: [Genre] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var navPath = NavigationPath()
    @State private var covers = GenreCovers()

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if isLoading && genres.isEmpty {
                    FocusableProgressView(title: "Loading genres...")
                } else if genres.isEmpty {
                    // Keeps something focusable on screen, so Menu reaches the
                    // sidebar instead of exiting the app.
                    VStack(spacing: 16) {
                        Image(systemName: loadFailed ? "wifi.exclamationmark" : "guitars")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text(loadFailed ? "Couldn’t load genres" : "No genres").font(.title)
                        Text(loadFailed ? "Check the server in Settings." : "Your server hasn’t found genre tags in your music.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            Task { await load() }
                        } label: {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(AccentPillButtonStyle())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 40)], spacing: 40) {
                            ForEach(genres) { genre in
                                NavigationLink(value: genre) {
                                    GenreTile(genre: genre, coverArt: covers.coverArt[genre.value])
                                }
                                .buttonStyle(CardlessButtonStyle())
                                // Only for tiles on screen (the grid is lazy).
                                .task { await covers.load(genre.value) }
                            }
                        }
                        .padding(.top, AppLayout.contentTopPadding + 20)
                        .padding(.horizontal, AppLayout.horizontalPadding)
                        .padding(.bottom, 100)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Genre.self) { genre in
                GenreDetailView(genre: genre)
            }
            .navigationDestination(for: Album.self) { album in
                AlbumDetailView(album: album)
            }
        }
        .task { if genres.isEmpty { await load() } }
    }

    private func load() async {
        isLoading = true
        do {
            genres = try await SubsonicClient.shared.getGenres()
                .filter { ($0.songCount ?? 0) > 0 }
                .sorted { ($0.songCount ?? 0, $1.value) > ($1.songCount ?? 0, $0.value) }
            loadFailed = false
        } catch {
            loadFailed = true
            Messages.shared.showFailure("load genres", error)
        }
        isLoading = false
    }
}

/// A genre's name and size, with one of its album covers: sharp on the
/// left, blurred and darkened behind the text.
struct GenreTile: View {
    let genre: Genre
    let coverArt: String?

    var body: some View {
        HStack(spacing: 24) {
            Group {
                if let coverArt {
                    CoverArtView(id: coverArt, size: 300)
                } else {
                    Image(systemName: "guitars")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, height: 180)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text(genre.value)
                    .font(.title3).bold()
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(GenreTile.counts(genre))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, 20)
        // Fills its grid column, so the grid lines up with other pages' margins.
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 180, alignment: .leading)
        .background {
            if let coverArt {
                CoverArtView(id: coverArt, size: 300)
                    .blur(radius: 40)
                    .overlay(Color.black.opacity(0.45))
                    .clipped()
            }
        }
        .cardSurface()
    }

    static func counts(_ genre: Genre) -> String { genre.countsText }
}

/// A genre's page: Play and Shuffle for its songs, and its albums.
struct GenreDetailView: View {
    let genre: Genre
    private let player = AudioPlayerService.shared
    @State private var albums: [Album] = []
    @State private var isLoadingAlbums = true
    @State private var isFetchingSongs = false

    /// Songs fetched for Play / Shuffle (a genre can have thousands; when
    /// these run out, autoplay carries on with more from the genre).
    private static let batch = 200

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(genre.value).font(.largeTitle).bold()
                    Text(GenreTile.counts(genre)).foregroundColor(.secondary)
                    HStack(spacing: 20) {
                        Button {
                            Task { await play(shuffle: false) }
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        Button {
                            Task { await play(shuffle: true) }
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                        }
                        if isFetchingSongs { ProgressView().controlSize(.small) }
                    }
                    .buttonStyle(AccentPillButtonStyle())
                    .disabled(isFetchingSongs)
                }

                if isLoadingAlbums {
                    ProgressView().frame(maxWidth: .infinity)
                } else if !albums.isEmpty {
                    Text("Albums").font(.title2).fontWeight(.medium)
                        .foregroundColor(.primary.opacity(0.28))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 350), spacing: 10)], spacing: 50) {
                        ForEach(albums) { album in
                            // By value: resolved by the Genres tab's stack.
                            NavigationLink(value: album) {
                                AlbumCard(album: album)
                            }
                            .buttonStyle(CardlessButtonStyle())
                        }
                    }
                }
            }
            .padding(.top, AppLayout.detailTopPadding)
            .padding(.horizontal, AppLayout.horizontalPadding)
            .padding(.bottom, 30)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            isLoadingAlbums = true
            do {
                albums = try await SubsonicClient.shared.getAlbumsByGenre(genre: genre.value)
            } catch {
                Messages.shared.showFailure("load \(genre.value) albums", error)
            }
            isLoadingAlbums = false
        }
    }

    /// Play: the genre's songs in the server's order. Shuffle: a random pick
    /// from the whole genre, not just its first songs.
    private func play(shuffle: Bool) async {
        isFetchingSongs = true
        defer { isFetchingSongs = false }
        do {
            let songs = shuffle
                ? try await SubsonicClient.shared.getRandomSongs(size: Self.batch, genre: genre.value)
                : try await SubsonicClient.shared.getSongsByGenre(genre: genre.value, count: Self.batch)
            guard !songs.isEmpty else {
                Messages.shared.show("No songs found in \(genre.value)")
                return
            }
            player.load(songs: songs, startIndex: 0, shuffle: shuffle, context: .genre(name: genre.value))
        } catch {
            Messages.shared.showFailure("play \(genre.value)", error)
        }
    }
}
