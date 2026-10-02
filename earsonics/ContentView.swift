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
    @State private var selectedTab: AppTab = .home
    @State private var showNowPlaying = false

    enum AppTab: Hashable {
        case home, artists, songs, playlists, starred, search, settings
    }

    var body: some View {
        ZStack {
            // Sidebar navigation: collapses to an icon rail while browsing,
            // expands with labels when focus moves onto it
            // Library tabs are keyed to the active server: switching servers
            // recreates them, discarding the previous library's data and
            // navigation stacks so they reload from the new server. Settings
            // is deliberately not keyed — the switch happens from inside it.
            TabView(selection: $selectedTab) {
                Tab(value: AppTab.search, role: .search) {
                    SearchView(goHome: { selectedTab = .home })
                        .id(appState.activeServerID)
                }

                Tab("Home", systemImage: "house", value: AppTab.home) {
                    HomeView()
                        .id(appState.activeServerID)
                }

                Tab("Artists", systemImage: "person", value: AppTab.artists) {
                    ArtistsView()
                        .id(appState.activeServerID)
                }

                Tab("Tracks", systemImage: "music.note", value: AppTab.songs) {
                    SongsView()
                        .id(appState.activeServerID)
                }

                Tab("Playlists", systemImage: "music.note.list", value: AppTab.playlists) {
                    PlaylistsView()
                        .id(appState.activeServerID)
                }

                Tab("Favourites", systemImage: "bookmark", value: AppTab.starred) {
                    StarredView()
                        .id(appState.activeServerID)
                }

                Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                    SettingsView()
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .environmentObject(appState)
            // Fixed-height top strip hosting the now-playing pill so content
            // never jumps when playback starts or stops
            .safeAreaInset(edge: .top) {
                ZStack(alignment: .trailing) {
                    Color.clear
                    if player.currentSong != nil && !showNowPlaying {
                        MiniPlayerBar(onTap: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showNowPlaying = true
                            }
                        })
                        .environmentObject(appState)
                        .padding(.trailing, AppLayout.horizontalPadding)
                        .transition(.opacity)
                    }
                }
                .frame(height: AppLayout.topStripHeight)
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
        // No global .tint(): buttons stay neutral while idle and only take
        // the accent when focused (AccentPillButtonStyle / accentFocusRing)
        .environment(\.appAccent, appState.accentColor)
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
