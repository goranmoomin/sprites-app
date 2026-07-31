import Foundation

/// The single seam to the Sprites platform. Everything the app does to a
/// Sprite goes through this protocol; the real implementation talks HTTP and
/// WebSocket, the fake simulates the platform in memory for tests.
public protocol SpritesPlatform: Sendable {
    // MARK: Shallow observation (never wakes a Sprite)
    func listSprites() async throws -> [SpriteMetadata]
}
