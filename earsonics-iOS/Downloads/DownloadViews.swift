// earsonics-iOS/Downloads/DownloadViews.swift
import SwiftUI
import EarsonicsCore

/// Whether the device is online, for screens to react to.
@MainActor @Observable
final class NetworkStatus {
    static let shared = NetworkStatus()
    private(set) var isOnline = NetworkMonitor.shared.isOnline

    private init() {
        NetworkMonitor.shared.observe { status in
            Task { @MainActor in NetworkStatus.shared.isOnline = status.isOnline }
        }
    }
}

/// Download, progress and remove for an album or playlist page, next to its
/// play buttons. Tapping while it downloads or once it's done offers Remove.
struct CollectionDownloadButton: View {
    let collection: DownloadedCollection?
    let songs: [Song]
    @State private var confirmsRemove = false
    private let store = DownloadStore.shared

    var body: some View {
        let server = SubsonicClient.shared.server
        let saved = collection.flatMap { c in server.flatMap { store.collection(c.kind, id: c.id, serverID: $0.id) } }
        let progress = saved.flatMap { c in server.map { store.completion(of: c, serverID: $0.id) } }
        Group {
            if let saved, let server, let progress {
                Button {
                    confirmsRemove = true
                } label: {
                    if progress.done == progress.total {
                        Label("Downloaded", systemImage: "arrow.down.circle.fill")
                    } else {
                        Label {
                            Text("Downloading \(progress.done) of \(progress.total)")
                        } icon: {
                            DownloadRing(fraction: Double(progress.done) / Double(max(progress.total, 1)))
                        }
                    }
                }
                .confirmationDialog("Remove the download?", isPresented: $confirmsRemove, titleVisibility: .visible) {
                    Button("Remove Download", role: .destructive) { store.remove(saved, serverID: server.id) }
                } message: {
                    Text("It stays in your library to stream.")
                }
            } else {
                Button("Download", systemImage: "arrow.down.circle") {
                    guard let collection, let server else { return }
                    store.download(songs, as: collection, server: server)
                }
                .disabled(songs.isEmpty || collection == nil)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .controlSize(.large)
        .accessibilityIdentifier("downloadButton")
    }
}

/// A small ring that fills as a download goes.
struct DownloadRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.35), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.04, fraction))
                .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: fraction)
        }
        .frame(width: 18, height: 18)
    }
}

/// A song row's download mark: a filled arrow once downloaded, a ring while
/// it downloads, nothing otherwise.
struct SongDownloadBadge: View {
    let songId: String

    var body: some View {
        if let server = SubsonicClient.shared.server {
            switch DownloadStore.shared.state(songId: songId, serverID: server.id) {
            case .downloaded:
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .accessibilityLabel("Downloaded")
            case .downloading(let fraction):
                DownloadRing(fraction: fraction).scaleEffect(0.75)
                    .accessibilityLabel("Downloading")
            case .waiting:
                DownloadRing(fraction: 0).scaleEffect(0.75)
                    .accessibilityLabel("Waiting to download")
            case .failed:
                Image(systemName: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Download failed")
            case .none:
                EmptyView()
            }
        }
    }
}

/// "Download" or "Remove Download" for a song's menu.
struct SongDownloadMenuItem: View {
    let song: Song

    var body: some View {
        if let server = SubsonicClient.shared.server {
            if DownloadStore.shared.state(songId: song.id, serverID: server.id) == .none {
                Button("Download", systemImage: "arrow.down.circle") {
                    DownloadStore.shared.download([song], server: server)
                }
            } else {
                Button("Remove Download", systemImage: "minus.circle", role: .destructive) {
                    DownloadStore.shared.remove(songId: song.id, serverID: server.id)
                }
            }
        }
    }
}

extension Album {
    /// What a download of this album is recorded as.
    func downloadCollection(songs: [Song]) -> DownloadedCollection {
        DownloadedCollection(kind: .album, id: id, name: name, artist: artist, coverArt: coverArt, songIDs: songs.map(\.id))
    }
}

extension Playlist {
    func downloadCollection(songs: [Song]) -> DownloadedCollection {
        DownloadedCollection(kind: .playlist, id: id, name: name, artist: nil, coverArt: coverArt, songIDs: songs.map(\.id))
    }
}

// MARK: - The Downloads page

/// Everything downloaded from the active server: albums and playlists, then
/// every downloaded song. Works offline: nothing here asks the server.
struct DownloadsView: View {
    @State private var confirmsRemoveAll = false
    private let store = DownloadStore.shared

    var body: some View {
        Group {
            if let server = SubsonicClient.shared.server {
                content(server)
            } else {
                ContentUnavailableView("No server", systemImage: "server.rack")
            }
        }
        .appBackground()
        .navigationTitle("Downloads")
        .toolbarTitleDisplayMode(.inlineLarge)
    }

    @ViewBuilder
    private func content(_ server: Server) -> some View {
        let index = store.index(for: server.id)
        let collections = index.collections.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let songs = store.downloadedSongs(serverID: server.id)
        if index.entries.isEmpty {
            ContentUnavailableView("Nothing downloaded",
                                   systemImage: "arrow.down.circle",
                                   description: Text("Download albums, playlists and songs to play them without a connection."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    summary(index, songCount: songs.count, waiting: index.entries.count - songs.count)
                    if !collections.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Albums & Playlists")
                            VStack(spacing: 0) {
                                ForEach(Array(collections.enumerated()), id: \.element.key) { offset, collection in
                                    if offset > 0 { Divider().padding(.leading, 76) }
                                    CollectionRow(collection: collection, serverID: server.id)
                                }
                            }
                            .card(cornerRadius: 24, padding: 8)
                        }
                    }
                    if !songs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Songs", subtitle: songs.count.counted("song"))
                            PlayShuffleButtons(play: { Playback.play(songs, shuffle: false, context: .mix, source: "downloads") },
                                               shuffle: { Playback.play(songs, shuffle: true, context: .mix, source: "downloads") },
                                               source: "downloads")
                                .frame(maxWidth: 480)
                            SongList(songs: songs, source: "downloads")
                        }
                    }
                    Button("Remove All Downloads", role: .destructive) { confirmsRemoveAll = true }
                        .frame(maxWidth: .infinity)
                        .confirmationDialog("Remove all downloads?", isPresented: $confirmsRemoveAll, titleVisibility: .visible) {
                            Button("Remove All", role: .destructive) { store.removeAll(serverID: server.id) }
                        } message: {
                            Text("Frees \(bytes(index.totalBytes)). Your library isn’t changed.")
                        }
                }
                .padding()
            }
        }
    }

    private func summary(_ index: DownloadIndex, songCount: Int, waiting: Int) -> some View {
        HStack(spacing: 14) {
            IconTile(systemImage: "arrow.down.circle.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("\(songCount.counted("song")) · \(bytes(index.totalBytes))").font(.headline)
                Text(waiting > 0 ? "\(waiting.counted("song")) still to download" : "Ready to play offline")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
            }
            Spacer()
        }
        .card(cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }
}

/// A downloaded album or playlist: opens its downloaded songs.
private struct CollectionRow: View {
    let collection: DownloadedCollection
    let serverID: UUID

    var body: some View {
        let progress = DownloadStore.shared.completion(of: collection, serverID: serverID)
        NavigationLink(value: Route.downloaded(collection)) {
            HStack(spacing: 14) {
                Artwork(id: collection.coverArt, pixels: 120, cornerRadius: 10,
                        placeholderSymbol: collection.kind == .album ? "square.stack" : "music.note.list")
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.name).font(.headline).lineLimit(1)
                    Text([collection.artist ?? (collection.kind == .playlist ? "Playlist" : nil),
                          progress.done == progress.total ? progress.total.counted("song")
                                                          : "\(progress.done) of \(progress.total) downloaded"]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if progress.done < progress.total {
                    DownloadRing(fraction: Double(progress.done) / Double(max(progress.total, 1)))
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove Download", systemImage: "minus.circle", role: .destructive) {
                DownloadStore.shared.remove(collection, serverID: serverID)
            }
        }
    }
}

/// A downloaded album or playlist's songs, from the download index (so it
/// opens offline), in the album's or playlist's order.
struct DownloadedCollectionView: View {
    let collection: DownloadedCollection
    @State private var confirmsRemove = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let serverID = SubsonicClient.shared.server?.id
        let entries = serverID.map { DownloadStore.shared.index(for: $0).entries } ?? [:]
        let songs = collection.songIDs.compactMap { entries[$0]?.song }
        let context: PlayContext = collection.kind == .album ? .album(id: collection.id) : .playlist(id: collection.id)
        DetailLayout {
            DetailHeader(coverArt: collection.coverArt,
                         placeholder: collection.kind == .album ? "music.note" : "music.note.list",
                         title: collection.name, subtitleText: collection.artist,
                         detail: songs.count.counted("song")) {
                PlayShuffleButtons(play: { Playback.play(songs, shuffle: false, context: context) },
                                   shuffle: { Playback.play(songs, shuffle: true, context: context) },
                                   context: context)
                    .frame(maxWidth: 480)
            }
        } content: {
            SongList(songs: songs, context: context, showsTrackNumbers: collection.kind == .album,
                     groupsByDisc: collection.kind == .album)
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Remove Download", systemImage: "trash", role: .destructive) { confirmsRemove = true }
        }
        .confirmationDialog("Remove the download?", isPresented: $confirmsRemove, titleVisibility: .visible) {
            Button("Remove Download", role: .destructive) {
                if let serverID { DownloadStore.shared.remove(collection, serverID: serverID) }
                dismiss()
            }
        }
    }
}

/// "1.2 GB", for storage lines.
func bytes(_ count: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
}
