import Foundation
import Testing
import SpritesCore

/// Flow offering comes from the integrations themselves: the detail model
/// asks its injected integrations, never the global registry.
@MainActor
struct FlowOfferingTests {
    static let sprite = "morning-cherry-1234"

    private func makeFake() async -> FakeSpritesPlatform {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        return fake
    }

    private func t3Service(status: ServiceStatus) -> Service {
        Service(
            name: "t3", cmd: "/home/sprite/.local/bin/t3",
            args: ["serve", "--host", "0.0.0.0"], state: ServiceState(status: status))
    }

    @Test func freshSpriteOffersLoginAndSetup() async throws {
        let fake = await makeFake()
        let model = SpriteDetailModel(platform: fake, sprite: Self.sprite)

        await model.refresh()

        #expect(model.offeredFlows?.map(\.id) == ["claude-code-login", "t3-setup"])
    }

    @Test func fullySetUpSpriteOffersOnlyPairAgain() async throws {
        let fake = await makeFake()
        await ClaudeCodeLoginFlowTests.plantLoggedIn(fake, sprite: Self.sprite)
        await fake.setService(on: Self.sprite, t3Service(status: .running))
        let model = SpriteDetailModel(platform: fake, sprite: Self.sprite)

        await model.refresh()

        #expect(model.offeredFlows?.map(\.id) == ["t3-pair-again"])
    }

    @Test func stoppedT3ServiceOffersPairAgainAndSetup() async throws {
        let fake = await makeFake()
        await ClaudeCodeLoginFlowTests.plantLoggedIn(fake, sprite: Self.sprite)
        await fake.setService(on: Self.sprite, t3Service(status: .stopped))
        let model = SpriteDetailModel(platform: fake, sprite: Self.sprite)

        await model.refresh()

        #expect(model.offeredFlows?.map(\.id) == ["t3-pair-again", "t3-setup"])
    }

    @Test func injectedFakeIntegrationsFlowsAppear() async throws {
        let fake = await makeFake()
        let model = SpriteDetailModel(
            platform: fake, sprite: Self.sprite, integrations: [FakeIntegration()])

        await model.refresh()

        #expect(model.offeredFlows?.map(\.id) == ["fake-flow"])
    }
}

private struct FakeIntegration: Integration {
    let id = "fake"
    let displayName = "Fake"
    let category = Category.other

    func recognizes(_ service: Service) -> Bool { false }

    func observeStatus(on sprite: String, services: [Service], platform: SpritesPlatform)
        async throws -> IntegrationStatus
    {
        IntegrationStatus(summary: "observed", isReady: false)
    }

    func actions(services: [Service], metadata: SpriteMetadata?) -> [SpriteAction] { [] }

    func flows(status: IntegrationStatus, services: [Service], metadata: SpriteMetadata?) -> [Flow] {
        [Flow(id: "fake-flow", title: "Fake Flow", steps: [])]
    }
}
