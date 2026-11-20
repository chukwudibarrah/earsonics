// earsonics-iOS/ContentView.swift
import SwiftUI
import EarsonicsCore

/// The app's tabs. Library is always a tab (its hub page lists the
/// sections); with room for a sidebar (iPad, an unfolded iPhone Duo) the
/// sidebar also lists the sections themselves as shortcuts.
enum AppTab: Hashable {
    case home, search, library, settings
    case section(LibrarySection)
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppearanceChoice.key) private var appearance = AppearanceChoice.defaultValue

    var body: some View {
        Group {
            if appState.serverStore.servers.isEmpty {
                NavigationStack { ServerEditView(isFirstRun: true) }
            } else {
                MainTabs()
            }
        }
        .tint(appState.accentColor)
        .environment(\.appAccent, appState.accentColor)
        .preferredColorScheme(appearance.colorScheme)
        .overlay(alignment: .top) { MessageBanner() }
    }
}

private struct MainTabs: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let player = AudioPlayerService.shared

    @State private var selection: AppTab = .home
    @State private var homePath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var libraryPath: [Route] = []
    @State private var settingsPath = NavigationPath()
    @State private var showsNowPlaying = false
    @Namespace private var nowPlayingZoom

    private var isWide: Bool { horizontalSizeClass == .regular }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack(path: $homePath) { HomeView().routeDestinations() }
            }

            Tab("Library", systemImage: "square.stack.fill", value: AppTab.library) {
                NavigationStack(path: $libraryPath) { LibraryHubView().routeDestinations() }
            }

            TabSection("Your Library") {
                ForEach(LibrarySection.allCases) { section in
                    Tab(section.title, systemImage: section.systemImage, value: AppTab.section(section)) {
                        NavigationStack { LibrarySectionView(section: section).routeDestinations() }
                    }
                    .tabPlacement(.sidebarOnly)
                }
            }
            // Sidebar only: the Library tab already covers it in the tab bar.
            .defaultVisibility(.hidden, for: .tabBar)
            .hidden(!isWide)

            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack(path: $settingsPath) { SettingsView().routeDestinations() }
            }

            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: $searchPath) { SearchView().routeDestinations() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: player.currentSong != nil) {
            MiniPlayer { showsNowPlaying = true }
                .matchedTransitionSource(id: "nowPlaying", in: nowPlayingZoom)
        }
        .fullScreenCover(isPresented: $showsNowPlaying) {
            NowPlayingView()
                .navigationTransition(.zoom(sourceID: "nowPlaying", in: nowPlayingZoom))
        }
        // Folding an iPhone Duo or narrowing an iPad window removes the
        // sidebar shortcuts: keep the person on the same part of the library
        // by opening it inside the Library tab.
        .onChange(of: isWide) { _, wide in
            if !wide, case .section(let section) = selection {
                libraryPath = [.section(section)]
                selection = .library
            }
        }
    }
}

/// The floating pill above the tab bar while something is playing. Tap it
/// to open Now Playing; its buttons work on their own.
struct MiniPlayer: View {
    let open: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    private let player = AudioPlayerService.shared

    var body: some View {
        if let song = player.currentSong {
            HStack(spacing: 12) {
                Artwork(id: song.coverArt, pixels: 120, cornerRadius: 8)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if placement != .inline {
                        Text(song.artist ?? "").font(.caption).foregroundStyle(Palette.secondaryText).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Button(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
                    player.togglePlayPause()
                }
                .font(.title3)
                if placement != .inline {
                    Button("Next", systemImage: "forward.fill") { player.skipNext() }
                        .font(.title3)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Now playing: \(song.title), \(song.artist ?? "")")
            .accessibilityAction(named: "Open Now Playing", open)
        }
    }
}

/// The app-wide message (an action's outcome, or why it failed).
private struct MessageBanner: View {
    private let messages = Messages.shared

    var body: some View {
        if let banner = messages.banner {
            Text(banner)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect()
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }
}

#Preview {
    ContentView().environment(AppState.shared)
}
