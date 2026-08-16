import Foundation
import Testing
import SpritesCore

/// Requirements name Integrations (ADR 0008): any ready member satisfies a
/// Requirement, a Flow needs all of them, and the blocked sentence names
/// the products.
@MainActor
struct RequirementTests {
    static let sprite = "req-sprite-1"

    private func run(_ flow: Flow, ready: Set<String>) async -> FlowRun {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        let integrations: [any Integration] = [
            StubIntegration(id: "alpha", displayName: "Alpha", ready: ready.contains("alpha")),
            StubIntegration(id: "beta", displayName: "Beta", ready: ready.contains("beta")),
            StubIntegration(id: "gamma", displayName: "Gamma", ready: ready.contains("gamma")),
        ]
        let run = FlowRun(flow: flow, platform: fake, sprite: Self.sprite, integrations: integrations)
        await run.start()
        return run
    }

    @Test func anyReadyMemberSatisfiesARequirement() async {
        let flow = Flow(id: "f", title: "F", requires: [Requirement(anyOf: ["alpha", "beta"])], steps: [])
        #expect(await run(flow, ready: ["beta"]).phase == .succeeded)
        #expect(await run(flow, ready: ["alpha"]).phase == .succeeded)
    }

    @Test func everyRequirementIsNeededAndTheFirstUnmetOneIsNamed() async {
        let flow = Flow(
            id: "f", title: "F",
            requires: [Requirement(anyOf: ["alpha", "beta"]), Requirement(anyOf: ["gamma"])],
            steps: [])
        let both = await run(flow, ready: ["alpha", "gamma"])
        #expect(both.phase == .succeeded)

        let missingGamma = await run(flow, ready: ["alpha"])
        #expect(missingGamma.phase == .blocked)
        #expect(missingGamma.blockedReason == "This needs Gamma ready on this sprite. Run its Flow first.")

        let missingBoth = await run(flow, ready: [])
        #expect(missingBoth.blockedReason == "This needs Alpha or Beta ready on this sprite. Run its Flow first.")
    }

    @Test func aFlowWithoutRequirementsNeverBlocks() async {
        let flow = Flow(id: "f", title: "F", steps: [])
        #expect(await run(flow, ready: []).phase == .succeeded)
    }
}

private struct StubIntegration: Integration {
    let id: String
    let displayName: String
    let ready: Bool
    let category = Category.other

    func recognizes(_ service: Service) -> Bool { false }

    func observeStatus(on sprite: String, services: [Service], platform: SpritesPlatform)
        async throws -> IntegrationStatus
    {
        IntegrationStatus(summary: ready ? "ready" : "not ready", isReady: ready)
    }

    func actions(services: [Service], metadata: SpriteMetadata?) -> [SpriteAction] { [] }
    func flows(status: IntegrationStatus, services: [Service], metadata: SpriteMetadata?) -> [Flow] { [] }
}
