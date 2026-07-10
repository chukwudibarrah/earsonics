// Shared/SharedLayout.swift
import CoreFoundation
import SwiftUI

enum AppLayout {
    static let horizontalPadding: CGFloat = 80
    static let verticalSpacing: CGFloat = 40

    /// Fixed height of the top safe-area strip that hosts the now-playing
    /// pill. Constant whether or not the pill is visible so content never
    /// jumps when playback starts or stops.
    static let topStripHeight: CGFloat = 100

    /// Height of the now-playing pill inside the top strip.
    static let miniPlayerHeight: CGFloat = 72

    /// Breathing room between the top strip and each screen's content.
    static let contentTopPadding: CGFloat = 24

    /// Top padding for detail screens (album, artist, playlist).
    static let detailTopPadding: CGFloat = 40
}
