import Foundation

/// Integration category from CONTEXT.md, expressed as a capability an
/// integration provides on a Sprite or requires from other integrations.
public enum Capability: Sendable, Equatable {
    /// Manages an Agent's login on a Sprite (Claude Code, Codex, Gemini CLI).
    case codingAgent
    /// Runs a Service exposing the Sprite to a client app (T3 Code).
    case controlPlane

    /// Human-readable category name, e.g. in blocked-entry explanations.
    public var displayName: String {
        switch self {
        case .codingAgent: "coding agent"
        case .controlPlane: "control plane"
        }
    }
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

/// First-party support for one third-party capability on a Sprite: observes
/// its own status, recognizes Services as its instances by command match,
/// and contributes Actions. Flows are added per integration.
public protocol Integration: Sendable {
    var id: String { get }
    var displayName: String { get }
    var provides: [Capability] { get }
    var requires: [Capability] { get }

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

    /// The one place capability satisfaction is computed: a required
    /// capability is met when some integration providing it is observed
    /// ready on the sprite (deep observation, never app-side memory).
    public static func readyProvider(
        of capability: Capability, on sprite: String, services: [Service],
        platform: SpritesPlatform, among integrations: [any Integration] = Integrations.all
    ) async -> (integration: any Integration, status: IntegrationStatus)? {
        for integration in integrations where integration.provides.contains(capability) {
            guard
                let status = try? await integration.observeStatus(
                    on: sprite, services: services, platform: platform),
                status.isReady
            else { continue }
            return (integration, status)
        }
        return nil
    }
}
