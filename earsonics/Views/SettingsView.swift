// Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showDonationQR = false

    var body: some View {
        NavigationStack {
            Form {
                // Server management section
                Section(header: Text("Servers").font(.headline)) {
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
                .padding(.vertical, 20)

                // Playback section
                Section(header: Text("Playback").font(.headline)) {
                    LabeledContent("Quality") {
                        Text("Original (lossless)")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 20)

                // About section
                Section(header: Text("About").font(.headline)) {
                    Button {
                        showDonationQR = true
                    } label: {
                        HStack {
                            Text("QR code me a coffee")
                            Spacer()
                            Text("Show QR")
                                .foregroundColor(.secondary)
                        }
                    }
                    .sheet(isPresented: $showDonationQR) {
                        VStack(spacing: 40) {
                            Text("Scan to donate a coffee!")
                                .font(.largeTitle)
                            
                            Image("paypalme")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 500, height: 500)
                            
                            Button("Close") {
                                showDonationQR = false
                            }
                        }
                        .padding()
                    }

                    HStack { Text("App"); Spacer(); Text("earsonics").foregroundColor(.secondary) }
                        .focusable()
                    HStack { Text("Version"); Spacer(); Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.01").foregroundColor(.secondary) }
                        .focusable()
                    HStack { Text("Protocol"); Spacer(); Text("Subsonic/Navidrome").foregroundColor(.secondary) }
                        .focusable()
                    HStack { Text("Platform"); Spacer(); Text("Apple TV").foregroundColor(.secondary) }
                        .focusable()
                }
                .padding(.vertical, 20)
            }
        }
    }
}
