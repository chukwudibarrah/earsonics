// Views/Shared/FocusableProgressView.swift
import SwiftUI

/// A full-screen loading indicator that can hold focus.
///
/// On tvOS a screen with nothing focusable is a trap: nothing receives focus,
/// the sidebar can't be reached, and Menu falls through to the system and
/// exits the app. Use this instead of a bare `ProgressView` for any state
/// that can be the only thing on screen. It shows no focus effect of its own.
struct FocusableProgressView: View {
    let title: String

    var body: some View {
        ProgressView(title)
            .font(.headline)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable()
    }
}
