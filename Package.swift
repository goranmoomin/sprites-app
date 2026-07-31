// swift-tools-version: 6.1
import PackageDescription

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
        .target(name: "SpritesCore"),
        .target(name: "SpritesUI", dependencies: ["SpritesCore"]),
        .testTarget(
            name: "SpritesCoreTests",
            dependencies: [
                "SpritesCore",
                .product(name: "Replay", package: "Replay"),
            ],
            resources: [.copy("Replays")]
        ),
    ]
)
