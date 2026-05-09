// Views/Shared/FocusStyle.swift
import SwiftUI

// Deprecated: We will use native tvOS `.buttonStyle(.card)` or `.buttonStyle(.plain)`
// instead of trying to manually handle focus scaling and colors. 
// This file is kept only for backwards compatibility temporarily.
extension Color {
    static let focusFill = Color(white: 0.14)
}

struct CardlessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}
