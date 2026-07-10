// Views/SongsView.swift
import SwiftUI
import Combine

struct SongsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = SongsViewModel()
    @State private var playlists: [Playlist] = []
    @ObservedObject private var player = AudioPlayerService.shared

    var body: some View {
        NavigationStack {
            if vm.isLoading && vm.songs.isEmpty {
                ProgressView("Loading songs...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.songs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No songs").font(.title)
                    Text("No songs were found on the server.").foregroundColor(.secondary)
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
    
    private var currentOffset = 0
    private let pageSize = 1000
    private let fixedQuery = "" // empty query to match everything

    func loadNextPage() async {
        guard !isLoading && hasMore else { return }
        
        isLoading = true
        defer { isLoading = false }
        
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
            print("Failed to fetch paginated tracks: \(error)")
        }
    }
}
