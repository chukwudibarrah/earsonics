// ViewModels/AppState.swift
import SwiftUI
import AVFoundation
import Observation
import EarsonicsCore

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let serverStore = ServerStore.shared
    let player = AudioPlayerService.shared
    let api = SubsonicClient.shared

    var showNowPlaying: Bool = false
    var isConnected: Bool = false
    var connectionError: String? = nil

    /// Id of the server the API client is currently pointed at, so views can
    /// reset their library data when it changes.
    private(set) var activeServerID: UUID? = nil

    // Settings. Stored properties (not `@AppStorage`, which only works in
    // views) saved under the same keys as before, so existing choices carry
    // over; the player reads `crossfadeDuration` from the same key.
    var crossfadeDuration: Double = UserDefaults.standard.double(forKey: Keys.crossfade) {
        didSet { UserDefaults.standard.set(crossfadeDuration, forKey: Keys.crossfade) }
    }
    var preventScreenSaver: Bool = UserDefaults.standard.bool(forKey: Keys.preventScreenSaver) {
        didSet {
            UserDefaults.standard.set(preventScreenSaver, forKey: Keys.preventScreenSaver)
            // Apply straight away, not only at the next play/pause.
            updateIdleTimer(isPlaying: player.isPlaying)
        }
    }
    var accentColourRaw: String = UserDefaults.standard.string(forKey: Keys.accent) ?? AccentColorChoice.orange.rawValue {
        didSet { UserDefaults.standard.set(accentColourRaw, forKey: Keys.accent) }
    }

    enum Keys {
        static let crossfade = PlaybackPreferences.crossfadeKey
        static let preventScreenSaver = "preventScreenSaver"
        static let accent = "accentColourChoice"
    }

    /// The user-selected highlight colour (see `AccentColorChoice`).
    var accentChoice: AccentColorChoice {
        get { AccentColorChoice(rawValue: accentColourRaw) ?? .orange }
        set { accentColourRaw = newValue.rawValue }
    }

    var accentColor: Color { accentChoice.color }

    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []

    init() {
        syncActiveServer()
        observeActiveServer()
        observePlayback()
        observeAppLifecycle()
    }

    /// Follows the active server when it changes outside the server editor
    /// (which syncs itself after saving), e.g. when the active server is
    /// deleted.
    private func observeActiveServer() {
        Task { [weak self] in
            guard let store = self?.serverStore else { return }
            for await id in Observations({ store.activeServer?.id }) {
                guard let self else { return }
                if id != self.activeServerID { self.syncActiveServer() }
            }
        }
    }

    /// Keeps the screen saver off while music plays, if the user asked for that.
    private func observePlayback() {
        Task { [weak self] in
            guard let player = self?.player else { return }
            for await isPlaying in Observations({ player.isPlaying }) {
                guard let self else { return }
                self.updateIdleTimer(isPlaying: isPlaying)
            }
        }
    }

    private func observeAppLifecycle() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Always allow the screen saver when the app is in the background.
                UIApplication.shared.isIdleTimerDisabled = false
                // The app may not come back (the system can end it while
                // it's in the background), so save the queue and position now.
                self?.player.saveQueueNow()
            }
        })
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { _ in
            // Allow the screen saver if audio is interrupted.
            MainActor.assumeIsolated { UIApplication.shared.isIdleTimerDisabled = false }
        })
    }

    private func updateIdleTimer(isPlaying: Bool) {
        UIApplication.shared.isIdleTimerDisabled = preventScreenSaver && isPlaying
    }

    func syncActiveServer() {
        guard let server = serverStore.activeServer else {
            // Last server deleted: detach so nothing keeps talking to it.
            api.server = nil
            player.server = nil
            if activeServerID != nil {
                activeServerID = nil
                LibraryStore.shared.reset()
            }
            isConnected = false
            return
        }
        api.server = server
        player.server = server
        if activeServerID != server.id {
            activeServerID = server.id
            // Another server's playlists and stars don't apply here.
            LibraryStore.shared.reset()
        }
        Task { await testConnection(server: server) }
        // At launch, and when switching to another server: bring back its
        // saved queue (as the user's "On launch" setting says).
        Task { await player.restoreSavedQueue() }
    }

    func testConnection(server: Server) async {
        do {
            let ok = try await api.ping(server: server)
            isConnected = ok
            connectionError = nil
        } catch {
            isConnected = false
            connectionError = error.localizedDescription
        }
    }
}
