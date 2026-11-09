// Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var showDonationQR = false
    @State private var cacheSize: Int64 = 0
    @State private var audioCacheSize: Int64 = 0
    @State private var isClearingCache = false

    // Audio-cache settings. Declared here (in a View)
    // rather than in AppState so their changes drive SwiftUI correctly; the
    // player and cache read the same keys live from UserDefaults.
    @AppStorage("audioCacheEnabled") private var audioCacheEnabled = true
    @AppStorage(AudioCache.limitKey) private var audioCacheLimitGB = 2

    @State private var navPath = NavigationPath()

    // Pages open by value (NavigationLink(value:) + navigationDestination).
    // `NavigationLink { destination }` left the server list/editor on screen
    // after switching tabs from the sidebar.
    var body: some View {
        NavigationStack(path: $navPath) {
            Form {
                // Server management section
                Section(header: Text("Servers").font(.headline)) {
                    NavigationLink(value: SettingsRoute.servers) {
                        HStack {
                            Label("Manage servers", systemImage: "server.rack")
                            Spacer()
                            if let server = appState.serverStore.activeServer {
                                Text(server.name).foregroundColor(.secondary).font(.callout)
                            }
                        }
                    }

                    if let server = appState.serverStore.activeServer {
                        HStack {
                            Label("Status", systemImage: appState.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(appState.isConnected ? .green : .red)
                            Spacer()
                            Text(appState.isConnected ? "Connected" : "Disconnected")
                                .foregroundColor(appState.isConnected ? .green : .red)
                        }
                        Button {
                            Task { await appState.testConnection(server: server) }
                        } label: {
                            Label("Test connection", systemImage: "arrow.clockwise")
                        }
                    }
                }
                .padding()

                // Playback section
                Section(header: Text("Playback").font(.headline)) {
                    SettingsChoiceRow(choice: .quality)
                    Text("Controls both live streaming and cached copies, so a replayed track matches its first play. Lower qualities are transcoded by the server and use less space.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Crossfade duration: \(Int(appState.crossfadeDuration))s")
                            Spacer()
                            Button("-") {
                                if appState.crossfadeDuration > 0 { appState.crossfadeDuration -= 1 }
                            }
                            .buttonStyle(.bordered)
                            Button("+") {
                                if appState.crossfadeDuration < 12 { appState.crossfadeDuration += 1 }
                            }
                            .buttonStyle(.bordered)
                        }
                        if appState.crossfadeDuration > 0 {
                            Text("Note: Overlapping streams may occasionally cause lag on wireless outputs (AirPlay/Bluetooth).")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $appState.player.normalizeVolume) {
                        Text("Normalise volume")
                    }
                    if appState.player.normalizeVolume {
                        Text("Uses Replay Gain metadata to equalise volume between tracks and prevent loud peaks.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Toggle(isOn: $appState.preventScreenSaver) {
                        Text("Disable screen saver while playing")
                    }
                    if appState.preventScreenSaver {
                        Text("Warning: Keeping the screen active for long periods may cause burn-in on some TVs.")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
                .padding()

                QueueSettingsSection()
                    .padding()

                // Appearance section
                Section(header: Text("Appearance").font(.headline)) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Highlight colour")
                        HStack(spacing: 28) {
                            ForEach(AccentColorChoice.allCases) { choice in
                                AccentSwatchButton(
                                    choice: choice,
                                    isSelected: appState.accentChoice == choice
                                ) {
                                    appState.accentChoice = choice
                                }
                            }
                        }
                        Text("Used for the focus outline, now-playing glow and play indicators.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()

                // Storage section
                Section(header: Text("Storage").font(.headline)) {
                    Toggle(isOn: $audioCacheEnabled) {
                        Text("Cache played songs")
                    }
                    if audioCacheEnabled {
                        Text("Stores tracks you play so replaying them doesn't stream again.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        HStack {
                            Text("Music cache limit: \(audioCacheLimitGB) GB")
                            Spacer()
                            Button("-") {
                                if audioCacheLimitGB > 1 { audioCacheLimitGB -= 1 }
                            }
                            .buttonStyle(.bordered)
                            Button("+") {
                                if audioCacheLimitGB < 10 { audioCacheLimitGB += 1 }
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    HStack {
                        Label("Music cache", systemImage: "music.note")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: audioCacheSize, countStyle: .file))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Label("Artwork cache", systemImage: "photo.stack")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                            .foregroundColor(.secondary)
                    }
                    Button {
                        Task {
                            isClearingCache = true
                            await ImageCache.shared.clear()
                            await AudioCache.shared.clear()
                            await refreshCacheSizes()
                            isClearingCache = false
                        }
                    } label: {
                        HStack {
                            Label("Clear cache", systemImage: "trash")
                            if isClearingCache {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isClearingCache || (cacheSize == 0 && audioCacheSize == 0))
                    Text("Removes cached music and cover art. Both are re-fetched as needed.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding()

                // About section
                Section(header: Text("About").font(.headline)) {
                    Button {
                        showDonationQR = true
                    } label: {
                        HStack {
                            Text("QR code me a coffee")
                            Spacer()
                            Text("Show QR").foregroundColor(.secondary)
                        }
                    }
                    .sheet(isPresented: $showDonationQR) {
                        VStack(spacing: 40) {
                            Text("Scan to donate a coffee!")
                                .font(.subheadline)
                            Image("paypalme")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 500, height: 500)
                            Button("Close") { showDonationQR = false }
                        }
                        .padding()
                    }

                    HStack { Text("App"); Spacer(); Text("earsonics").foregroundColor(.secondary) }
                        .focusable()
                    HStack { Text("Version"); Spacer(); Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown").foregroundColor(.secondary) }
                        .focusable()
                    HStack { Text("Protocol"); Spacer(); Text("Subsonic/Navidrome").foregroundColor(.secondary) }
                        .focusable()
                    HStack { Text("Platform"); Spacer(); Text("Apple TV").foregroundColor(.secondary) }
                        .focusable()
                }
                .padding(.vertical, 20)
            }
            .padding(.horizontal, AppLayout.horizontalPadding)
            .padding(.top, AppLayout.contentTopPadding)
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .servers: ServerManagementView()
                case .addServer: ServerEditView(mode: .add)
                case .editServer(let server): ServerEditView(mode: .edit(server))
                case .choice(let choice): SettingsChoiceList(choice: choice)
                }
            }
        }
        .task { await refreshCacheSizes() }
    }

    private func refreshCacheSizes() async {
        cacheSize = await ImageCache.shared.diskUsage()
        audioCacheSize = await AudioCache.shared.diskUsage()
    }
}

/// Pages reachable from Settings, opened by value through SettingsView's
/// navigation path.
enum SettingsRoute: Hashable {
    case servers
    case addServer
    case editServer(Server)
    case choice(SettingsChoice)
}
// MARK: - Accent colour swatch
private struct AccentSwatchButton: View {
    let choice: AccentColorChoice
    let isSelected: Bool
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(choice.color)
                .frame(width: 52, height: 52)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.headline.bold())
                            .foregroundColor(.black.opacity(0.7))
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(isFocused ? 1 : 0), lineWidth: 4)
                }
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(CardlessButtonStyle())
        .focused($isFocused)
        .accessibilityLabel(choice.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Queue settings
/// What happens when a queue ends, and how the queue is kept between
/// launches. The player reads the same keys (see `PlaybackPreferences`).
struct QueueSettingsSection: View {
    @AppStorage(PlaybackPreferences.syncQueueKey) private var syncQueueWithServer = true

    var body: some View {
        Section {
            SettingsChoiceRow(choice: .afterAlbum)
            SettingsChoiceRow(choice: .afterPlaylist)
            SettingsChoiceRow(choice: .launch)
            Toggle(isOn: $syncQueueWithServer) {
                Text("Sync queue with server")
            }
        } header: {
            Text("Queue").font(.headline)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Albums include an artist’s “Play all”; mixes are Home shelves, Favourites, Tracks and Search. Songs added when a queue ends are marked “Autoplay” in the queue.")
                Text(syncQueueWithServer
                     ? "Sync saves your queue and position to the server, so you can carry on in other Subsonic apps or on another Apple TV."
                     : "Your queue is only saved on this Apple TV.")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Choice rows
/// A setting with a fixed list of choices. Each opens its own page through
/// the Settings navigation path: the standard `Picker` pushes its list
/// outside that path, and in this app such pages open blank (see
/// `SettingsRoute`).
enum SettingsChoice: Hashable {
    case quality
    case afterAlbum
    case afterPlaylist
    case launch

    var title: String {
        switch self {
        case .quality:       return "Quality"
        case .afterAlbum:    return "When an album ends"
        case .afterPlaylist: return "When a playlist or mix ends"
        case .launch:        return "On launch"
        }
    }

    /// UserDefaults key, shared with whatever reads the setting.
    var key: String {
        switch self {
        case .quality:       return StreamQuality.defaultsKey
        case .afterAlbum:    return PlaybackPreferences.afterAlbumKey
        case .afterPlaylist: return PlaybackPreferences.afterPlaylistKey
        case .launch:        return PlaybackPreferences.launchBehaviourKey
        }
    }

    var defaultValue: String {
        switch self {
        case .quality:       return StreamQuality.original.rawValue
        case .afterAlbum:    return QueueContinuation.defaultAfterAlbum.rawValue
        case .afterPlaylist: return QueueContinuation.defaultAfterPlaylist.rawValue
        case .launch:        return QueueLaunchBehaviour.restorePaused.rawValue
        }
    }

    /// Stored value and display name of each choice, in order.
    var options: [(value: String, name: String)] {
        switch self {
        case .quality:
            return StreamQuality.allCases.map { ($0.rawValue, $0.displayName) }
        case .afterAlbum, .afterPlaylist:
            return QueueContinuation.allCases.map { ($0.rawValue, $0.displayName) }
        case .launch:
            return QueueLaunchBehaviour.allCases.map { ($0.rawValue, $0.displayName) }
        }
    }

    func name(for value: String) -> String {
        options.first { $0.value == value }?.name
            ?? options.first { $0.value == defaultValue }?.name ?? value
    }
}

/// A Settings row showing the setting's name and current choice; selecting
/// it opens the list of choices.
struct SettingsChoiceRow: View {
    let choice: SettingsChoice
    @AppStorage private var value: String

    init(choice: SettingsChoice) {
        self.choice = choice
        _value = AppStorage(wrappedValue: choice.defaultValue, choice.key)
    }

    var body: some View {
        NavigationLink(value: SettingsRoute.choice(choice)) {
            HStack {
                Text(choice.title)
                Spacer()
                Text(choice.name(for: value))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The list of choices for one setting. Selecting one saves it and goes back.
struct SettingsChoiceList: View {
    let choice: SettingsChoice
    @AppStorage private var value: String
    @Environment(\.dismiss) private var dismiss

    init(choice: SettingsChoice) {
        self.choice = choice
        _value = AppStorage(wrappedValue: choice.defaultValue, choice.key)
    }

    var body: some View {
        Form {
            Section(header: Text(choice.title).font(.headline)) {
                ForEach(choice.options, id: \.value) { option in
                    Button {
                        value = option.value
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.name)
                            Spacer()
                            if option.value == value {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}

#Preview("Queue settings") {
    NavigationStack {
        Form {
            QueueSettingsSection()
        }
    }
}
