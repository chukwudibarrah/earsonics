// earsonics-iOS/EarsonicsPhoneApp.swift
import SwiftUI
import EarsonicsCore

/// The iPhone and iPad app. Shares the core (EarsonicsCore) and app state
/// (SharedApp/) with the Apple TV app; its screens are its own.
@main
struct EarsonicsPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AppState.shared)
        }
        // Downloads finish while the app is closed; the system relaunches it
        // to hand them over.
        .backgroundTask(.urlSession(DownloadEngine.sessionIdentifier)) {
            await DownloadEngine.shared.backgroundEventsDelivered()
        }
    }
}
