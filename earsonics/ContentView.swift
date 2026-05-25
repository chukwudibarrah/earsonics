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
        case home, artists, songs, playlists, starred, search, settings
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main tab view — disabled when Now Playing is active so its
            // buttons are removed from the tvOS focus chain entirely
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem { Text("Home") }
                    .tag(Tab.home)

                ArtistsView()
                    .tabItem { Text("Artists") }
                    .tag(Tab.artists)

                SongsView()
                    .tabItem { Text("Songs") }
                    .tag(Tab.songs)

                PlaylistsView()
                    .tabItem { Text("Playlists") }
                    .tag(Tab.playlists)

                StarredView()
                    .tabItem { Text("Favourites") }
                    .tag(Tab.starred)
                
                SettingsView()
                    .tabItem { Text("Settings") }
                    .tag(Tab.settings)

                SearchView(goHome: { selectedTab = .home })
                    .tabItem { Text("Search") }
                    .tag(Tab.search)

            }
            .tabViewStyle(.sidebarAdaptable)
            .environmentObject(appState)
            .disabled(showNowPlaying) // remove from focus chain when player is open

            // Mini player — top-left corner, aligned with tab bar
            if player.currentSong != nil && !showNowPlaying {
                MiniPlayerBar(onTap: { withAnimation { showNowPlaying = true } })
                    .environmentObject(appState)
                    .padding(.top, 60)
//                    .padding(.leading, 50)
                    .zIndex(10)
                    .transition(.opacity)
                    .disabled(showNowPlaying)
            }

            // Full-screen Now Playing overlay
            // .disabled(false) on this layer so its buttons ARE in the focus chain
            if showNowPlaying {
                NowPlayingView(dismiss: { withAnimation { showNowPlaying = false } })
                    .environmentObject(appState)
                    .zIndex(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onExitCommand {
                        withAnimation { showNowPlaying = false }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.28), value: showNowPlaying)
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
