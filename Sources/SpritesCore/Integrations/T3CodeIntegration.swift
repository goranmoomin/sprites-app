import Foundation

/// Control-plane integration for T3 Code: recognizes `t3 serve` services by
/// command shape and contributes the Open in T3 Code handoff.
public struct T3CodeIntegration: Integration {
    public let id = "t3-code"
    public let displayName = "T3 Code"
    public let category = Category.controlPlane

    /// The coding agents T3 Code drives; every setup Flow requires one
    /// logged in.
    public static let supportedCodingAgents = Requirement(anyOf: [Integrations.claudeCode.id])

    /// The official T3 Code app's URL scheme for the handoff (verified
    /// against the t3code mobile source: scheme `t3code`, prod variant).
    public static let appURL = URL(string: "t3code://")!
    /// The app's Add Environment screen: the only pairing-aware surface;
    /// there is no `/pair` route and no universal link (verified in source).
    /// A pairing URL pasted into its Host field completes pairing.
    public static let addEnvironmentURL = URL(string: "t3code://connections/new")!

    public init() {}

    /// Recognized iff the command shape is `t3 serve ...`: an adjacent
    /// token pair (t3, serve) in [basename(cmd)] + args. Names are ignored;
    /// launcher wrappers like `npx t3 serve` still match.
    public func recognizes(_ service: Service) -> Bool {
        let tokens = ([service.cmd] + service.args).map {
            $0.split(separator: "/").last.map(String.init) ?? $0
        }
        return zip(tokens, tokens.dropFirst()).contains { $0 == ("t3", "serve") }
    }

    public func observeStatus(on sprite: String, services: [Service], platform: SpritesPlatform)
        async throws -> IntegrationStatus
    {
        let recognized = services.filter(recognizes)
        guard !recognized.isEmpty else {
            return IntegrationStatus(summary: "not set up", isReady: false)
        }
        // The installed version is observable, never remembered.
        let version = try? await installedVersion(on: sprite, platform: platform)
        let details = version.flatMap { $0 }.map { [IntegrationStatus.Detail("Version", $0)] } ?? []
        if recognized.contains(where: { $0.state?.status == .running }) {
            return IntegrationStatus(summary: "service running", isReady: true, details: details)
        }
        let status = recognized.first?.state?.status.display ?? "not running"
        return IntegrationStatus(summary: "service \(status)", isReady: false, details: details)
    }

    public func actions(services: [Service], metadata: SpriteMetadata?) -> [SpriteAction] {
        guard services.contains(where: recognizes) else { return [] }
        return [SpriteAction(id: "open-in-t3-code", title: "Open in T3 Code", kind: .openURL(Self.appURL))]
    }

    public func flows(status: IntegrationStatus, services: [Service], metadata: SpriteMetadata?) -> [Flow] {
        var flows: [Flow] = []
        // Pair again is offered whenever a recognized service exists
        // (e.g. after a restore), not only while it is running.
        if services.contains(where: recognizes) {
            flows.append(pairAgainFlow())
        }
        if !status.isReady {
            flows.append(setupFlow())
        }
        return flows
    }
}
