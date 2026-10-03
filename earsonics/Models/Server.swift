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

// MARK: - URL checks
extension Server {
    /// How a server URL will behave, for feedback in the server editor.
    enum URLCheck: Equatable {
        /// HTTPS, or plain HTTP to a private-network address.
        case ok
        /// Not a usable http(s) URL with a host.
        case invalid
        /// Plain HTTP to a public IP address. App Transport Security exempts IP
        /// literals, so it connects, but traffic crosses the internet unencrypted.
        case unencryptedPublic
        /// Plain HTTP to a domain name. App Transport Security blocks this, so
        /// it can never connect.
        case blockedHTTPDomain
    }

    static func check(url: String) -> URLCheck {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = comps.host?.lowercased(), !host.isEmpty else { return .invalid }
        guard scheme == "http" else { return .ok }

        if let octets = ipv4Octets(host) {
            return isPrivateIPv4(octets) ? .ok : .unencryptedPublic
        }
        if host.contains(":") {   // IPv6 literal; URLComponents keeps the brackets
            let ip = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            let isPrivate = ip == "::1" || ip.hasPrefix("fe80:")
                || ip.hasPrefix("fc") || ip.hasPrefix("fd")
            return isPrivate ? .ok : .unencryptedPublic
        }
        // ATS allows plain HTTP only to unqualified names ("nas") and .local
        // (Bonjour) hosts; anything else with a dot is treated as a public domain.
        if host == "localhost" || !host.contains(".") || host.hasSuffix(".local") {
            return .ok
        }
        return .blockedHTTPDomain
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { Int($0) }.filter { (0...255).contains($0) }
        return octets.count == 4 ? octets : nil
    }

    /// Loopback, link-local, RFC 1918 private and CGNAT (used by Tailscale) ranges.
    private static func isPrivateIPv4(_ o: [Int]) -> Bool {
        switch (o[0], o[1]) {
        case (10, _), (127, _): return true
        case (172, 16...31): return true
        case (192, 168), (169, 254): return true
        case (100, 64...127): return true
        default: return false
        }
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
            if let id = activeServerID, !isEphemeral {
                UserDefaults.standard.set(id.uuidString, forKey: activeKey)
            }
        }
    }

    /// True when the server list came from the UI-test environment (below);
    /// nothing is then read from or written to UserDefaults or the Keychain.
    private var isEphemeral = false

    var activeServer: Server? {
        guard let id = activeServerID else { return servers.first }
        return servers.first(where: { $0.id == id }) ?? servers.first
    }

    init() {
        #if DEBUG
        // UI tests pass a server in the launch environment so they run against
        // a known library (the public Navidrome demo) without reading or
        // overwriting the servers saved on the device. Debug builds only.
        let env = ProcessInfo.processInfo.environment
        if let url = env["EARSONICS_UITEST_SERVER_URL"],
           let username = env["EARSONICS_UITEST_USERNAME"],
           let password = env["EARSONICS_UITEST_PASSWORD"] {
            isEphemeral = true
            let server = Server(name: "UI Test Server", url: url, username: username, password: password)
            servers = [server]
            activeServerID = server.id
            return
        }
        #endif
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
        guard !isEphemeral else { return }
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
