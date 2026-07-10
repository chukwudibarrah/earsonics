// ViewModels/AppState.swift
import SwiftUI
import Combine
import AVFoundation

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var serverStore = ServerStore.shared
    @Published var player = AudioPlayerService.shared
    @Published var api = SubsonicClient.shared

    @Published var showNowPlaying: Bool = false
    @Published var isConnected: Bool = false
    @Published var connectionError: String? = nil

    @AppStorage("crossfadeDuration") var crossfadeDuration: Double = 0.0
    @AppStorage("preventScreenSaver") var preventScreenSaver: Bool = false
    @AppStorage("accentColourChoice") var accentColourRaw: String = AccentColorChoice.orange.rawValue

    /// The user-selected highlight colour (see `AccentColorChoice`).
    var accentChoice: AccentColorChoice {
        get { AccentColorChoice(rawValue: accentColourRaw) ?? .orange }
        set { accentColourRaw = newValue.rawValue }
    }

    var accentColor: Color { accentChoice.color }

    init() {
        // Wire up active server to API and player
        syncActiveServer()
        serverStore.$activeServerID
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncActiveServer() }
            .store(in: &cancellables)

        setupObservers()
    }

    private var cancellables = Set<AnyCancellable>()

    private func setupObservers() {
        // Observe playback state to manage idle timer
        player.$isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] isPlaying in
                guard let self = self else { return }
                self.updateIdleTimer(isPlaying: isPlaying)
            }
            .store(in: &cancellables)
            
        // Observe app state for safe idle timer resetting
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { _ in
                // Always allow screen saver when app is in background
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { _ in
                // Allow screen saver if audio is interrupted
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .store(in: &cancellables)
    }

    private func updateIdleTimer(isPlaying: Bool) {
        if preventScreenSaver && isPlaying {
            UIApplication.shared.isIdleTimerDisabled = true
        } else {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    func syncActiveServer() {
        guard let server = serverStore.activeServer else {
            isConnected = false
            return
        }
        api.server = server
        player.server = server
        Task { await testConnection(server: server) }
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
