// Models/Server.swift
import Foundation
import Combine
import SwiftUI

struct Server: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var url: String          // e.g. https://music.example.com
    var username: String
    var password: String     // held in memory only; persisted to the Keychain, never UserDefaults (see ServerStore)
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
        let removed = offsets.map { servers[$0] }
        servers.remove(atOffsets: offsets)
        removed.forEach { KeychainHelper.delete(account: $0.id.uuidString) }
        if activeServer == nil { activeServerID = servers.first?.id }
    }

    func delete(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        KeychainHelper.delete(account: server.id.uuidString)
        if activeServer == nil { activeServerID = servers.first?.id }
    }

    /// Persists passwords to the Keychain and a password-free copy of the
    /// server list to UserDefaults, so secrets never touch UserDefaults.
    private func save() {
        for server in servers {
            KeychainHelper.save(server.password, account: server.id.uuidString)
        }
        let sanitized = servers.map { server -> Server in
            var copy = server
            copy.password = ""
            return copy
        }
        if let data = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Server].self, from: data) else { return }

        // Hydrate each password from the Keychain. If the stored blob still
        // carries a plaintext password (a pre-Keychain 1.05 install) and the
        // Keychain has no entry yet, migrate it across.
        var needsResave = false
        servers = decoded.map { server in
            var copy = server
            let account = server.id.uuidString
            if let stored = KeychainHelper.read(account: account) {
                copy.password = stored
            } else if !server.password.isEmpty {
                KeychainHelper.save(server.password, account: account)
                needsResave = true
            }
            return copy
        }

        // Rewrite UserDefaults without the plaintext passwords. Assigning to
        // `servers` above already triggered `save()` via didSet, so this is a
        // belt-and-braces step for the migration path.
        if needsResave { save() }
    }
}
