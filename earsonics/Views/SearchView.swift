// Views/SearchView.swift
import SwiftUI

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var query: String = ""
    @State private var results: SearchResult = SearchResult(artists: [], albums: [], songs: [])
    @State private var isSearching = false
    @State private var selectedAlbum: Album? = nil
    @State private var selectedArtist: Artist? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search songs, albums, artists...", text: $query)
                        .font(.title3)
                        .autocapitalization(.none)
                        .onChange(of: query) { newValue in
                            searchTask?.cancel()
                            guard !newValue.isEmpty else {
                                results = SearchResult(artists: [], albums: [], songs: [])
                                return
                            }
                            searchTask = Task {
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                guard !Task.isCancelled else { return }
                                await performSearch(query: newValue)
                            }
                        }
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    if isSearching { ProgressView().scaleEffect(0.8) }
                }
                .padding(16)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal, 60)
                .padding(.top, 20)

                if query.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60)).foregroundColor(.secondary)
                        Text("Search your library").font(.title).foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            if !results.artists.isEmpty {
                                ResultSection(title: "Artists") {
                                    ForEach(results.artists) { artist in
                                        ArtistRow(artist: artist)
                                            .onTapGesture { selectedArtist = artist }
                                    }
                                }
                            }
                            if !results.albums.isEmpty {
                                ResultSection(title: "Albums") {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 24) {
                                            ForEach(results.albums) { album in
                                                AlbumCard(album: album)
                                                    .onTapGesture { selectedAlbum = album }
                                            }
                                        }
                                        .padding(.horizontal, 4)
                                    }
                                }
                            }
                            if !results.songs.isEmpty {
                                ResultSection(title: "Songs") {
                                    ForEach(Array(results.songs.enumerated()), id: \.element.id) { idx, song in
                                        SongRow(song: song, index: idx) {
                                            appState.player.load(songs: results.songs, startIndex: idx)
                                        }
                                    }
                                }
                            }
                            if results.artists.isEmpty && results.albums.isEmpty && results.songs.isEmpty && !isSearching {
                                VStack(spacing: 16) {
                                    Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundColor(.secondary)
                                    Text("No results for \"\(query)\"").foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.vertical, 30)
                    }
                }
            }
            .navigationTitle("Search")
            .navigationDestination(item: $selectedAlbum) { AlbumDetailView(album: $0) }
            .navigationDestination(item: $selectedArtist) { ArtistDetailView(artist: $0) }
        }
    }

    private func performSearch(query: String) async {
        isSearching = true
        results = (try? await SubsonicClient.shared.search(query: query))
            ?? SearchResult(artists: [], albums: [], songs: [])
        isSearching = false
    }
}

struct ResultSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3).bold()
            content
        }
    }
}
