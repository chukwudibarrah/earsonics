// earsonics-iOS/ContentView.swift
import SwiftUI
import EarsonicsCore

/// Stage 1 of the iPhone/iPad app: just enough to prove the foundation (sign
/// in, browse, play) works on a phone. Stage 2 replaces it with the real tab
/// bar (iPhone) and sidebar (iPad).
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var editingServer = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.serverStore.activeServer == nil {
                    ServerSignInView()
                } else {
                    NewestAlbumsList()
                        .toolbar {
                            Button("Server", systemImage: "server.rack") { editingServer = true }
                        }
                        .sheet(isPresented: $editingServer) {
                            NavigationStack { ServerSignInView(editing: appState.serverStore.activeServer) }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { NowPlayingStrip() }
    }
}

/// The server's newest albums; tapping one plays it.
private struct NewestAlbumsList: View {
    @Environment(AppState.self) private var appState
    @State private var albums: [Album] = []
    @State private var failure: String?

    var body: some View {
        List(albums) { album in
            Button {
                Task { await play(album) }
            } label: {
                HStack(spacing: 14) {
                    CoverArtThumbnail(id: album.coverArt)
                    VStack(alignment: .leading) {
                        Text(album.name).font(.headline).lineLimit(1)
                        Text(album.artist ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .foregroundStyle(.primary)
        }
        .overlay {
            if let failure { ContentUnavailableView("Couldn’t load albums", systemImage: "wifi.exclamationmark", description: Text(failure)) }
        }
        .navigationTitle("Just arrived")
        .task(id: appState.activeServerID) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            albums = try await SubsonicClient.shared.getAlbumList(type: "newest", size: 30)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    private func play(_ album: Album) async {
        do {
            let songs = try await SubsonicClient.shared.getAlbum(id: album.id).songs ?? []
            guard !songs.isEmpty else { return }
            AudioPlayerService.shared.load(songs: songs, startIndex: 0, context: .album(id: album.id))
        } catch {
            Messages.shared.showFailure("play “\(album.name)”", error)
        }
    }
}

/// A small cover, loaded through the shared artwork cache.
private struct CoverArtThumbnail: View {
    let id: String?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Color.secondary.opacity(0.2).overlay(Image(systemName: "music.note").foregroundStyle(.secondary)) }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: id) {
            guard let id, let server = SubsonicClient.shared.server,
                  let url = SubsonicClient.shared.coverArtURL(id: id, size: 112, server: server) else { return }
            image = await ImageCache.shared.image(for: id, size: 112, serverID: server.id, url: url)
        }
    }
}

/// What's playing, with play/pause. Stage 3 replaces it with the mini
/// player and full Now Playing screen.
private struct NowPlayingStrip: View {
    private let player = AudioPlayerService.shared

    var body: some View {
        if let song = player.currentSong {
            HStack {
                VStack(alignment: .leading) {
                    Text(song.title).font(.subheadline.bold()).lineLimit(1)
                    Text(song.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
                    player.togglePlayPause()
                }
                .labelStyle(.iconOnly)
                .font(.title2)
            }
            .padding()
            .background(.bar)
        }
    }
}

/// Add or edit a server. Same checks as the Apple TV editor; the password
/// goes to the Keychain via ServerStore.
struct ServerSignInView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    var editing: Server? = nil

    @State private var name = ""
    @State private var url = "https://"
    @State private var username = ""
    @State private var password = ""
    @State private var testResult: String?
    @State private var isTesting = false

    private var urlCheck: Server.URLCheck { Server.check(url: url) }
    private var isValid: Bool { !name.isEmpty && urlCheck != .invalid && !username.isEmpty && !password.isEmpty }

    var body: some View {
        Form {
            Section("Server") {
                TextField("Name", text: $name)
                TextField("Address", text: $url)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                if urlCheck == .unencryptedPublic {
                    Text("This connection isn’t encrypted. Use https:// if your server supports it.").font(.footnote).foregroundStyle(.orange)
                } else if urlCheck == .blockedHTTPDomain {
                    Text("Unencrypted (http://) connections only work to local addresses such as 192.168.1.20. Use https://.").font(.footnote).foregroundStyle(.red)
                }
            }
            Section("Account") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password", text: $password)
            }
            Section {
                Button(isTesting ? "Testing…" : "Test connection") { Task { await test() } }
                    .disabled(!isValid || isTesting)
                if let testResult { Text(testResult).font(.footnote).foregroundStyle(.secondary) }
                Button("Save") { save() }.disabled(!isValid)
            }
        }
        .navigationTitle(editing == nil ? "Add a server" : "Edit server")
        .onAppear {
            guard let editing else { return }
            name = editing.name; url = editing.url; username = editing.username; password = editing.password
        }
    }

    private func makeServer() -> Server {
        if var server = editing {
            server.name = name; server.url = url; server.username = username; server.password = password
            return server
        }
        return Server(name: name, url: url, username: username, password: password)
    }

    private func test() async {
        isTesting = true
        defer { isTesting = false }
        do {
            testResult = try await SubsonicClient.shared.ping(server: makeServer()) ? "Connected successfully" : "The server didn’t respond as expected"
        } catch {
            testResult = error.localizedDescription
        }
    }

    private func save() {
        let server = makeServer()
        if editing == nil { appState.serverStore.add(server) } else { appState.serverStore.update(server) }
        appState.serverStore.activeServerID = server.id
        appState.syncActiveServer()
        dismiss()
    }
}

#Preview {
    ContentView().environment(AppState.shared)
}
