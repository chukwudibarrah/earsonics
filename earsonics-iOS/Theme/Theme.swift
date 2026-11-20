// earsonics-iOS/Theme/Theme.swift
import SwiftUI
import EarsonicsCore
import UIKit

/// The look the user picked in Settings. Dark by default: the app's midnight
/// palette is designed around it.
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, dark, light

    static let key = "appearance"
    static let defaultValue = AppearanceChoice.dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .dark:   "Dark"
        case .light:  "Light"
        }
    }

    /// nil follows the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark:   .dark
        case .light:  .light
        }
    }
}

/// Colours that adapt to light and dark: a deep midnight navy in dark mode,
/// soft blue-greys in light mode.
enum Palette {
    static let background = Color(light: 0xF2F4F9, dark: 0x070A13)
    /// Where the background gradient starts, at the top of the screen.
    static let backgroundGlow = Color(light: 0xFFFFFF, dark: 0x141B33)
    static let card = Color(light: 0xFFFFFF, dark: 0x111727)
    /// Chips, icon tiles and pills on a card.
    static let raised = Color(light: 0xE9ECF4, dark: 0x1C2440)
    static let hairline = Color(light: 0xDDE1EC, dark: 0x232B45)
    /// Subtitles and supporting text, tinted towards the palette.
    static let secondaryText = Color(light: 0x4E5870, dark: 0xA3AFD2)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

extension View {
    /// The screen background: a soft glow at the top fading into the base
    /// colour. Only the background reaches under the bars.
    func appBackground() -> some View {
        background {
            LinearGradient(colors: [Palette.backgroundGlow, Palette.background],
                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.45))
                .ignoresSafeArea()
        }
    }

    /// A rounded card on the background.
    func card(cornerRadius: CGFloat = 24, padding: CGFloat? = 16) -> some View {
        self
            .padding(padding.map { EdgeInsets(top: $0, leading: $0, bottom: $0, trailing: $0) } ?? EdgeInsets())
            .background(Palette.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
    }
}

/// A section's title with a one-line description under it, and an optional
/// "See all" link.
struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var seeAll: Route? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold())
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(Palette.secondaryText)
                }
            }
            Spacer(minLength: 12)
            if let seeAll {
                NavigationLink(value: seeAll) {
                    Text("See all").font(.subheadline.weight(.semibold))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A rounded tile holding an SF Symbol, for list rows.
struct IconTile: View {
    let systemImage: String
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.tint)
            .frame(width: size, height: size)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A small capsule with a count, e.g. "138 songs".
struct CountPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Palette.raised, in: Capsule())
    }
}

/// Large capsule buttons for Play and Shuffle on detail pages.
struct PlayShuffleButtons: View {
    let play: () -> Void
    let shuffle: () -> Void
    var isBusy = false
    /// What this page plays. While that's what's playing, Play becomes
    /// Pause (and Resume when paused) instead of starting it over.
    var context: PlayContext? = nil
    /// For mix lists, the page's name (see `PlaySource`).
    var source: String? = nil
    private let player = AudioPlayerService.shared

    private var isThisPlaying: Bool {
        guard player.currentSong != nil else { return false }
        if let source { return PlaySource.shared.isPlaying(source) }
        guard let context, context != .mix else { return false }
        return player.playQueue.context == context
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if isThisPlaying { player.togglePlayPause() } else { play() }
            } label: {
                Group {
                    if isThisPlaying && player.isPlaying {
                        Label("Pause", systemImage: "pause.fill")
                    } else if isThisPlaying {
                        Label("Resume", systemImage: "play.fill")
                    } else {
                        Label("Play", systemImage: "play.fill")
                    }
                }
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            Button(action: shuffle) {
                Label("Shuffle", systemImage: "shuffle").labelStyle(.titleAndIcon).lineLimit(1).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
        .controlSize(.large)
        .disabled(isBusy)
        .overlay { if isBusy { ProgressView() } }
    }
}

/// Play and Shuffle with smaller round buttons beside them, or below them
/// when the row would squeeze the labels.
struct PlayShuffleRow<Extras: View>: View {
    let play: () -> Void
    let shuffle: () -> Void
    var isBusy = false
    var context: PlayContext? = nil
    @ViewBuilder let extras: () -> Extras

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                PlayShuffleButtons(play: play, shuffle: shuffle, isBusy: isBusy, context: context).fixedSize()
                extras()
            }
            VStack(spacing: 12) {
                PlayShuffleButtons(play: play, shuffle: shuffle, isBusy: isBusy, context: context)
                HStack(spacing: 12) { extras() }
            }
        }
    }
}

extension Int {
    /// "1 song", "12 songs".
    func counted(_ singular: String, _ plural: String? = nil) -> String {
        "\(formatted()) \(self == 1 ? singular : (plural ?? singular + "s"))"
    }
}

/// "2h 35m" or "41m" for a total number of seconds.
func durationText(seconds: Int) -> String {
    let hours = seconds / 3600, minutes = (seconds % 3600) / 60
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
}
