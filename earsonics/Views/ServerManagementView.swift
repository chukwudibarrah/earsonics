// Views/ServerManagementView.swift
import SwiftUI

struct ServerManagementView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddServer = false
    @State private var editingServer: Server? = nil
    @FocusState private var focusedServerID: UUID?

    var body: some View {
        NavigationStack {
            List {
                Section("Servers") {
                    ForEach(appState.serverStore.servers) { server in
                        ServerRow(server: server, isActive: server.id == appState.serverStore.activeServerID)
                            .contextMenu {
                                Button {
                                    editingServer = server
                                } label: { Label("Edit", systemImage: "pencil") }
                                Button(role: .destructive) {
                                    appState.serverStore.delete(server)
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                            .onTapGesture {
                                appState.serverStore.activeServerID = server.id
                                appState.syncActiveServer()
                            }
                    }
                }

                Section {
                    Button {
                        showAddServer = true
                    } label: {
                        Label("Add Server", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                }
            }
            .navigationTitle("Servers")
            .sheet(isPresented: $showAddServer) {
                ServerEditView(mode: .add) { newServer in
                    appState.serverStore.add(newServer)
                    appState.syncActiveServer()
                }
            }
            .sheet(item: $editingServer) { server in
                ServerEditView(mode: .edit(server)) { updated in
                    appState.serverStore.update(updated)
                    appState.syncActiveServer()
                }
            }
        }
    }
}

struct ServerRow: View {
    let server: Server
    let isActive: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isActive ? .green : .gray)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name).font(.headline)
                Text(server.baseURL).font(.caption).foregroundColor(.secondary)
                Text("User: \(server.username)").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if isActive {
                Text("Active").font(.caption).foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
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
        NavigationStack {
            Form {
                Section("Server Details") {
                    LabeledContent("Name") {
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
                                ProgressView().scaleEffect(0.8)
                            }
                            Text(isTesting ? "Testing..." : "Test Connection")
                        }
                    }
                    .disabled(isTesting || !isValid)

                    if let result = testResult {
                        HStack {
                            Image(systemName: testSuccess == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(testSuccess == true ? .green : .red)
                            Text(result)
                                .foregroundColor(testSuccess == true ? .green : .red)
                        }
                    }
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
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
        case .add: return "Add Server"
        case .edit: return "Edit Server"
        }
    }
}
