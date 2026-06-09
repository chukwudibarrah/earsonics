// Views/Shared/ScrollingText.swift
import SwiftUI

/// A single-line text view that scrolls (marquee) when the content overflows its container.
/// Pauses and snaps back to the start when `isFocused` is true.
/// Resets and restarts the animation whenever `trackID` changes.
struct ScrollingText: View {
    let text: String
    var trackID: String = ""
    var isFocused: Bool = false

    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private var needsScrolling: Bool {
        textWidth > containerWidth + 1 && containerWidth > 0
    }

    var body: some View {
        GeometryReader { proxy in
            Text(text)
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
        .onChange(of: trackID) { _, _ in
            stopAndReset()
            // Brief delay so the reset settles before restarting animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                startScroll()
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                // Snap to start instantly — a mid-scroll freeze looks like a bug
                stopAndReset()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    startScroll()
                }
            }
        }
    }

    private func startScroll() {
        guard needsScrolling, !isFocused else { return }
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
