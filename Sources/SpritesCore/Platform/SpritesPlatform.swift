import Foundation

/// The single seam to the Sprites platform. Everything the app does to a
/// Sprite goes through this protocol; the real implementation talks HTTP and
/// WebSocket, the fake simulates the platform in memory for tests.
public protocol SpritesPlatform: Sendable {
    // MARK: Shallow observation (never wakes a Sprite)
    func listSprites() async throws -> [SpriteMetadata]
    func getSprite(named name: String) async throws -> SpriteMetadata

    // MARK: Sprite CRUD
    func createSprite(named name: String) async throws -> SpriteMetadata
    func deleteSprite(named name: String) async throws

    // MARK: Waking (activity; only on user request or an already-running Sprite)
    /// Explicitly wakes a Sprite. Counts as deep activity.
    func wake(sprite: String) async throws

    // MARK: Deep observation (wakes a cold Sprite)
    func services(on sprite: String) async throws -> [Service]
    func listTasks(on sprite: String) async throws -> [PlatformTask]
    func checkpoints(on sprite: String) async throws -> [Checkpoint]

    // MARK: Exec (deep; wakes a cold Sprite)
    func exec(on sprite: String, command: ExecCommand) async throws -> any ExecSession
}
