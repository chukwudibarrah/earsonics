// Views/ServerManagementView.swift
import SwiftUI

struct ServerManagementView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        // No NavigationStack here — this is pushed into the Settings stack, and
        // nesting stacks is an anti-pattern on tvOS. Tapping a server (or Add)
        // goes straight to the editor: List → Editor, so Save/Delete return to
        // this list. Links open by value; SettingsView resolves SettingsRoute.
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(appState.serverStore.servers) { server in
                    NavigationLink(value: SettingsRoute.editServer(server)) {
                        ServerRow(server: server, isActive: server.id == appState.serverStore.activeServerID)
                    }
                    .buttonStyle(CardlessButtonStyle())
                }

                NavigationLink(value: SettingsRoute.addServer) {
                    AddServerRow()
                }
                .buttonStyle(CardlessButtonStyle())
            }
            .padding(.top, AppLayout.contentTopPadding)
            .padding(.horizontal, AppLayout.horizontalPadding)
            .padding(.bottom, 120)
        }
        .navigationTitle("Servers")
    }
}

struct ServerRow: View {
    let server: Server
    let isActive: Bool
    @Environment(\.appAccent) private var appAccent

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isActive ? appAccent : .primary)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name).font(.headline)
                Text(server.baseURL).font(.caption).foregroundColor(.secondary)
                Text("User: \(server.username)").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if isActive {
                Text("Active").font(.caption).foregroundColor(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .cardSurface(cornerRadius: 10)
    }
}

// MARK: - Add Server Row
struct AddServerRow: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
            Text("Add server").font(.headline)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .cardSurface(cornerRadius: 10)
    }
}

// MARK: - Server Edit View
/// Single screen for adding or editing a server. Deliberately NOT a `Form`:
/// on tvOS a `TextField` inside a `Form` row draws a focus capsule inside the
/// row's own capsule ("fields within fields"), and the grouped-list ambient
/// font machinery is what the freeze traces implicated. Plain full-width fields
/// in a `ScrollView` avoid both. Actions live here too, so it's List → Editor
/// with Save/Delete returning to the list.
struct ServerEditView: View {
    enum Mode {
        case add
        case edit(Server)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @State private var name: String = ""
    @State private var url: String = "https://"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isTesting = false
    @State private var testResult: String? = nil
    @State private var testSuccess: Bool? = nil

    init(mode: Mode) {
        self.mode = mode
        if case .edit(let server) = mode {
            _name = State(initialValue: server.name)
            _url = State(initialValue: server.url)
            _username = State(initialValue: server.username)
            _password = State(initialValue: server.password)
        }
    }

    private var editingServer: Server? {
        if case .edit(let s) = mode { return s }
        return nil
    }

    private var isActive: Bool {
        guard let s = editingServer else { return false }
        return appState.serverStore.activeServerID == s.id
    }

    private var urlCheck: Server.URLCheck { Server.check(url: url) }

    /// A domain over plain HTTP still saves: the warning explains it will be
    /// blocked, and Test connection confirms it, but a misjudged host name
    /// shouldn't lock someone out of saving a server that works.
    private var isValid: Bool {
        !name.isEmpty && urlCheck != .invalid && !username.isEmpty && !password.isEmpty
    }

    /// Feedback under the URL field. The invalid hint is held back while the
    /// field still holds only the prefilled scheme, so the form doesn't open
    /// with an error showing.
    private var urlMessage: (text: String, isError: Bool)? {
        switch urlCheck {
        case .ok:
            return nil
        case .invalid:
            let untouched = ["", "https://", "http://"].contains(url.trimmingCharacters(in: .whitespaces))
            return untouched ? nil : ("Enter a full address starting with https:// or http://, e.g. https://music.example.com", true)
        case .unencryptedPublic:
            return ("This connection isn’t encrypted. Your login token and music travel over the internet in plain text, and anyone along the way could reuse the token to access your server. Use https:// if your server supports it.", false)
        case .blockedHTTPDomain:
            return ("Apple TV only allows unencrypted (http://) connections to local addresses, such as 192.168.1.20 or nas.local, so this address will be blocked. Use https://, or the server’s local IP address.", true)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Title lives in the scrolling content (not `.navigationTitle`),
                // otherwise the fixed large title bleeds through the form as the
                // content scrolls under it.
                Text(editingServer == nil ? "Add server" : "Edit server")
                    .font(.largeTitle).fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)

                fieldGroup("Server details") {
                    field("Server name") {
                        TextField("My Navidrome", text: $name)
                    }
                    field("URL") {
                        TextField("https://music.example.com", text: $url)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                    }
                    // A sibling below the field, not a wrapper around it —
                    // fields stay plain and full-width on tvOS.
                    if let message = urlMessage {
                        Label(message.text, systemImage: message.isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(message.isError ? .red : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                fieldGroup("Credentials") {
                    field("Username") {
                        TextField("Username", text: $username)
                            .autocapitalization(.none)
                    }
                    field("Password") {
                        SecureField("Password", text: $password)
                    }
                }

                // Test connection
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            if isTesting { ProgressView().padding(.trailing, 4) }
                            Text(isTesting ? "Testing…" : "Test connection")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AccentPillButtonStyle())
                    .disabled(isTesting || !isValid)

                    if let result = testResult {
                        HStack(spacing: 10) {
                            Image(systemName: testSuccess == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(testSuccess == true ? .green : .red)
                            Text(result)
                                .foregroundColor(testSuccess == true ? .green : .red)
                                .font(.caption)
                                .lineLimit(3)
                        }
                    }
                }

                // Primary + destructive actions
                VStack(spacing: 12) {
                    Button {
                        save()
                    } label: {
                        Text("Save").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AccentPillButtonStyle())
                    .disabled(!isValid)

                    if editingServer != nil {
                        Button {
                            setActive()
                        } label: {
                            Label(isActive ? "Active server" : "Set as active server",
                                  systemImage: isActive ? "checkmark.circle.fill" : "circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AccentPillButtonStyle())
                        .disabled(isActive)

                        Button(role: .destructive) {
                            deleteServer()
                        } label: {
                            Label("Delete server", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(AccentPillButtonStyle())
                    }
                }
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)          // centre the column
            .padding(.top, AppLayout.contentTopPadding)
            .padding(.horizontal, AppLayout.horizontalPadding)
            .padding(.bottom, 120)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Field building blocks

    @ViewBuilder
    private func fieldGroup<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    // A single labelled, full-width text field. The field keeps its default
    // tvOS appearance (one capsule, turns light when focused) — no surrounding
    // container, so there's no nested-pill effect.
    @ViewBuilder
    private func field<F: View>(_ label: String, @ViewBuilder _ input: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            input()
                .font(.body)
        }
    }

    // MARK: - Actions

    private func testConnection() async {
        isTesting = true
        testResult = nil
        do {
            let ok = try await SubsonicClient.shared.ping(server: makeServer())
            testSuccess = ok
            testResult = ok ? "Connected successfully!" : "Ping failed"
        } catch {
            testSuccess = false
            testResult = error.localizedDescription
        }
        isTesting = false
    }

    private func save() {
        let server = makeServer()
        if editingServer == nil {
            appState.serverStore.add(server)
        } else {
            appState.serverStore.update(server)
        }
        appState.syncActiveServer()
        dismiss()
    }

    private func setActive() {
        guard let s = editingServer else { return }
        appState.serverStore.activeServerID = s.id
        appState.syncActiveServer()
    }

    private func deleteServer() {
        guard let s = editingServer else { return }
        appState.serverStore.delete(s)
        appState.syncActiveServer()
        dismiss()
    }

    private func makeServer() -> Server {
        if case .edit(var s) = mode {
            s.name = name; s.url = url; s.username = username; s.password = password
            return s
        }
        return Server(name: name, url: url, username: username, password: password)
    }
}
