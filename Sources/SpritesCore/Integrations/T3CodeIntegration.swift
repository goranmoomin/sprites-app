import Foundation

/// Control-plane integration for T3 Code: recognizes `t3 serve` services by
/// command shape and contributes the Open in T3 Code handoff.
public struct T3CodeIntegration: Integration {
    public let id = "t3-code"
    public let displayName = "T3 Code"
    public let role = IntegrationRole.controlPlane
    public let requirements: [IntegrationRequirement] = [.loggedInCodingAgent]

    /// The official T3 Code app's URL scheme for the handoff.
    /// TODO: verify against the shipping T3 Code app (ticket 10 empirical check).
    public static let appURL = URL(string: "t3code://")!

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
        let suffix = version.flatMap { $0 }.map { " (v\($0))" } ?? ""
        if recognized.contains(where: { $0.state?.status == "running" }) {
            return IntegrationStatus(summary: "service running" + suffix, isReady: true)
        }
        let status = recognized.first?.state?.status ?? "not running"
        return IntegrationStatus(summary: "service \(status)" + suffix, isReady: false)
    }

    public func actions(services: [Service], metadata: SpriteMetadata?) -> [SpriteAction] {
        guard services.contains(where: recognizes) else { return [] }
        return [SpriteAction(id: "open-in-t3-code", title: "Open in T3 Code", url: Self.appURL)]
    }
}
