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

    // MARK: URL settings
    /// Changes URL visibility. Only ever called after explicit user consent.
    func setURLVisibility(sprite: String, _ visibility: URLVisibility) async throws

    // MARK: Deep observation (wakes a cold Sprite)
    func services(on sprite: String) async throws -> [Service]
    func listTasks(on sprite: String) async throws -> [PlatformTask]
    /// Creates or refreshes a named task. Observed live: the API's POST is
    /// create-only (409 on an existing name); PUT is the upsert.
    func upsertTask(on sprite: String, named name: String, expiringInSeconds seconds: Int) async throws
    func deleteTask(on sprite: String, named name: String) async throws
    func checkpoints(on sprite: String) async throws -> [Checkpoint]
    /// Creates a checkpoint, streaming the platform's NDJSON progress.
    func createCheckpoint(on sprite: String, comment: String)
        async throws -> AsyncThrowingStream<CheckpointEvent, Error>
    /// Destructive restore: captures disk, not running processes.
    func restoreCheckpoint(on sprite: String, id: String)
        async throws -> AsyncThrowingStream<CheckpointEvent, Error>

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
    /// Reattaches to a session that outlived its socket; scrollback replays
    /// as ordinary output. Throws if the session has ended.
    func attachExec(on sprite: String, sessionID: String) async throws -> any ExecSession
    func listExecSessions(on sprite: String) async throws -> [ExecSessionSummary]
    func killExecSession(on sprite: String, sessionID: String) async throws

    // MARK: In-sprite files (deep; wakes a cold Sprite)
    func fileExists(on sprite: String, path: String) async throws -> Bool
    func readFile(on sprite: String, path: String) async throws -> String?
    func writeFile(on sprite: String, path: String, content: String) async throws
}
