// EarsonicsCore/Server.swift
import Foundation
import Observation

public nonisolated struct Server: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var url: String          // e.g. https://music.example.com
    public var username: String
    public var password: String     // held in memory only; persisted to the Keychain, never UserDefaults (see ServerStore)
    public var isActive: Bool = true

    public init(id: UUID = UUID(), name: String, url: String, username: String, password: String, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.url = url
        self.username = username
        self.password = password
        self.isActive = isActive
    }

    // Computed base URL normalised (no trailing slash)
    public var baseURL: String {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while u.hasSuffix("/") { u.removeLast() }
        return u
    }
}

// MARK: - URL checks
nonisolated extension Server {
    /// How a server URL will behave, for feedback in the server editor.
    public nonisolated enum URLCheck: Equatable, Sendable {
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

    public static func check(url: String) -> URLCheck {
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
@MainActor
@Observable
public final class ServerStore {
    public static let shared = ServerStore()
    /// Settings key for the server list (passwords are in the Keychain).
    public static let serversKey = "earsonics.servers"
    private let key = ServerStore.serversKey
    private let activeKey = "earsonics.activeServerID"

    public var servers: [Server] = [] {
        didSet { save() }
    }
    public var activeServerID: UUID? {
        didSet {
            if let id = activeServerID, !isEphemeral {
                defaults.set(id.uuidString, forKey: activeKey)
            }
        }
    }

    #if DEBUG
    public static let uiTestServerID = UUID(uuidString: "E5E5E5E5-0000-4000-8000-0000000000E5")!
    #endif

    /// True when the server list came from the UI-test environment (below);
    /// nothing is then read from or written to UserDefaults or the Keychain.
    @ObservationIgnored private var isEphemeral = false

    public var activeServer: Server? {
        guard let id = activeServerID else { return servers.first }
        return servers.first(where: { $0.id == id }) ?? servers.first
    }

    /// Where the server list (minus passwords) is kept.
    @ObservationIgnored private let defaults: UserDefaults

    public convenience init() {
        self.init(defaults: .standard, environment: ProcessInfo.processInfo.environment)
    }

    /// `defaults` and `environment` are parameters so unit tests can use a
    /// throwaway settings store and no launch environment.
    public init(defaults: UserDefaults, environment env: [String: String] = [:]) {
        self.defaults = defaults
        #if DEBUG
        // UI tests pass a server in the launch environment so they run against
        // a known library (the public Navidrome demo) without reading or
        // overwriting the servers saved on the device. Debug builds only.
        // Hosting unit tests: never load the device's real servers, so a test
        // can't touch a real library (e.g. saving an empty play queue over the
        // user's own). XCTest sets this variable in the test host process.
        if env["XCTestConfigurationFilePath"] != nil {
            isEphemeral = true
            return
        }
        // UI tests of first-run sign-in: no servers, and nothing saved.
        if env["EARSONICS_UITEST_NO_SERVERS"] == "1" {
            isEphemeral = true
            return
        }
        if let url = env["EARSONICS_UITEST_SERVER_URL"],
           let username = env["EARSONICS_UITEST_USERNAME"],
           let password = env["EARSONICS_UITEST_PASSWORD"] {
            isEphemeral = true
            // A fixed id, so the server's saved queue survives a relaunch
            // within a test.
            // A name can be given for screenshots.
            let server = Server(id: Self.uiTestServerID, name: env["EARSONICS_UITEST_SERVER_NAME"] ?? "UI Test Server",
                                url: url, username: username, password: password)
            if env["EARSONICS_UITEST_CLEAR_LOCAL_QUEUE"] == "1" {
                LocalQueueStore.delete(serverID: server.id)
            }
            servers = [server]
            activeServerID = server.id
            return
        }
        #endif
        load()
        if let str = defaults.string(forKey: activeKey),
           let id = UUID(uuidString: str) {
            activeServerID = id
        } else {
            activeServerID = servers.first?.id
        }
    }

    public func add(_ server: Server) {
        servers.append(server)
        if servers.count == 1 { activeServerID = server.id }
    }

    public func update(_ server: Server) {
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = server
        }
    }

    public func delete(at offsets: IndexSet) {
        let removed = offsets.map { servers[$0] }
        // Highest index first, so earlier removals don't shift later ones.
        for index in offsets.sorted(by: >) where servers.indices.contains(index) {
            servers.remove(at: index)
        }
        removed.forEach {
            KeychainHelper.delete(account: $0.id.uuidString)
            LocalQueueStore.delete(serverID: $0.id)
        }
        if activeServer == nil { activeServerID = servers.first?.id }
    }

    public func delete(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        KeychainHelper.delete(account: server.id.uuidString)
        LocalQueueStore.delete(serverID: server.id)
        if activeServer == nil { activeServerID = servers.first?.id }
    }

    /// Persists passwords to the Keychain and a password-free copy of the
    /// server list to UserDefaults, so secrets never touch UserDefaults.
    /// Last password written to the Keychain per server, so unchanged ones
    /// aren't rewritten on every edit to the list.
    @ObservationIgnored private var savedPasswords: [UUID: String] = [:]

    private func save() {
        guard !isEphemeral else { return }
        for server in servers where savedPasswords[server.id] != server.password {
            if KeychainHelper.save(server.password, account: server.id.uuidString) {
                savedPasswords[server.id] = server.password
            }
        }
        let sanitized = servers.map { server -> Server in
            var copy = server
            copy.password = ""
            return copy
        }
        if let data = try? JSONEncoder().encode(sanitized) {
            defaults.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
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
                savedPasswords[server.id] = stored
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
