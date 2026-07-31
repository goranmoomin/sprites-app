import Foundation

/// Integration category: one integration per role, not per product.
public enum IntegrationRole: String, Sendable, Equatable {
    /// Manages an Agent's login on a Sprite (Claude Code, Codex, Gemini CLI).
    case codingAgent
    /// Runs a Service exposing the Sprite to a client app (T3 Code).
    case controlPlane
}

/// A cross-integration dependency, declared not implied.
public enum IntegrationRequirement: Sendable, Equatable {
    case loggedInCodingAgent
}

/// One integration's observed status on one Sprite (never app-side memory).
public struct IntegrationStatus: Sendable, Equatable {
    /// Status line detail, e.g. "logged in", "service running", "not set up".
    public var summary: String
    /// Whether the integration is usable (logged in / service running).
    public var isReady: Bool

    public init(summary: String, isReady: Bool) {
        self.summary = summary
        self.isReady = isReady
    }
}

/// A one-tap operation on the sprite detail screen.
public struct SpriteAction: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var url: URL?

    public init(id: String, title: String, url: URL? = nil) {
        self.id = id
        self.title = title
        self.url = url
    }
}

/// First-party support for one third-party capability on a Sprite: observes
/// its own status, recognizes Services as its instances by command match,
/// and contributes Actions. Flows are added per integration.
public protocol Integration: Sendable {
    var id: String { get }
    var displayName: String { get }
    var role: IntegrationRole { get }
    var requirements: [IntegrationRequirement] { get }

    /// Command-match recognizer. Service names are ignored.
    func recognizes(_ service: Service) -> Bool

    /// Deep observation of this integration's state on the sprite.
    func observeStatus(on sprite: String, services: [Service], platform: SpritesPlatform)
        async throws -> IntegrationStatus

    /// Actions contributed given the currently observed services.
    func actions(services: [Service], metadata: SpriteMetadata?) -> [SpriteAction]
}

/// The MVP registry: exactly two integrations.
public enum Integrations {
    public static let claudeCode = ClaudeCodeIntegration()
    public static let t3Code = T3CodeIntegration()
    public static var all: [any Integration] { [claudeCode, t3Code] }
}
