import Foundation

/// Coding-agent integration for Claude Code. "Logged in" is observed from
/// the credential file on the Sprite, never remembered app-side.
public struct ClaudeCodeIntegration: Integration {
    public let id = "claude-code"
    public let displayName = "Claude Code"
    public let provides: [Capability] = [.codingAgent]
    public let requires: [Capability] = []

    /// Where the claude CLI stores OAuth credentials on the sprite.
    public static let credentialsPath = "/home/sprite/.claude/.credentials.json"
    /// User-level Claude settings, where the Heartbeat hooks are installed.
    public static let settingsPath = "/home/sprite/.claude/settings.json"

    public init() {}

    public func recognizes(_ service: Service) -> Bool {
        // Claude Code login is not a Service; nothing to recognize.
        false
    }

    public func observeStatus(on sprite: String, services: [Service], platform: SpritesPlatform)
        async throws -> IntegrationStatus
    {
        let loggedIn = try await platform.fileExists(on: sprite, path: Self.credentialsPath)
        return IntegrationStatus(
            summary: loggedIn ? "logged in" : "not logged in",
            isReady: loggedIn
        )
    }

    public func actions(services: [Service], metadata: SpriteMetadata?) -> [SpriteAction] {
        []
    }

    public func flows(status: IntegrationStatus, services: [Service], metadata: SpriteMetadata?) -> [Flow] {
        status.isReady ? [] : [loginFlow()]
    }
}
