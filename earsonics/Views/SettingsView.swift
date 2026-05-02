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
                            Label("Manage Servers", systemImage: "server.rack")
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
                            Label("Test Connection", systemImage: "arrow.clockwise")
                        }
                    }
                }

                // Playback section
                Section("Playback") {
                    LabeledContent("Quality") {
                        Text("Original (Lossless)")
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Gapless Crossfade")
                            Spacer()
                            Button {
                                gaplessCrossfade = gaplessCrossfade >= 10 ? 0 : gaplessCrossfade + 0.5
                                appState.player.gaplessCrossfade = gaplessCrossfade
                            } label: {
                                Text(gaplessCrossfade == 0 ? "Off (True Gapless)" : String(format: "%.1fs", gaplessCrossfade))
                            }
                        }
                        Text("0 = true gapless (recommended for live albums)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                // About section
                Section("About") {
                    LabeledContent("App", value: "earsonics")
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Protocol", value: "Subsonic / Navidrome")
                    LabeledContent("Platform", value: "Apple TV")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                gaplessCrossfade = appState.player.gaplessCrossfade
            }
        }
    }
}
