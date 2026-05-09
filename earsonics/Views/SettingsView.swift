// Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var gaplessCrossfade: Double = 0

    var body: some View {
        NavigationStack {
            List {
                // Server management section
                Section("Servers") {
                    NavigationLink {
                        ServerManagementView()
                    } label: {
                        HStack {
                            Label("Manage servers", systemImage: "server.rack")
                            Spacer()
                            if let server = appState.serverStore.activeServer {
                                Text(server.name).foregroundColor(.secondary).font(.callout)
                            }
                        }
                    }

                    if let server = appState.serverStore.activeServer {
                        HStack {
                            Label("Status", systemImage: appState.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(appState.isConnected ? .green : .red)
                            Spacer()
                            Text(appState.isConnected ? "Connected" : "Disconnected")
                                .foregroundColor(appState.isConnected ? .green : .red)
                        }
                        Button {
                            Task { await appState.testConnection(server: server) }
                        } label: {
                            Label("Test connection", systemImage: "arrow.clockwise")
                        }
                    }
                }

                // Playback section
                Section("Playback") {
                    LabeledContent("Quality") {
                        Text("Original (Lossless)")
                            .foregroundColor(.secondary)
                    }

                    Button {
                        gaplessCrossfade = gaplessCrossfade >= 10 ? 0 : gaplessCrossfade + 0.5
                        appState.player.gaplessCrossfade = gaplessCrossfade
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Gapless crossfade")
                                Text("0 = true gapless (recommended for live albums)")
                                    .font(.caption)
                            }
                            Spacer()
                            Text(gaplessCrossfade == 0 ? "Off (true gapless)" : String(format: "%.1fs", gaplessCrossfade))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // About section
                Section("About") {
                    HStack { Text("App"); Spacer(); Text("earsonics").foregroundColor(.secondary) }
                    HStack { Text("Version"); Spacer(); Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0").foregroundColor(.secondary) }
                    HStack { Text("Protocol"); Spacer(); Text("Subsonic / Navidrome").foregroundColor(.secondary) }
                    HStack { Text("Platform"); Spacer(); Text("Apple TV").foregroundColor(.secondary) }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                gaplessCrossfade = appState.player.gaplessCrossfade
            }
        }
    }
}
