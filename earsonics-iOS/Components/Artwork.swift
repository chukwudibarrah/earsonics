// earsonics-iOS/Components/Artwork.swift
import SwiftUI
import EarsonicsCore

/// Cover art through the shared artwork cache (memory and disk, per server).
/// Square unless the caller frames it otherwise.
struct Artwork: View {
    let id: String?
    /// Pixels requested from the server: the largest size it's drawn at.
    var pixels: Int = 400
    var cornerRadius: CGFloat = 14
    var placeholderSymbol = "music.note"
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Palette.raised)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: placeholderSymbol)
                        .font(.title2)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: "\(id ?? "")#\(DownloadStore.shared.artworkVersion)") { await load() }
            .accessibilityHidden(true)
    }

    private func load() async {
        guard let id, let server = SubsonicClient.shared.server else {
            image = nil
            return
        }
        // A downloaded album's cover is on the device: no network needed.
        if let file = DownloadStore.shared.artworkFile(id: id, serverID: server.id) {
            let side = CGFloat(pixels)
            let saved = await Task.detached(priority: .userInitiated) { () async -> UIImage? in
                guard let full = UIImage(contentsOfFile: file.path), full.size.width > 0, full.size.height > 0 else { return nil }
                let scale = min(1, side / max(full.size.width, full.size.height))
                return await full.byPreparingThumbnail(ofSize: CGSize(width: full.size.width * scale,
                                                                      height: full.size.height * scale)) ?? full
            }.value
            if let saved {
                image = saved
                return
            }
        }
        guard let url = SubsonicClient.shared.coverArtURL(id: id, size: pixels, server: server) else {
            image = nil
            return
        }
        image = await ImageCache.shared.image(for: id, size: pixels, serverID: server.id, url: url)
    }
}

/// An album's cover, title and artist on a card. Width comes from the
/// container (a grid column or a shelf slot), so it adapts to any window.
struct AlbumCard: View {
    let album: Album

    var body: some View {
        NavigationLink(value: Route.album(album)) {
            VStack(alignment: .leading, spacing: 10) {
                Artwork(id: album.coverArt)
                    .aspectRatio(1, contentMode: .fit)
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name).font(.headline).lineLimit(1)
                    Text(album.artist ?? " ").font(.subheadline).foregroundStyle(Palette.secondaryText).lineLimit(1)
                }
                .padding(.horizontal, 4)
            }
            .card(cornerRadius: 22, padding: 10)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .contextMenu { AlbumMenu(album: album) }
        .accessibilityLabel("\(album.name), \(album.artist ?? "")")
        .accessibilityIdentifier("albumCard")
    }
}

/// A playlist's cover (servers draw it as a mosaic of its albums), name and
/// size on a card.
struct PlaylistCard: View {
    let playlist: Playlist

    var body: some View {
        NavigationLink(value: Route.playlist(playlist)) {
            VStack(alignment: .leading, spacing: 10) {
                Artwork(id: playlist.coverArt, placeholderSymbol: "music.note.list")
                    .aspectRatio(1, contentMode: .fit)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name).font(.headline).lineLimit(1)
                    Text(playlist.summary).font(.subheadline).foregroundStyle(Palette.secondaryText).lineLimit(1)
                }
                .padding(.horizontal, 4)
            }
            .card(cornerRadius: 22, padding: 10)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
}

extension Playlist {
    /// "215 songs · 14h 2m".
    var summary: String {
        let count = (songCount ?? 0).counted("song")
        guard let duration, duration > 0 else { return count }
        return "\(count) · \(durationText(seconds: duration))"
    }
}

/// A genre's name and size, beside one of its album covers.
struct GenreCard: View {
    let genre: Genre
    let coverArt: String?
    /// Off for narrow cards (the Home shelf), where a cover leaves the name
    /// no room.
    var showsCover = true

    var body: some View {
        NavigationLink(value: Route.genre(genre)) {
            HStack(spacing: 14) {
                if showsCover {
                    Artwork(id: coverArt, pixels: 240, cornerRadius: 12, placeholderSymbol: "guitars")
                        .frame(width: 72, height: 72)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(genre.value).font(.headline).lineLimit(2)
                    Text(genre.countsText).font(.subheadline).foregroundStyle(Palette.secondaryText).lineLimit(showsCover ? 1 : 2)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 72)
            .card(cornerRadius: 20, padding: showsCover ? 10 : 16)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

/// A horizontally scrolling row of cards under a section header. Card width
/// comes from the shelf's own width, so a narrow phone shows two cards and a
/// little of the next, and a wide window (iPad, unfolded iPhone Duo) more.
struct Shelf<Item: Identifiable, Card: View>: View {
    let title: String
    var subtitle: String? = nil
    var seeAll: Route? = nil
    let items: [Item]
    var minCardWidth: CGFloat = 150
    @ViewBuilder let card: (Item) -> Card

    private let spacing: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title, subtitle: subtitle, seeAll: seeAll)
                .padding(.horizontal)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: spacing) {
                    ForEach(items) { item in
                        card(item)
                            .containerRelativeFrame(.horizontal) { length, _ in cardWidth(in: length) }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    /// Fits as many cards as the minimum width allows, plus a peek of the
    /// next one so the row reads as scrollable.
    private func cardWidth(in length: CGFloat) -> CGFloat {
        let usable = length - 32
        let count = max(2, floor((usable + spacing) / (minCardWidth + spacing)))
        return (usable - spacing * count) / (count + 0.15)
    }
}
