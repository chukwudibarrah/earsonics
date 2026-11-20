// earsonics-iOS/Home/HomeView.swift
import SwiftUI
import EarsonicsCore

/// What Home shows. Each list loads on its own, so a slow one never holds up
/// the rest.
@MainActor @Observable
final class HomeModel {
    var newest: [Album] = []
    var recent: [Album] = []
    var frequent: [Album] = []
    var random: [Album] = []
    var genres: [Genre] = []
    var starredSongs: [Song] = []
    var starredAlbums: [Album] = []
    var didLoad = false
    var failure: String?

    private let client = SubsonicClient.shared

    func load() async {
        failure = nil
        async let newest = client.getAlbumList(type: "newest", size: 20)
        async let recent = client.getAlbumList(type: "recent", size: 20)
        async let frequent = client.getAlbumList(type: "frequent", size: 20)
        async let random = client.getAlbumList(type: "random", size: 20)
        async let genres = client.getGenres()
        async let starred = client.getStarred()
        async let playlists: Void = LibraryStore.shared.loadPlaylists()

        do {
            self.newest = try await newest
        } catch {
            if Task.isCancelled { return }
            failure = error.localizedDescription
        }
        self.recent = (try? await recent) ?? []
        self.frequent = (try? await frequent) ?? []
        self.random = (try? await random) ?? []
        self.genres = ((try? await genres) ?? []).filter { ($0.songCount ?? 0) > 0 }
            .sorted { ($0.songCount ?? 0) > ($1.songCount ?? 0) }
        if let starred = try? await starred {
            starredSongs = starred.songs
            starredAlbums = starred.albums
        }
        await playlists
        didLoad = true
    }
}

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var model = HomeModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if !NetworkStatus.shared.isOnline { OfflineHint().padding(.horizontal) }
                if let failure = model.failure, model.newest.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn’t load your library", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(failure)
                    } actions: {
                        Button("Try Again") { Task { await model.load() } }.buttonStyle(.glassProminent)
                    }
                    .padding(.top, 60)
                } else if !model.didLoad {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                } else {
                    content
                }
            }
            .padding(.vertical)
        }
        .appBackground()
        .navigationTitle("Home")
        .toolbarTitleDisplayMode(.inlineLarge)
        .refreshable { await model.load() }
        .task(id: appState.activeServerID) { await model.load() }
        // Back online: fill in what couldn't load.
        .onChange(of: NetworkStatus.shared.isOnline) { _, online in
            if online, model.failure != nil { Task { await model.load() } }
        }
    }

    @ViewBuilder private var content: some View {
        HomeHero(model: model)
            .padding(.horizontal)

        QuickPicks(model: model)
            .padding(.horizontal)

        if !model.newest.isEmpty {
            Shelf(title: "Recently Added", subtitle: "Fresh arrivals from your server",
                  seeAll: .section(.recentlyAdded), items: model.newest) { AlbumCard(album: $0) }
        }
        if !model.recent.isEmpty {
            Shelf(title: "Recently Played", subtitle: "Pick up where you left off",
                  seeAll: .section(.recentlyPlayed), items: model.recent) { AlbumCard(album: $0) }
        }
        if !model.frequent.isEmpty {
            Shelf(title: "On Repeat", subtitle: "The albums you play most", items: model.frequent) { AlbumCard(album: $0) }
        }
        let playlists = LibraryStore.shared.playlists
        if !playlists.isEmpty {
            Shelf(title: "Playlists", subtitle: "Saved sets from your server",
                  seeAll: .section(.playlists), items: playlists) { PlaylistCard(playlist: $0) }
        }
        if !model.genres.isEmpty {
            Shelf(title: "Genres", subtitle: "Dive into a style", seeAll: .section(.genres),
                  items: Array(model.genres.prefix(12)), minCardWidth: 260) { genre in
                GenreCard(genre: genre, coverArt: nil, showsCover: false)
            }
        }
        if !model.random.isEmpty {
            Shelf(title: "Discover", subtitle: "Something you haven’t played in a while", items: model.random) { AlbumCard(album: $0) }
        }
    }
}

/// The summary card at the top of Home: a greeting and a few counts that
/// open the matching part of the library.
private struct HomeHero: View {
    let model: HomeModel
    @Environment(AppState.self) private var appState

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text((appState.serverStore.activeServer?.name ?? "Your library").uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
                Text(greeting).font(.largeTitle.bold())
                Text("Your favourites, new arrivals and latest listening, all in one place.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
            }
            HStack(spacing: 10) {
                stat(model.starredSongs.count, "Favourites", .favourites)
                stat(LibraryStore.shared.playlists.count, "Playlists", .playlists)
                stat(model.genres.count, "Genres", .genres)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.28), Palette.card],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Palette.hairline) }
    }

    private func stat(_ value: Int, _ label: String, _ section: LibrarySection) -> some View {
        NavigationLink(value: Route.section(section)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(value.formatted()).font(.title3.bold())
                Text(label).font(.caption).foregroundStyle(Palette.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Palette.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// Big cards for the two places people go most. (Recently added and genres
/// have their own shelves below.)
private struct QuickPicks: View {
    let model: HomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Quick Picks", subtitle: "Jump back into the music you reach for most")
            // Two across on a phone; card-sized (not stretched) when wider.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 14, alignment: .top)],
                      alignment: .leading, spacing: 14) {
                pick(.favourites, cover: model.starredAlbums.first?.coverArt ?? model.starredSongs.first?.coverArt,
                     detail: model.starredSongs.count.counted("favourite song"))
                pick(.recentlyPlayed, cover: model.recent.first?.coverArt, detail: "Your latest listening")
            }
        }
    }

    private func pick(_ section: LibrarySection, cover: String?, detail: String) -> some View {
        NavigationLink(value: Route.section(section)) {
            VStack(alignment: .leading, spacing: 10) {
                Artwork(id: cover, placeholderSymbol: section.systemImage)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: section.systemImage)
                            .font(.footnote.weight(.bold))
                            .padding(9)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(8)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(Palette.secondaryText).lineLimit(1)
                }
                .padding(.horizontal, 4)
            }
            .card(cornerRadius: 22, padding: 10)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
}

/// Shown on Home without a connection: downloads still play.
private struct OfflineHint: View {
    var body: some View {
        NavigationLink(value: Route.section(.downloads)) {
            HStack(spacing: 14) {
                IconTile(systemImage: "wifi.slash")
                VStack(alignment: .leading, spacing: 2) {
                    Text("You’re offline").font(.headline)
                    Text("Your downloads still play.").font(.subheadline).foregroundStyle(Palette.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.secondaryText)
            }
            .card(cornerRadius: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
