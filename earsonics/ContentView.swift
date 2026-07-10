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
            TabView(selection: $selectedTab) {
                Tab(value: AppTab.search, role: .search) {
                    SearchView(goHome: { selectedTab = .home })
                }

                Tab("Home", systemImage: "house", value: AppTab.home) {
                    HomeView()
                }

                Tab("Artists", systemImage: "person", value: AppTab.artists) {
                    ArtistsView()
                }

                Tab("Tracks", systemImage: "music.note", value: AppTab.songs) {
                    SongsView()
                }

                Tab("Playlists", systemImage: "music.note.list", value: AppTab.playlists) {
                    PlaylistsView()
                }

                Tab("Favourites", systemImage: "bookmark", value: AppTab.starred) {
                    StarredView()
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
