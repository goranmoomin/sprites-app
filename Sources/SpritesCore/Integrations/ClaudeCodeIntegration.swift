import Foundation

/// Coding-agent integration for Claude Code. "Logged in" is observed from
/// the CLI's own auth probe on the Sprite, never remembered app-side.
public struct ClaudeCodeIntegration: Integration {
    public let id = "claude-code"
    public let displayName = "Claude Code"
    public let provides: [Capability] = [.codingAgent]
    public let requires: [Capability] = []

    /// The legacy credential store `claude auth login` used to write; the
    /// setup-token login never creates it. Logout still sweeps it so
    /// Sprites logged in under the old flow come out clean.
    public static let credentialsPath = "/home/sprite/.claude/.credentials.json"
    /// User-level Claude settings: the Heartbeat hooks and the planted
    /// login token both live here.
    public static let settingsPath = "/home/sprite/.claude/settings.json"
    /// The CLI's browser-open attempt logs the full authorize URL here
    /// (observed live); login Flows sweep it.
    public static let xdgOpenLogPath = "/tmp/xdg-open.log"

    /// The app-side saved login the branching login Flow reuses.
    public let loginStore: any ClaudeLoginStore

    public init(loginStore: any ClaudeLoginStore = KeychainClaudeLoginStore()) {
        self.loginStore = loginStore
    }

    public func recognizes(_ service: Service) -> Bool {
        // Claude Code login is not a Service; nothing to recognize.
        false
    }

    public func observeStatus(on sprite: String, services: [Service], platform: SpritesPlatform)
        async throws -> IntegrationStatus
    {
        // The CLI's own answer, so the app never re-implements the auth
        // precedence chain. It validates nothing (a planted fake token
        // still reports logged in); truth on demand is the Flow's verify
        // step. Exits 1 when logged out, so parse the JSON, not the code.
        let result = try await platform.runCapturing(
            on: sprite, ["claude", "auth", "status", "--json"])
        let loggedIn = (try? JSONSerialization.jsonObject(with: result.stdout))
            .flatMap { $0 as? [String: Any] }
            .flatMap { $0["loggedIn"] as? Bool } ?? false
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
