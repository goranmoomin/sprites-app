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

    // MARK: Services (deep; wakes a cold Sprite)
    /// Creates or updates a service, streaming the platform's NDJSON progress.
    func upsertService(on sprite: String, named name: String, definition: ServiceDefinition)
        async throws -> AsyncThrowingStream<ServiceUpsertEvent, Error>
    func startService(on sprite: String, named name: String) async throws
    func stopService(on sprite: String, named name: String) async throws
    func deleteService(on sprite: String, named name: String) async throws
    func serviceLogs(on sprite: String, named name: String, lines: Int) async throws -> String

    // MARK: Exec (deep; wakes a cold Sprite)
    func exec(on sprite: String, command: ExecCommand) async throws -> any ExecSession
}
