// ViewModels/AppState.swift
import SwiftUI
import Combine

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

    init() {
        // Wire up active server to API and player
        syncActiveServer()
        serverStore.$activeServerID
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncActiveServer() }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

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
