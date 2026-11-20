// earsonics-iOS/Settings/SettingsView.swift
import SwiftUI
import StoreKit
import EarsonicsCore

/// Settings as cards: each shows a one-line summary and opens to its
/// controls. Settings use the same keys as the Apple TV app, so the shared
/// player and core read them the same way.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    private let player = AudioPlayerService.shared

    @AppStorage(AppearanceChoice.key) private var appearance = AppearanceChoice.defaultValue
    @AppStorage(StreamQuality.defaultsKey) private var quality = StreamQuality.original
    @AppStorage(VolumeNormalisation.modeKey) private var balance = VolumeNormalisation.Mode.track
    @AppStorage(PlaybackPreferences.afterAlbumKey) private var afterAlbum = QueueContinuation.defaultAfterAlbum
    @AppStorage(PlaybackPreferences.afterPlaylistKey) private var afterPlaylist = QueueContinuation.defaultAfterPlaylist
    @AppStorage(PlaybackPreferences.launchBehaviourKey) private var onLaunch = QueueLaunchBehaviour.restorePaused
    @AppStorage(PlaybackPreferences.syncQueueKey) private var syncQueue = true
    @AppStorage("audioCacheEnabled") private var cacheEnabled = true
    @AppStorage(AudioCache.limitKey) private var cacheLimitGB = 2

    @State private var musicCacheSize: Int64 = 0
    @State private var artworkCacheSize: Int64 = 0
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        @Bindable var appState = appState
        @Bindable var player = player
        ScrollView {
            VStack(spacing: 16) {
                serverCard

                SettingsCard(title: "Playback", subtitle: "Quality, transitions and volume",
                             summary: "\(quality.displayName) · Crossfade \(Int(appState.crossfadeDuration))s · \(player.normalizeVolume ? "Even volume" : "Volume as recorded")") {
                    Picker("Quality", selection: $quality) {
                        ForEach(StreamQuality.allCases) { Text($0.displayName).tag($0) }
                    }
                    note("Streaming and cached copies use the same quality, so a replay sounds like the first play.")
                    Stepper("Crossfade: \(Int(appState.crossfadeDuration))s", value: $appState.crossfadeDuration, in: 0...12, step: 1)
                    Toggle("Normalise volume", isOn: $player.normalizeVolume)
                    if player.normalizeVolume {
                        Picker("Balance volume", selection: $balance) {
                            ForEach(VolumeNormalisation.Mode.allCases) { Text($0.displayName).tag($0) }
                        }
                        .onChange(of: balance) { player.refreshVolume() }
                        note("Uses Replay Gain tags where songs have them, and measures the rest as they download.")
                    }
                }

                SettingsCard(title: "Queue", subtitle: "What plays next and what’s kept",
                             summary: "Albums: \(afterAlbum.displayName) · Mixes: \(afterPlaylist.displayName)") {
                    Picker("When an album ends", selection: $afterAlbum) {
                        ForEach(QueueContinuation.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("When a playlist or mix ends", selection: $afterPlaylist) {
                        ForEach(QueueContinuation.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("On launch", selection: $onLaunch) {
                        ForEach(QueueLaunchBehaviour.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Sync queue with server", isOn: $syncQueue)
                    note(syncQueue ? "Your queue and position are saved on the server, so you can carry on in other Subsonic apps or on your Apple TV."
                                   : "Your queue is only saved on this device.")
                }

                SettingsCard(title: "Appearance", subtitle: "Theme and highlight colour",
                             summary: "\(appearance.displayName) · \(appState.accentChoice.displayName)") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppearanceChoice.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 12) {
                        ForEach(AccentColorChoice.allCases) { choice in
                            Button {
                                appState.accentChoice = choice
                            } label: {
                                Circle()
                                    .fill(choice.color)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if appState.accentChoice == choice {
                                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.black.opacity(0.7))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.displayName)
                            .accessibilityAddTraits(appState.accentChoice == choice ? .isSelected : [])
                        }
                    }
                }

                SettingsCard(title: "Storage", subtitle: "Cached music and artwork",
                             summary: "Music \(bytes(musicCacheSize)) · Artwork \(bytes(artworkCacheSize))") {
                    Toggle("Cache played songs", isOn: $cacheEnabled)
                    if cacheEnabled {
                        Stepper("Music cache limit: \(cacheLimitGB) GB", value: $cacheLimitGB, in: 1...20)
                    }
                    Button("Clear Cache", role: .destructive) {
                        Task {
                            await ImageCache.shared.clear()
                            await AudioCache.shared.clear()
                            await refreshSizes()
                        }
                    }
                    note("Cached music and artwork are downloaded again when needed.")
                }

                SettingsCard(title: "About", subtitle: "earsonics \(appVersion)", summary: nil) {
                    Button("Rate earsonics") { requestReview() }
                    Link("Write a Review", destination: URL(string: "https://apps.apple.com/app/id6766037499?action=write-review")!)
                    Link("Buy Me a Coffee", destination: URL(string: "https://buymeacoffee.com/cbarrah")!)
                    Link("Privacy Policy", destination: URL(string: "https://github.com/chukwudibarrah/earsonics/blob/main/privacy-policy.md")!)
                    Link("Source Code on GitHub", destination: URL(string: "https://github.com/chukwudibarrah/earsonics")!)
                }
            }
            .padding()
        }
        .appBackground()
        .navigationTitle("Settings")
        .toolbarTitleDisplayMode(.inlineLarge)
        .task { await refreshSizes() }
    }

    private var serverCard: some View {
        NavigationLink {
            ServerListView()
        } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(appState.isConnected ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.serverStore.activeServer?.name ?? "No server").font(.headline)
                    Text(appState.isConnected ? "Connected" : (appState.connectionError ?? "Not connected"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Text("Servers").font(.subheadline).foregroundStyle(Palette.secondaryText)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.secondaryText)
            }
            .card(cornerRadius: 24, padding: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(Palette.secondaryText)
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private func refreshSizes() async {
        musicCacheSize = await AudioCache.shared.diskUsage()
        artworkCacheSize = await ImageCache.shared.diskUsage()
    }
}

/// A settings card: title, description and a summary line; tapping opens
/// its controls.
struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let summary: String?
    @ViewBuilder let content: () -> Content
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.title3.bold())
                        Text(subtitle).font(.subheadline).foregroundStyle(Palette.secondaryText)
                        if let summary, !isExpanded {
                            Text(summary).font(.footnote.weight(.semibold)).foregroundStyle(Palette.secondaryText)
                                .padding(.top, 4)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .padding(8)
                        .background(Palette.raised, in: Circle())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides these settings" : "Shows these settings")

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) { content() }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 24, padding: 18)
    }
}

/// Saved servers: pick the active one, add, edit or delete.
struct ServerListView: View {
    @Environment(AppState.self) private var appState
    @State private var editing: Server?
    @State private var isAdding = false

    var body: some View {
        List {
            ForEach(appState.serverStore.servers) { server in
                Button {
                    appState.serverStore.activeServerID = server.id
                    appState.syncActiveServer()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(server.name).font(.headline)
                            Text(server.username).font(.subheadline).foregroundStyle(Palette.secondaryText)
                        }
                        Spacer()
                        if server.id == appState.serverStore.activeServer?.id {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        appState.serverStore.delete(server)
                        appState.syncActiveServer()
                    }
                    Button("Edit") { editing = server }
                }
                .listRowBackground(Palette.card)
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Servers")
        .toolbar { Button("Add Server", systemImage: "plus") { isAdding = true } }
        .sheet(isPresented: $isAdding) { NavigationStack { ServerEditView() } }
        .sheet(item: $editing) { server in NavigationStack { ServerEditView(editing: server) } }
    }
}

/// Add or edit a server. Same address checks as the Apple TV editor; the
/// password is kept in the Keychain by ServerStore.
struct ServerEditView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    var editing: Server? = nil
    /// First run: there's nothing to cancel back to.
    var isFirstRun = false

    @State private var name = ""
    @State private var url = "https://"
    @State private var username = ""
    @State private var password = ""
    @State private var testResult: String?
    @State private var isTesting = false

    private var urlCheck: Server.URLCheck { Server.check(url: url) }
    private var isValid: Bool { !name.isEmpty && urlCheck != .invalid && !username.isEmpty && !password.isEmpty }

    var body: some View {
        Form {
            if isFirstRun {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Welcome to earsonics").font(.title2.bold())
                        Text("Connect to your Navidrome or other Subsonic server to start listening.")
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            Section("Server") {
                TextField("Name", text: $name)
                TextField("Address", text: $url)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                if urlCheck == .unencryptedPublic {
                    Text("This connection isn’t encrypted. Use https:// if your server supports it.").font(.footnote).foregroundStyle(.orange)
                } else if urlCheck == .blockedHTTPDomain {
                    Text("Unencrypted (http://) connections only work to local addresses such as 192.168.1.20. Use https://.").font(.footnote).foregroundStyle(.red)
                }
            }
            Section("Account") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password", text: $password)
            }
            Section {
                Button(isTesting ? "Testing…" : "Test connection") { Task { await test() } }
                    .disabled(!isValid || isTesting)
                if let testResult { Text(testResult).font(.footnote).foregroundStyle(Palette.secondaryText) }
                Button("Save") { save() }.disabled(!isValid)
            }
        }
        .navigationTitle(editing == nil ? "Add a server" : "Edit server")
        .toolbar {
            if !isFirstRun {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .onAppear {
            guard let editing else { return }
            name = editing.name; url = editing.url; username = editing.username; password = editing.password
        }
    }

    private func makeServer() -> Server {
        if var server = editing {
            server.name = name; server.url = url; server.username = username; server.password = password
            return server
        }
        return Server(name: name, url: url, username: username, password: password)
    }

    private func test() async {
        isTesting = true
        defer { isTesting = false }
        do {
            testResult = try await SubsonicClient.shared.ping(server: makeServer()) ? "Connected successfully" : "The server didn’t respond as expected"
        } catch {
            testResult = error.localizedDescription
        }
    }

    private func save() {
        let server = makeServer()
        if editing == nil { appState.serverStore.add(server) } else { appState.serverStore.update(server) }
        appState.serverStore.activeServerID = server.id
        appState.syncActiveServer()
        dismiss()
    }
}
