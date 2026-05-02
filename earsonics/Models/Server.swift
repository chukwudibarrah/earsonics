// Models/Server.swift
import Foundation
import Combine
import SwiftUI

struct Server: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var url: String          // e.g. https://music.example.com
    var username: String
    var password: String     // stored in plain text locally; consider Keychain for prod
    var isActive: Bool = true

    // Computed base URL normalised (no trailing slash)
    var baseURL: String {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while u.hasSuffix("/") { u.removeLast() }
        return u
    }
}

// MARK: - Persistence
class ServerStore: ObservableObject {
    static let shared = ServerStore()
    private let key = "earsonics.servers"
    private let activeKey = "earsonics.activeServerID"

    @Published var servers: [Server] = [] {
        didSet { save() }
    }
    @Published var activeServerID: UUID? {
        didSet {
            if let id = activeServerID {
                UserDefaults.standard.set(id.uuidString, forKey: activeKey)
            }
        }
    }

    var activeServer: Server? {
        guard let id = activeServerID else { return servers.first }
        return servers.first(where: { $0.id == id }) ?? servers.first
    }

    init() {
        load()
        if let str = UserDefaults.standard.string(forKey: activeKey),
           let id = UUID(uuidString: str) {
            activeServerID = id
        } else {
            activeServerID = servers.first?.id
        }
    }

    func add(_ server: Server) {
        servers.append(server)
        if servers.count == 1 { activeServerID = server.id }
    }

    func update(_ server: Server) {
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = server
        }
    }

    func delete(at offsets: IndexSet) {
        servers.remove(atOffsets: offsets)
        if activeServer == nil { activeServerID = servers.first?.id }
    }

    func delete(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        if activeServer == nil { activeServerID = servers.first?.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Server].self, from: data) else { return }
        servers = decoded
    }
}
