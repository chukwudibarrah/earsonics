// Views/Shared/FocusStyle.swift
import SwiftUI

extension Color {
    static let focusFill = Color(white: 0.14)

    /// Standard idle surface for cards and rows.
    static let cardFill = Color.white.opacity(0.08)
}

/// A button style with no system focus decoration and no magnification —
/// used everywhere the view draws its own focus treatment (accent ring).
struct CardlessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

/// Draws the user-selected accent outline and a soft matching glow around a
/// card while its enclosing button is focused. Apply *inside* the button
/// label, after any background/clipping, so ring and surface share a shape.
struct AccentFocusRing<S: InsettableShape>: ViewModifier {
    var shape: S
    @Environment(\.isFocused) private var isFocused
    @Environment(\.appAccent) private var appAccent

    func body(content: Content) -> some View {
        content
            .overlay {
                shape
                    .strokeBorder(appAccent, lineWidth: isFocused ? 4 : 0)
            }
            .shadow(color: isFocused ? appAccent.opacity(0.5) : .clear, radius: 20)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

extension View {
    /// Accent-coloured focus outline for card-shaped focusable content.
    func accentFocusRing(cornerRadius: CGFloat = 12) -> some View {
        modifier(AccentFocusRing(shape: RoundedRectangle(cornerRadius: cornerRadius)))
    }

    /// Accent-coloured focus outline following a custom shape.
    func accentFocusRing<S: InsettableShape>(_ shape: S) -> some View {
        modifier(AccentFocusRing(shape: shape))
    }

    /// Standard card/row treatment: neutral surface clipped to the same
    /// rounded rectangle the focus ring strokes, so artwork corners and the
    /// ring always agree. No magnification on focus.
    func cardSurface(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(Color.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .accentFocusRing(cornerRadius: cornerRadius)
    }
}

/// Bare icon/text button: transparent while idle, a translucent accent
/// capsule behind the label when focused, never magnified. For small
/// controls (dismiss chevrons, clear-search, hearts) whose labels keep
/// their own colours.
struct AccentIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconLabel(configuration: configuration)
    }

    private struct IconLabel: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.appAccent) private var appAccent

        var body: some View {
            configuration.label
                .padding(12)
                .background(isFocused ? appAccent.opacity(0.35) : .clear, in: Capsule())
                .opacity(configuration.isPressed ? 0.8 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isFocused)
        }
    }
}

/// Pill-shaped action button (Play, Shuffle, Star…): neutral while idle,
/// filled with the accent colour when focused, never magnified.
struct AccentPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PillLabel(configuration: configuration)
    }

    private struct PillLabel: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.appAccent) private var appAccent

        var body: some View {
            configuration.label
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    isFocused ? AnyShapeStyle(appAccent) : AnyShapeStyle(Color.cardFill),
                    in: Capsule()
                )
                .foregroundStyle(isFocused ? Color.black : Color.primary)
                .opacity(configuration.isPressed ? 0.8 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isFocused)
        }
    }
}
