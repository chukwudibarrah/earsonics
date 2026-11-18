// Views/SettingsView.swift
import SwiftUI
import EarsonicsCore

struct SettingsView: View {
    @Environment(AppState.self) var appState
    private let player = AudioPlayerService.shared
    @State private var showDonationQR = false
    @State private var showReviewQR = false
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
        // Bindings into the shared app state (toggles below).
        @Bindable var appState = appState
        @Bindable var player = player
        NavigationStack(path: $navPath) {
            Form {
                // Server management section
                Section(header: Text("Servers").font(.headline)) {
                    // The active server and its connection status share this
                    // row: a status row of its own looked selectable.
                    NavigationLink(value: SettingsRoute.servers) {
                        HStack {
                            Label("Manage servers", systemImage: "server.rack")
                            Spacer()
                            if let server = appState.serverStore.activeServer {
                                Text(server.name).foregroundColor(.secondary).font(.callout)
                                // Colour on the icon only: green text was
                                // unreadable on the white focused row.
                                Label {
                                    Text(appState.isConnected ? "Connected" : "Disconnected")
                                        .foregroundStyle(.secondary)
                                } icon: {
                                    Image(systemName: appState.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(appState.isConnected ? .green : .red)
                                }
                                .font(.callout)
                                .padding(.leading, 16)
                            }
                        }
                    }

                    if let server = appState.serverStore.activeServer {
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
                    SettingsNote("Controls both live streaming and cached copies, so a replayed track matches its first play. Lower qualities are transcoded by the server and use less space.")
                    HStack {
                        Text("Crossfade duration: \(Int(appState.crossfadeDuration))s")
                        Spacer()
                        Button("-") {
                            if appState.crossfadeDuration > 0 { appState.crossfadeDuration -= 1 }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Shorter crossfade")
                        Button("+") {
                            if appState.crossfadeDuration < 12 { appState.crossfadeDuration += 1 }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Longer crossfade")
                    }
                    if appState.crossfadeDuration > 0 {
                        SettingsNote("Overlapping streams may occasionally cause lag on wireless outputs (AirPlay/Bluetooth).")
                    }

                    Toggle(isOn: $player.normalizeVolume) {
                        Text("Normalise volume")
                    }
                    if appState.player.normalizeVolume {
                        SettingsNote("Uses Replay Gain metadata to equalise volume between tracks and prevent loud peaks.")
                    }

                    Toggle(isOn: $appState.preventScreenSaver) {
                        Text("Disable screen saver while playing")
                    }
                    if appState.preventScreenSaver {
                        SettingsNote("Warning: Keeping the screen active for long periods may cause burn-in on some TVs.",
                                     isWarning: true)
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
                    }
                    SettingsNote("Used for the focus outline, now-playing glow and play indicators.")
                }
                .padding()

                // Storage section
                Section(header: Text("Storage").font(.headline)) {
                    Toggle(isOn: $audioCacheEnabled) {
                        Text("Cache played songs")
                    }
                    if audioCacheEnabled {
                        SettingsNote("Stores tracks you play so replaying them doesn't stream again.")
                        HStack {
                            Text("Music cache limit: \(audioCacheLimitGB) GB")
                            Spacer()
                            Button("-") {
                                if audioCacheLimitGB > 1 { audioCacheLimitGB -= 1 }
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Smaller music cache")
                            Button("+") {
                                if audioCacheLimitGB < 10 { audioCacheLimitGB += 1 }
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Larger music cache")
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
                    SettingsNote("Removes cached music and cover art. Both are re-fetched as needed.")
                }
                .padding()

                // About section
                Section(header: Text("About").font(.headline)) {
                    // tvOS has no in-app review prompt (StoreKit's
                    // requestReview isn't available), and App Store rules
                    // don't allow custom review pop-ups, so this is a QR
                    // code for the review page, opened on a phone.
                    Button {
                        showReviewQR = true
                    } label: {
                        HStack {
                            Text("Rate earsonics")
                            Spacer()
                            Text("Show QR").foregroundColor(.secondary)
                        }
                    }
                    .sheet(isPresented: $showReviewQR) {
                        VStack(spacing: 40) {
                            Text("Enjoying earsonics? Scan to rate or review it on the App Store.")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                            QRCodeImage(text: AppLinks.writeReview.absoluteString)
                                .frame(width: 500, height: 500)
                                .accessibilityLabel("QR code for the earsonics App Store review page")
                            Button("Close") { showReviewQR = false }
                        }
                        .padding()
                    }

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
            // The form clips to its bounds, which cut off both ends of the
            // enlarged focused row. Clip only at the top (so scrolled rows
            // don't show over the title), leaving the row room at the sides;
            // rows still run to the bottom of the screen, as before.
            .scrollClipDisabled()
            .mask(Rectangle()
                .padding(.horizontal, -AppLayout.horizontalPadding)
                .padding(.bottom, -200))
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
// MARK: - Notes
/// An explanation under the setting it describes: smaller text with no row
/// background, so it doesn't look like (or sit in the way of) a menu item.
/// Plain text, so focus skips it.
struct SettingsNote: View {
    let text: String
    var isWarning = false

    init(_ text: String, isWarning: Bool = false) {
        self.text = text
        self.isWarning = isWarning
    }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(isWarning ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .listRowBackground(Color.clear)
    }
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
