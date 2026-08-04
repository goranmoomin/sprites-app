// swift-tools-version: 6.2
import PackageDescription

// See: https://www.massicotte.org/blog/what-settings/
let swiftSettings: [SwiftSetting] = [
    // Approachable Concurrency
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Sprites",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SpritesCore", targets: ["SpritesCore"]),
        .library(name: "SpritesUI", targets: ["SpritesUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/mattt/Replay.git", from: "0.4.0")
    ],
    targets: [
        .target(name: "SpritesCore", swiftSettings: swiftSettings),
        .target(
            name: "SpritesUI",
            dependencies: ["SpritesCore"],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "SpritesCoreTests",
            dependencies: [
                "SpritesCore",
                .product(name: "Replay", package: "Replay"),
            ],
            resources: [.copy("Replays")],
            swiftSettings: swiftSettings,
        ),
    ]
)
