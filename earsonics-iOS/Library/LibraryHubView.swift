// earsonics-iOS/Library/LibraryHubView.swift
import SwiftUI
import EarsonicsCore

/// Counts shown beside the Library rows. Loaded together, each one optional:
/// a server that doesn't report one just shows no pill.
@MainActor @Observable
final class LibraryCounts {
    var songs: Int?
    var artists: Int?
    var genres: Int?
    var favourites: Int?

    func load() async {
        let client = SubsonicClient.shared
        async let status = client.getScanStatus()
        async let artists = client.getArtists()
        async let genres = client.getGenres()
        async let starred = client.getStarred()
        async let playlists: Void = LibraryStore.shared.loadPlaylists()
        songs = (try? await status)?.count
        self.artists = (try? await artists)?.count
        self.genres = (try? await genres)?.filter { ($0.songCount ?? 0) > 0 }.count
        favourites = (try? await starred)?.songs.count
        await playlists
    }

    func pill(for section: LibrarySection) -> String? {
        switch section {
        case .favourites: favourites?.counted("song")
        case .songs:      songs?.counted("song")
        case .artists:    artists?.counted("artist")
        case .genres:     genres?.counted("genre")
        case .playlists:  LibraryStore.shared.playlists.count.counted("playlist")
        case .recentlyPlayed, .recentlyAdded, .albums: nil
        }
    }
}

/// The Library tab on iPhone (and on iPad in a narrow window): a summary
/// card, then the library's sections in groups.
struct LibraryHubView: View {
    @Environment(AppState.self) private var appState
    @State private var counts = LibraryCounts()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                summary
                ForEach(LibrarySection.groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: group.title, subtitle: group.subtitle)
                        VStack(spacing: 0) {
                            ForEach(Array(group.sections.enumerated()), id: \.element) { index, section in
                                if index > 0 { Divider().padding(.leading, 76) }
                                LibraryRow(section: section, count: counts.pill(for: section))
                            }
                        }
                        .card(cornerRadius: 24, padding: 8)
                    }
                }
            }
            .padding()
        }
        .appBackground()
        .navigationTitle("Library")
        .toolbarTitleDisplayMode(.inlineLarge)
        .refreshable { await counts.load() }
        .task(id: appState.activeServerID) { await counts.load() }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            Image(systemName: appState.isConnected ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(appState.isConnected ? AnyShapeStyle(.tint) : AnyShapeStyle(.orange))
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.serverStore.activeServer?.name ?? "Library").font(.headline)
                Text([counts.songs?.counted("song"), counts.artists?.counted("artist")]
                        .compactMap { $0 }.joined(separator: " · ").ifEmpty(appState.isConnected ? "Connected" : "Not connected"))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
            }
            Spacer()
        }
        .card(cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }
}

/// A Library row: icon tile, title, description, count pill and chevron.
struct LibraryRow: View {
    let section: LibrarySection
    let count: String?

    var body: some View {
        NavigationLink(value: Route.section(section)) {
            HStack(spacing: 14) {
                IconTile(systemImage: section.systemImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title).font(.headline)
                    Text(section.subtitle).font(.subheadline).foregroundStyle(Palette.secondaryText).lineLimit(2)
                }
                Spacer(minLength: 8)
                if let count { CountPill(text: count) }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
