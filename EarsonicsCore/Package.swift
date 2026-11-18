// swift-tools-version: 6.2
import PackageDescription

/// The code shared by every earsonics app (Apple TV now; iPhone, iPad and Mac
/// later): models, the Subsonic client, the play queue and player, caches,
/// queue sync, scrobbling and autoplay. No screens — each platform's app has
/// its own.
let package = Package(
    name: "EarsonicsCore",
    platforms: [.tvOS("26.4"), .iOS("26.4")],
    products: [
        .library(name: "EarsonicsCore", targets: ["EarsonicsCore"]),
    ],
    targets: [
        .target(
            name: "EarsonicsCore",
            // The same concurrency settings as the app targets (Swift 6,
            // main actor by default, Xcode's "approachable concurrency"), so
            // code behaves the same here as it did in the app.
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
