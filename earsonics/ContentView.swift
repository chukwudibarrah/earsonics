//
//  ContentView.swift
//  earsonics
//
//  Created by MacDaddy on 02/05/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @State private var showNowPlaying = false
    @State private var selectedTab: Tab = .home

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

            // Mini player bar (visible when something is loaded)
            if appState.player.currentSong != nil && !showNowPlaying {
                MiniPlayerBar(showNowPlaying: $showNowPlaying)
                    .environmentObject(appState)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.player.currentSong?.id)
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
                .environmentObject(appState)
        }
        // If no servers configured, go straight to settings
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
