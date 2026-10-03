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
    @ObservedObject private var playlistAdder = PlaylistAdder.shared
    @State private var selectedTab: AppTab = .home
    @State private var showNowPlaying = false
    @Namespace private var contentFocus
    @Environment(\.resetFocus) private var resetFocus

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
                    HomeView(isSelectedTab: selectedTab == .home)
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
            .environment(\.openSettings, OpenSettingsAction { selectedTab = .settings })
            // The now-playing pill below lives outside the tabs. Making the
            // tab area a focus section lets focus move from the pill into it
            // even when no button lines up with the pill (e.g. a sparse empty
            // state); the focus scope lets the pill hand focus back to it.
            .focusSection()
            .focusScope(contentFocus)
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
                        // Menu on the pill would otherwise reach the system
                        // and exit the app (the pill isn't inside a tab, so
                        // the sidebar never sees it). Return to the page
                        // instead; from there Menu opens the sidebar as usual.
                        .onExitCommand { resetFocus(in: contentFocus) }
                        .padding(.trailing, AppLayout.horizontalPadding)
                        .transition(.opacity)
                    }
                }
                .frame(height: AppLayout.topStripHeight)
            }
            .disabled(showNowPlaying)

            // Full-screen Now Playing overlay. It handles Menu itself,
            // stepping back through lyrics/queue before closing.
            if showNowPlaying {
                NowPlayingView(dismiss: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showNowPlaying = false
                    }
                })
                    .environmentObject(appState)
                    .zIndex(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Outcome of "Add to playlist" (see PlaylistAdder). Not focusable
            // and ignores input, so it never takes focus from the screen below.
            if let banner = playlistAdder.banner {
                VStack {
                    Spacer()
                    Text(banner)
                        .font(.callout)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 60)
                }
                .allowsHitTesting(false)
                .zIndex(30)
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showNowPlaying)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: player.currentSong != nil)
        .animation(.easeInOut(duration: 0.25), value: playlistAdder.banner)
        // No global .tint(): buttons stay neutral while idle and only take
        // the accent when focused (AccentPillButtonStyle / accentFocusRing)
        .environment(\.appAccent, appState.accentColor)
        .alert(
            playlistAdder.pending?.title ?? "",
            isPresented: Binding(
                get: { playlistAdder.pending != nil },
                set: { if !$0 { playlistAdder.pending = nil } }
            ),
            presenting: playlistAdder.pending
        ) { add in
            if add.newSongIDs.isEmpty {
                Button("Add Anyway") { playlistAdder.confirm(add, includeDuplicates: true) }
            } else {
                Button("Add \(add.newSongIDs.count) New Only") { playlistAdder.confirm(add, includeDuplicates: false) }
                Button("Add All \(add.songIDs.count)") { playlistAdder.confirm(add, includeDuplicates: true) }
            }
            Button("Cancel", role: .cancel) { playlistAdder.pending = nil }
        } message: { add in
            Text(add.message)
        }
        .onAppear {
            if appState.serverStore.servers.isEmpty {
                selectedTab = .settings
            }
        }
    }
}

/// Switches to the Settings tab — for empty states (e.g. no server
/// configured) that need to send the user there.
struct OpenSettingsAction {
    let action: () -> Void
    func callAsFunction() { action() }
}

extension EnvironmentValues {
    @Entry var openSettings = OpenSettingsAction {}
}

#Preview {
    ContentView()
}
