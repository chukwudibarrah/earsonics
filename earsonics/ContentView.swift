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
        ZStack {
            // Main tab view with safe area inset for mini player
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
                    .tabItem { Label("", systemImage: "magnifyingglass") }
                    .tag(Tab.search)
            }
            .environmentObject(appState)
            .safeAreaInset(edge: .top) {
                if player.currentSong != nil && !showNowPlaying {
                    HStack {
                        MiniPlayerBar(onTap: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showNowPlaying = true
                            }
                        })
                        .environmentObject(appState)
                        .padding(.leading, AppLayout.horizontalPadding)
                        Spacer()
                    }
                    .padding(.top, AppLayout.miniPlayerTopOffset)
                    .transition(.opacity)
                } else {
                    Color.clear.frame(height: 80)
                }
            }
            .disabled(showNowPlaying)

            // Full-screen Now Playing overlay
            if showNowPlaying {
                NowPlayingView(dismiss: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showNowPlaying = false
                    }
                })
                    .environmentObject(appState)
                    .zIndex(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onExitCommand {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showNowPlaying = false
                        }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showNowPlaying)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: player.currentSong != nil)
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
