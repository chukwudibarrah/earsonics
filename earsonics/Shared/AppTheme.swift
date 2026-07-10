// Shared/AppTheme.swift
import SwiftUI

/// The palette of highlight colours the user can pick from in Settings.
/// The chosen colour drives focus outlines, the now-playing glow and
/// play/pause indicators throughout the app.
enum AccentColorChoice: String, CaseIterable, Identifiable {
    case orange, red, pink, purple, blue, teal, green, yellow

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .orange: .orange
        case .red:    .red
        case .pink:   .pink
        case .purple: .purple
        case .blue:   .blue
        case .teal:   .teal
        case .green:  .green
        case .yellow: .yellow
        }
    }

    var displayName: String { rawValue.capitalized }
}

extension EnvironmentValues {
    /// The user-selected highlight colour. Set once at the app root from
    /// `AppState.accentColor`; read wherever the accent is needed.
    @Entry var appAccent: Color = AccentColorChoice.orange.color
}
