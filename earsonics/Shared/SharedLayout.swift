// Shared/SharedLayout.swift
import CoreFoundation
import SwiftUI

enum AppLayout {
    static let horizontalPadding: CGFloat = 80
    static let verticalSpacing: CGFloat = 40
    static let miniPlayerHeight: CGFloat = 100
    static let miniPlayerTopOffset: CGFloat = 60
}

/// Deprecated: Use safeAreaInset architecture instead.
let layoutTopPaddingBase: CGFloat = 100

/// Top padding when the MiniPlayerBar is visible (bar starts at y=60, height=100 → bottom ≈ y=160, +15 breathing room).
let layoutTopPaddingWithPlayer: CGFloat = 175

/// Returns the correct top padding based on whether the mini player is currently active.
func layoutTopPadding(playerActive: Bool) -> CGFloat {
    playerActive ? layoutTopPaddingWithPlayer : layoutTopPaddingBase
}
