// earsonics-iOS/Search/SearchView.swift
import SwiftUI
import EarsonicsCore

/// Search with quick starts (genres, playlists and recent searches) while
/// the field is empty, and results grouped by kind as you type.
struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var results = SearchResult(artists: [], albums: [], songs: [])
    @State private var isSearching = false
    @State private var genres: [Genre] = []
    @AppStorage("recentSearches") private var recentStore = ""

    private var recents: [String] { recentStore.split(separator: "\n").map(String.init) }
    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if trimmed.isEmpty {
                    quickStarts
                } else if !isSearching && results.artists.isEmpty && results.albums.isEmpty && results.songs.isEmpty {
                    ContentUnavailableView.search(text: trimmed).padding(.top, 40)
                } else {
                    resultsView
                }
            }
            .padding(.vertical)
        }
        .appBackground()
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Albums, artists, songs")
        .onSubmit(of: .search) { remember(trimmed) }
        .task(id: trimmed) { await search() }
        .task(id: appState.activeServerID) {
            genres = ((try? await SubsonicClient.shared.getGenres()) ?? [])
                .filter { ($0.songCount ?? 0) > 0 }.sorted { ($0.songCount ?? 0) > ($1.songCount ?? 0) }
        }
    }

    @ViewBuilder private var quickStarts: some View {
        if !recents.isEmpty {
            chips(title: "Recent Searches", subtitle: nil, items: recents.map { ($0, "clock.arrow.circlepath", nil as Route?) },
                  clear: { recentStore = "" })
        }
        let starts: [(String, String, Route?)] =
            genres.prefix(6).map { ($0.value, "guitars", .genre($0)) } +
            LibraryStore.shared.playlists.prefix(4).map { ($0.name, "music.note.list", .playlist($0)) }
        if !starts.isEmpty {
            chips(title: "Try Searching", subtitle: "Quick starts from your library", items: starts, clear: nil)
        }
    }

    private func chips(title: String, subtitle: String?, items: [(String, String, Route?)], clear: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: title, subtitle: subtitle)
                if let clear { Button("Clear", action: clear).font(.subheadline) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                ForEach(items, id: \.0) { item in
                    Group {
                        if let route = item.2 {
                            NavigationLink(value: route) { chipLabel(item.0, item.1) }
                        } else {
                            Button { query = item.0 } label: { chipLabel(item.0, item.1) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }

    private func chipLabel(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder private var resultsView: some View {
        if !results.artists.isEmpty {
            Shelf(title: "Artists", items: results.artists, minCardWidth: 110) { artist in
                NavigationLink(value: Route.artist(artist)) {
                    VStack(spacing: 8) {
                        Artwork(id: artist.coverArt, pixels: 240, cornerRadius: 200, placeholderSymbol: "music.mic")
                            .aspectRatio(1, contentMode: .fit)
                        Text(artist.name).font(.subheadline.weight(.medium)).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        if !results.albums.isEmpty {
            Shelf(title: "Albums", items: results.albums) { AlbumCard(album: $0) }
        }
        if !results.songs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Songs")
                SongList(songs: results.songs)
            }
            .padding(.horizontal)
        }
    }

    private func search() async {
        let text = trimmed
        guard !text.isEmpty else {
            results = SearchResult(artists: [], albums: [], songs: [])
            return
        }
        isSearching = true
        defer { isSearching = false }
        // Wait for typing to pause; a newer keystroke cancels this task.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            results = try await SubsonicClient.shared.search(query: text, artistCount: 12, albumCount: 16, songCount: 30)
        } catch {
            Messages.shared.showFailure("search", error)
        }
    }

    /// Keeps the last eight searches, newest first.
    private func remember(_ text: String) {
        guard !text.isEmpty else { return }
        recentStore = ([text] + recents.filter { $0.caseInsensitiveCompare(text) != .orderedSame })
            .prefix(8).joined(separator: "\n")
    }
}
