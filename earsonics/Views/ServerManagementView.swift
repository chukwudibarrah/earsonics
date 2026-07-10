// Views/ServerManagementView.swift
import SwiftUI

struct ServerManagementView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(appState.serverStore.servers) { server in
                        NavigationLink {
                            ServerDetailView(server: server)
                        } label: {
                            ServerRow(server: server, isActive: server.id == appState.serverStore.activeServerID)
                        }
                    }
                }
                .padding(.bottom, 30)

                Section {
                    NavigationLink {
                        ServerEditView(mode: .add) { newServer in
                            appState.serverStore.add(newServer)
                            appState.syncActiveServer()
                        }
                    } label: {
                        Label("Add server", systemImage: "plus.circle.fill")
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("Servers")
            .padding(.horizontal, 60)
        }
    }
}

// MARK: - Server Detail
struct ServerDetailView: View {
    let server: Server
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Status") {
                if appState.serverStore.activeServerID == server.id {
                    Label("Active server", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Text("Inactive").foregroundColor(.secondary)
                }
            }

            Section("Server information") {
                LabeledContent("Name", value: server.name)
                LabeledContent("URL", value: server.baseURL)
                LabeledContent("Username", value: server.username)
            }

            Section("Actions") {
                Button("Set as active server") {
                    appState.serverStore.activeServerID = server.id
                    appState.syncActiveServer()
                }
                .disabled(appState.serverStore.activeServerID == server.id)

                NavigationLink("Edit server details") {
                    ServerEditView(mode: .edit(server)) { updated in
                        appState.serverStore.update(updated)
                        appState.syncActiveServer()
                    }
                }

                Button(role: .destructive) {
                    appState.serverStore.delete(server)
                    dismiss()
                } label: {
                    Text("Delete server")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle(server.name)
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
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Server Edit View
struct ServerEditView: View {
    enum Mode {
        case add
        case edit(Server)
    }

    let mode: Mode
    let onSave: (Server) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @State private var name: String = ""
    @State private var url: String = "https://"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isTesting = false
    @State private var testResult: String? = nil
    @State private var testSuccess: Bool? = nil

    init(mode: Mode, onSave: @escaping (Server) -> Void) {
        self.mode = mode
        self.onSave = onSave
        if case .edit(let server) = mode {
            _name = State(initialValue: server.name)
            _url = State(initialValue: server.url)
            _username = State(initialValue: server.username)
            _password = State(initialValue: server.password)
        }
    }

    var isValid: Bool {
        !name.isEmpty && !url.isEmpty && !username.isEmpty && !password.isEmpty
    }

    var body: some View {
        Form {
            Section("Server details") {
                LabeledContent("Enter server name") {
                    TextField("My Navidrome", text: $name)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("URL") {
                    TextField("https://music.example.com", text: $url)
                        .multilineTextAlignment(.trailing)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                }
            }

            Section("Credentials") {
                LabeledContent("Username") {
                    TextField("Username", text: $username)
                        .multilineTextAlignment(.trailing)
                        .autocapitalization(.none)
                }
                LabeledContent("Password") {
                    SecureField("Password", text: $password)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView().scaleEffect(0.8).padding(.trailing, 8)
                        }
                        Text(isTesting ? "Testing..." : "Test connection")
                    }
                }
                .disabled(isTesting || !isValid)

                if let result = testResult {
                    HStack {
                        Image(systemName: testSuccess == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(testSuccess == true ? .green : .red)
                        Text(result)
                            .foregroundColor(testSuccess == true ? .green : .red)
                            .font(.caption)
                            .lineLimit(3)
                    }
                }
            }

            Section {
                Button("Save") {
                    save()
                }
                .disabled(!isValid)
            }
        }
        .navigationTitle(mode.title)
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        let server = makeServer()
        do {
            let ok = try await SubsonicClient.shared.ping(server: server)
            testSuccess = ok
            testResult = ok ? "Connected successfully!" : "Ping failed"
        } catch {
            testSuccess = false
            testResult = error.localizedDescription
        }
        isTesting = false
    }

    private func save() {
        onSave(makeServer())
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

private extension ServerEditView.Mode {
    var title: String {
        switch self {
        case .add: return "Add server"
        case .edit: return "Edit server"
        }
    }
}
