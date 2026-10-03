// Views/SongsView.swift
import SwiftUI
import Combine
import os

struct SongsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = SongsViewModel()
    @State private var playlists: [Playlist] = []
    @ObservedObject private var player = AudioPlayerService.shared

    var body: some View {
        NavigationStack {
            if vm.isLoading && vm.songs.isEmpty {
                FocusableProgressView(title: "Loading songs...")
            } else if vm.songs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: vm.error == nil ? "music.note" : "wifi.exclamationmark")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text(vm.error == nil ? "No songs" : "Couldn’t load songs").font(.title)
                    Text(vm.error ?? "No songs were found on the server.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    // Also keeps something focusable on screen, so Menu
                    // reaches the sidebar instead of exiting the app.
                    Button {
                        Task { await vm.reload() }
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(AccentPillButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 16) {
                            Button {
                                appState.player.isShuffled = false
                                appState.player.load(songs: vm.songs, startIndex: 0)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            Button {
                                appState.player.isShuffled = false
                                appState.player.load(songs: vm.songs, startIndex: 0)
                                appState.player.toggleShuffle()
                            } label: {
                                Label("Shuffle play", systemImage: "shuffle")
                            }
                        }
                        .buttonStyle(AccentPillButtonStyle())
                        .padding(.horizontal, AppLayout.horizontalPadding)

                        LazyVStack(spacing: 2) {
                            ForEach(Array(vm.songs.enumerated()), id: \.element.id) { idx, song in
                                SongRow(song: song, index: idx, contextSongs: vm.songs, playlists: playlists, showTrackNumber: false)
                            }

                            if vm.hasMore {
                                Button {
                                    Task { await vm.loadNextPage() }
                                } label: {
                                    if vm.isLoading {
                                        ProgressView().padding()
                                    } else {
                                        Text("Load more")
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .cardSurface(cornerRadius: 10)
                                    }
                                }
                                .buttonStyle(CardlessButtonStyle())
                                .padding(.top, 20)
                                .onAppear { Task { await vm.loadNextPage() } }
                            }
                        }
                        .padding(.horizontal, AppLayout.horizontalPadding)
                        .padding(.bottom, 120)
                    }
                    .padding(.top, AppLayout.contentTopPadding)
                }
            }
        }
        .task {
            if vm.songs.isEmpty { await vm.loadNextPage() }
            playlists = (try? await SubsonicClient.shared.getPlaylists()) ?? []
        }
    }
}

@MainActor
class SongsViewModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published var isLoading = false
    @Published var hasMore = true
    /// Message from the last failed load, shown when there are no songs.
    @Published var error: String?

    private var currentOffset = 0
    private let pageSize = 1000
    private let fixedQuery = "" // empty query to match everything

    /// Starts over from the first page.
    func reload() async {
        guard !isLoading else { return }
        songs = []
        currentOffset = 0
        hasMore = true
        await loadNextPage()
    }

    func loadNextPage() async {
        guard !isLoading && hasMore else { return }
        
        isLoading = true
        defer { isLoading = false }
        error = nil

        do {
            let result = try await SubsonicClient.shared.search(
                query: fixedQuery,
                artistCount: 0,
                albumCount: 0,
                songCount: pageSize,
                songOffset: currentOffset,
                server: nil
            )
            
            let newSongs = result.songs
            if newSongs.isEmpty {
                hasMore = false
                return
            }
            
            self.songs.append(contentsOf: newSongs)
            self.currentOffset += pageSize
            
            if newSongs.count < pageSize {
                hasMore = false
            }
        } catch {
            // Only the localized description: a URLError's full description
            // includes the request URL, which carries the auth token and salt.
            Logger(subsystem: "com.wonderworks.earsonics", category: "library")
                .error("Failed to fetch paginated tracks: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
        }
    }
}
