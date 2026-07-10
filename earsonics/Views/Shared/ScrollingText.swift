// Views/Shared/ScrollingText.swift
import SwiftUI

/// A single-line text view that scrolls (marquee) when the content overflows
/// its container. Resets and restarts whenever `trackID` changes.
///
/// The view sizes itself to the text's natural single-line height — callers
/// must NOT constrain it with `.frame(height:)`, which clips descenders.
///
/// Two modes:
/// - `.whenUnfocused` (default): scrolls continuously, snaps back to the
///   start while focused — used by the now-playing pill.
/// - `.whenFocused`: stays truncated at rest and scrolls only while the
///   enclosing card is focused — used by shelf cards.
struct ScrollingText: View {
    enum Mode {
        case whenUnfocused, whenFocused
    }

    let text: String
    var trackID: String = ""
    var isFocused: Bool = false
    var mode: Mode = .whenUnfocused

    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    /// Empty strings still occupy one full line so stacked labels keep
    /// every card the same height.
    private var displayText: String { text.isEmpty ? " " : text }

    private var needsScrolling: Bool {
        textWidth > containerWidth + 1 && containerWidth > 0
    }

    private var shouldScroll: Bool {
        mode == .whenFocused ? isFocused : !isFocused
    }

    var body: some View {
        // The hidden text gives the view its intrinsic single-line size;
        // the marquee copy renders in an overlay clipped to those bounds.
        Text(displayText)
            .lineLimit(1)
            .opacity(0)
            .overlay(
                GeometryReader { proxy in
                    Text(displayText)
                        .lineLimit(1)
                        .fixedSize()
                        .background(
                            GeometryReader { inner in
                                Color.clear.onAppear {
                                    containerWidth = proxy.size.width
                                    textWidth = inner.size.width
                                    startScroll()
                                }
                            }
                        )
                        .offset(x: offset)
                }
                .clipped()
            )
            .onChange(of: trackID) { _, _ in
                stopAndReset()
                // Brief delay so the reset settles before restarting animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    startScroll()
                }
            }
            .onChange(of: isFocused) { _, _ in
                if shouldScroll {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        startScroll()
                    }
                } else {
                    // Snap back to the start instantly — a mid-scroll freeze looks like a bug
                    stopAndReset()
                }
            }
    }

    private func startScroll() {
        guard needsScrolling, shouldScroll else { return }
        withAnimation(
            .linear(duration: Double(textWidth) / 40)
                .repeatForever(autoreverses: false)
                .delay(1.5)
        ) {
            offset = -(textWidth + 20)
        }
    }

    private func stopAndReset() {
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) { offset = 0 }
    }
}
