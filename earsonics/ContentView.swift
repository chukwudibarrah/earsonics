//
//  ContentView.swift
//  earsonics
//
//  Created by MacDaddy on 02/05/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var selectedTab: Tab = .home
    @State private var showNowPlaying = false

    enum Tab: Hashable {
        case home, artists, playlists, starred, search, settings
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house.fill") }
                    .tag(Tab.home)

                ArtistsView()
                    .tabItem { Label("Artists", systemImage: "music.mic") }
                    .tag(Tab.artists)

                PlaylistsView()
                    .tabItem { Label("Playlists", systemImage: "music.note.list") }
                    .tag(Tab.playlists)

                StarredView()
                    .tabItem { Label("Favourites", systemImage: "heart.fill") }
                    .tag(Tab.starred)

                SearchView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(Tab.search)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(Tab.settings)
            }
            .environmentObject(appState)

            // Spotify-style bottom mini player
            if player.currentSong != nil {
                VStack {
                    Spacer()
                    MiniPlayerBar(onTap: { showNowPlaying = true })
                        .environmentObject(appState)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: player.currentSong?.id)
            }
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
                .environmentObject(appState)
        }
        .onAppear {
            if appState.serverStore.servers.isEmpty {
                selectedTab = .settings
            }
        }
    }
}

#Preview {
    ContentView()
}
