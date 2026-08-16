import Foundation

/// The Board row an Integration declares itself into (CONTEXT.md
/// Category). Grouping only; carries no requirement semantics.
public enum Category: Sendable, Equatable, CaseIterable {
    /// Manages an Agent's login (Claude Code, Codex, Gemini CLI).
    case codingAgent
    /// Runs a Service exposing the Sprite to a client app (T3 Code).
    case controlPlane
    case other

    /// Board row title.
    public var displayName: String {
        switch self {
        case .codingAgent: "Coding agents"
        case .controlPlane: "Control planes"
        case .other: "Other"
        }
    }
}

/// What a Flow needs on the Sprite before it runs (CONTEXT.md
/// Requirement): a set of Integration ids, any one observed ready
/// satisfies it. A Flow needs all of its Requirements (ADR 0008).
public struct Requirement: Sendable, Equatable {
    public let anyOf: [String]

    public init(anyOf: [String]) {
        self.anyOf = anyOf
    }
}

/// One integration's observed status on one Sprite (never app-side memory).
public struct IntegrationStatus: Sendable, Equatable {
    /// One observed fact worth showing under the summary (account, version,
    /// address); every value is copyable in the UI.
    public struct Detail: Sendable, Equatable, Identifiable {
        public var label: String
        public var value: String
        public var id: String { label }

        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    /// Status line, e.g. "logged in", "service running", "not set up".
    public var summary: String
    /// Whether the integration is usable (logged in / service running).
    public var isReady: Bool
    /// Ordered as the integration wants them shown.
    public var details: [Detail]

    public init(summary: String, isReady: Bool, details: [Detail] = []) {
        self.summary = summary
        self.isReady = isReady
        self.details = details
    }
}

/// First-party support for one third-party capability on a Sprite: observes
/// its own status, recognizes Services as its instances by command match,
/// and contributes Actions. Flows are added per integration.
public protocol Integration: Sendable {
    var id: String { get }
    var displayName: String { get }
    var category: Category { get }

    /// Command-match recognizer. Service names are ignored.
    func recognizes(_ service: Service) -> Bool

    /// Deep observation of this integration's state on the sprite.
    func observeStatus(on sprite: String, services: [Service], platform: SpritesPlatform)
        async throws -> IntegrationStatus

    /// Actions contributed given the currently observed services.
    func actions(services: [Service], metadata: SpriteMetadata?) -> [SpriteAction]

    /// Flows currently offered given this integration's observed context.
    /// Per-integration ordering is the integration's own; callers keep
    /// cross-integration registry order.
    func flows(status: IntegrationStatus, services: [Service], metadata: SpriteMetadata?) -> [Flow]

    /// The Saved login this integration keeps in the store, as the app
    /// menu's display line; nil when it keeps none.
    func describeSavedLogin(in store: any SavedLoginStore) -> String?
}

extension Integration {
    public func describeSavedLogin(in store: any SavedLoginStore) -> String? { nil }
}

/// The registry.
public enum Integrations {
    /// The one app-side store every integration's Saved login lives in.
    public static let savedLogins: any SavedLoginStore = KeychainSavedLoginStore()
    public static let claudeCode = ClaudeCodeIntegration()
    public static let t3Code = T3CodeIntegration()
    public static let github = GitHubIntegration()
    public static let tailscale = TailscaleIntegration()
    public static var all: [any Integration] { [claudeCode, t3Code, github, tailscale] }

    /// The one place Requirement satisfaction is computed: the first of the
    /// named integrations observed ready on the sprite (deep observation,
    /// never app-side memory), or nil when none is.
    public static func readyProvider(
        among ids: [String], on sprite: String, services: [Service],
        platform: SpritesPlatform, among integrations: [any Integration] = Integrations.all
    ) async -> (integration: any Integration, status: IntegrationStatus)? {
        for integration in integrations where ids.contains(integration.id) {
            guard
                let status = try? await integration.observeStatus(
                    on: sprite, services: services, platform: platform),
                status.isReady
            else { continue }
            return (integration, status)
        }
        return nil
    }

    /// The blocked sentence for the first unmet Requirement of a flow, or
    /// nil when every Requirement is met. Names products, never categories.
    public static func unmetRequirementReason(
        of flow: Flow, on sprite: String, platform: SpritesPlatform,
        among integrations: [any Integration] = Integrations.all
    ) async -> String? {
        guard !flow.requires.isEmpty else { return nil }
        // Providers observe against the sprite's Services (a daemon is a
        // Service), so they are read once here.
        let services = (try? await platform.services(on: sprite)) ?? []
        for requirement in flow.requires {
            let met = await readyProvider(
                among: requirement.anyOf, on: sprite, services: services, platform: platform,
                among: integrations) != nil
            guard !met else { continue }
            return blockedSentence(for: requirement, among: integrations)
        }
        return nil
    }

    /// The blocked sentence for one unmet Requirement; names products,
    /// never categories.
    public static func blockedSentence(
        for requirement: Requirement, among integrations: [any Integration] = Integrations.all
    ) -> String {
        let names = requirement.anyOf.compactMap { id in
            integrations.first { $0.id == id }?.displayName
        }
        return "This needs \(names.joined(separator: " or ")) ready on this sprite. Run its Flow first."
    }
}
