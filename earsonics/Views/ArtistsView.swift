// Views/ArtistsView.swift
import SwiftUI

struct ArtistsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = LibraryViewModel()
    @State private var searchText: String = ""

    var filtered: [Artist] {
        searchText.isEmpty ? vm.artists : vm.artists.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            if vm.isLoading && vm.artists.isEmpty {
                ProgressView("Loading artists...")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { artist in
                            NavigationLink {
                                ArtistDetailView(artist: artist)
                                    .environmentObject(appState)
                            } label: {
                                ArtistRow(artist: artist)
                            }
                            .buttonStyle(CardlessButtonStyle())
                        }
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, AppLayout.horizontalPadding)
                    .padding(.bottom, 100)
                }
                .searchable(text: $searchText, prompt: "Search artists")
            }
        }
        .task { if vm.artists.isEmpty { await vm.loadHome() } }
    }
}

struct ArtistRow: View {
    let artist: Artist
    
    var body: some View {
        HStack(spacing: 20) {
            CoverArtView(id: artist.coverArt, size: 100)
                .frame(width: 60, height: 60)
                .cornerRadius(6)
            VStack(alignment: .leading, spacing: 10) {
                Text(artist.name)
                    .font(.caption2).bold(true)
                if let count = artist.albumCount {
                    Text("\(count) albums")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.callout)
        }
        .padding()
        .cardSurface()
    }
}

// MARK: - Artist Detail
struct ArtistDetailView: View {
    let artist: Artist
    @EnvironmentObject var appState: AppState
    @ObservedObject private var player = AudioPlayerService.shared
    @Environment(\.appAccent) private var appAccent
    @State private var albums: [Album] = []
    @State private var isLoading = true
    @State private var isStarred: Bool
    @State private var isFetchingTracks = false
    @State private var fetchErrorOccurred = false
    
    init(artist: Artist) {
        self.artist = artist
        _isStarred = State(initialValue: artist.starred != nil)
    }
    
    var isThisArtistPlaying: Bool {
        player.currentSong?.artistId == artist.id
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Background artist name watermark
            Text(artist.name)
                .font(.system(size: 200, weight: .black))
                .foregroundColor(.white.opacity(0.05))
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    // Header
                    HStack(spacing: 50) {
                        CoverArtView(id: artist.coverArt, size: 400)
                            .frame(width: 200, height: 200)
                            .cornerRadius(100)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text(artist.name).font(.largeTitle).bold()
                            if let count = artist.albumCount {
                                Text("\(count) albums").foregroundColor(.secondary)
                            }
                            HStack(spacing: 20) {
                                Button {
                                    playOrShuffleArtistDiscography(shuffle: false)
                                } label: {
                                    if isFetchingTracks {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("Play all", systemImage: "play.fill")
                                    }
                                }
                                .disabled(isFetchingTracks)
                                
                                Button {
                                    playOrShuffleArtistDiscography(shuffle: true)
                                } label: {
                                    if isFetchingTracks {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("Shuffle", systemImage: "shuffle")
                                    }
                                }
                                .disabled(isFetchingTracks)
                                
                                StarButton(isStarred: isStarred, artistId: artist.id) { newVal in
                                    isStarred = newVal
                                }
                            }
                            .buttonStyle(AccentPillButtonStyle())
                        }
                        Spacer()
                    }
                    
                    // Albums grid
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 350), spacing: 10)], spacing: 50) {
                            ForEach(albums) { album in
                                NavigationLink {
                                    AlbumDetailView(album: album)
                                } label: {
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
            .task {
                isLoading = true
                albums = (try? await SubsonicClient.shared.getArtistAlbums(artistId: artist.id)) ?? []
                isLoading = false
            }
        }
        .alert("Connection issue", isPresented: $fetchErrorOccurred) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Could not load the full artist discography. Please check your server connection and try again.")
        }
    }
    
    // MARK: - Lazy-fetch discography then play/shuffle
    private func playOrShuffleArtistDiscography(shuffle: Bool) {
        guard !albums.isEmpty else { return }
        isFetchingTracks = true
        fetchErrorOccurred = false
        
        Task {
            var allTracks: [Song] = []
            var successfulFetches = 0
            
            let chunks = stride(from: 0, to: albums.count, by: 5).map {
                Array(albums[$0..<min($0 + 5, albums.count)])
            }
            
            for chunk in chunks {
                await withTaskGroup(of: [Song]?.self) { group in
                    for album in chunk {
                        group.addTask {
                            (try? await SubsonicClient.shared.getAlbum(id: album.id))?.songs
                        }
                    }
                    for await songs in group {
                        if let songs = songs {
                            allTracks.append(contentsOf: songs)
                            successfulFetches += 1
                        }
                    }
                }
            }
            
            let successRate = Double(successfulFetches) / Double(albums.count)
            
            await MainActor.run {
                isFetchingTracks = false
                guard successRate >= 0.5 && !allTracks.isEmpty else {
                    fetchErrorOccurred = true
                    return
                }
                
                let sorted = allTracks.sorted {
                    ($0.year ?? 0, $0.track ?? 0) < ($1.year ?? 0, $1.track ?? 0)
                }
                
                appState.player.isShuffled = shuffle
                appState.player.load(songs: sorted, startIndex: 0)
            }
        }
    }
}

