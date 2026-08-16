import Foundation
import Testing
import SpritesCore

/// The Board: every integration as one tile in Category rows, state
/// observed rather than remembered, the same model on the create path and
/// the detail screen.
@MainActor
struct BoardTests {
    static let sprite = "brand-new-sprite-1"

    private func makeCreatedSprite() async -> FakeSpritesPlatform {
        let fake = FakeSpritesPlatform()
        let create = CreateSpriteModel(platform: fake)
        create.name = Self.sprite
        _ = await create.create()
        return fake
    }

    private func scriptHappyDialogues(_ fake: FakeSpritesPlatform) async {
        await ClaudeCodeLoginFlowTests.scriptHappySetupToken(fake, sprite: Self.sprite)
        await fake.scriptExec(where: { $0.argv.first == "npm" && $0.argv.last == "t3" }) { _, io in
            await fake.setFile(
                on: Self.sprite, path: "/home/sprite/.local/bin/t3", content: "#!bin")
            io.exit(0)
        }
        await fake.scriptExec(where: { $0.argv.contains("pairing") }) { _, io in
            io.stdout(#"{"pairUrl":"https://x.sprites.app/pair#token=otp-9"}"# + "\n")
            io.exit(0)
        }
    }

    /// Drives a flow run to completion, answering prompts like a user.
    private func autoRespond(_ run: FlowRun) -> Task<Void, Never> {
        Task {
            while let prompt = await run.nextPrompt() {
                switch prompt {
                case .openURLAndEnterCode: run.respond(.text("auth-code-42"))
                case .consent: run.respond(.approved)
                case .t3Pairing: run.respond(.acknowledged)
                case .claudeMintedToken: run.respond(.acknowledged)
                }
            }
        }
    }

    private func board(_ fake: FakeSpritesPlatform, integrations: [any Integration] = Integrations.all)
        async -> SpriteDetailModel
    {
        let model = SpriteDetailModel(platform: fake, sprite: Self.sprite, integrations: integrations)
        await model.refresh()
        // Freshly created sprites are warm: the create page takes the wake.
        if model.needsWakeToInspect { await model.wakeToInspect() }
        return model
    }

    @Test func rowsAreCategoriesWithOneTilePerIntegrationInRegistryOrder() async throws {
        let fake = await makeCreatedSprite()
        let model = await board(fake)

        let rows = try #require(model.board)
        #expect(rows.map(\.category) == [.codingAgent, .controlPlane])
        #expect(rows.map { $0.tiles.map(\.id) } == [["claude-code"], ["t3-code"]])
        #expect(rows.flatMap(\.tiles).allSatisfy { !$0.status.isReady })
        // The tile carries what the integration offers, so a tap needs no
        // further observation.
        #expect(rows[0].tiles[0].flows.map(\.id) == ["claude-code-login"])
        #expect(rows[1].tiles[0].flows.map(\.id) == ["t3-setup"])
        // Empty categories have no row.
        #expect(!rows.contains { $0.category == .other })
    }

    @Test func aTileIsReobservedAfterItsFlowRuns() async throws {
        let fake = await makeCreatedSprite()
        await scriptHappyDialogues(fake)
        let model = await board(fake)
        let claude = try #require(model.board?.first?.tiles.first)
        #expect(claude.status.isReady == false)

        // The T3 setup reads as blocked from the Board alone (no probe).
        let t3Setup = try #require(model.board?.last?.tiles.first?.flows.first)
        #expect(model.blockedReason(for: t3Setup) == "This needs Claude Code ready on this sprite. Run its Flow first.")

        let run = FlowRun(flow: claude.flows[0], platform: fake, sprite: Self.sprite)
        let responder = autoRespond(run)
        await run.start()
        await responder.value
        #expect(run.phase == .succeeded)

        // Nothing is marked done: the next observation says so itself.
        await model.refresh()
        #expect(model.board?.first?.tiles.first?.status.summary == "logged in")
        #expect(model.board?.first?.tiles.first?.flows.isEmpty == true)
        #expect(model.blockedReason(for: t3Setup) == nil)
    }

    @Test func runningEveryOfferedFlowEndsOnAFullySetUpSprite() async throws {
        let fake = await makeCreatedSprite()
        await scriptHappyDialogues(fake)
        let model = await board(fake)

        // Tap through the tiles in Board order.
        for row in model.board ?? [] {
            for tile in row.tiles {
                for flow in tile.flows {
                    let run = FlowRun(flow: flow, platform: fake, sprite: Self.sprite)
                    let responder = autoRespond(run)
                    await run.start()
                    await responder.value
                    #expect(run.phase == .succeeded, "\(flow.id)")
                }
            }
        }

        let detail = SpriteDetailModel(platform: fake, sprite: Self.sprite)
        await detail.refresh()
        #expect(detail.integrationLines?.allSatisfy(\.isReady) == true)
        #expect(detail.actions?.contains { $0.id == "open-in-t3-code" } == true)
    }

    @Test func leavingWithNothingRunLeavesAnOrdinarySprite() async throws {
        let fake = await makeCreatedSprite()
        _ = await board(fake)

        // The sprite is a perfectly ordinary sprite with everything left to
        // do, and the detail screen offers the same Flows.
        let detail = SpriteDetailModel(platform: fake, sprite: Self.sprite)
        await detail.refresh()
        #expect(detail.integrationLines?.isEmpty == false)
        #expect(detail.integrationLines?.allSatisfy { !$0.isReady } == true)
        #expect(detail.offeredFlows?.map(\.id) == ["claude-code-login", "t3-setup"])
    }

    @Test func interruptionAfterOneFlowLeavesAConsistentObservableSprite() async throws {
        let fake = await makeCreatedSprite()
        await scriptHappyDialogues(fake)
        let model = await board(fake)

        // Run only the Claude login, then the app dies. No cleanup runs.
        let login = try #require(model.board?.first?.tiles.first?.flows.first)
        let run = FlowRun(flow: login, platform: fake, sprite: Self.sprite)
        let responder = autoRespond(run)
        await run.start()
        await responder.value
        // (board model abandoned here)

        let detail = SpriteDetailModel(platform: fake, sprite: Self.sprite)
        await detail.refresh()
        let lines = try #require(detail.integrationLines)
        #expect(lines.first { $0.title == "Claude Code" }?.isReady == true)
        #expect(lines.first { $0.title == "T3 Code" }?.isReady == false)
        #expect(detail.services?.isEmpty == true)
    }

    @Test func statusesAreObservedConcurrentlyAndOneFailureLeavesTheOthers() async throws {
        let fake = await makeCreatedSprite()
        let slow = SlowIntegration(id: "slow-a", delay: .milliseconds(200))
        let slower = SlowIntegration(id: "slow-b", delay: .milliseconds(200))
        let broken = BrokenIntegration()
        let started = ContinuousClock.now
        let model = await board(fake, integrations: [slow, broken, slower])
        let elapsed = ContinuousClock.now - started

        // Serial would be at least 400ms.
        #expect(elapsed < .milliseconds(350))
        let tiles = model.board?.flatMap(\.tiles) ?? []
        #expect(tiles.map(\.id) == ["slow-a", "broken", "slow-b"])
        #expect(tiles.map(\.status.summary) == ["slow ok", "observation failed", "slow ok"])
        #expect(model.lastError == nil)
    }
}

private struct SlowIntegration: Integration {
    let id: String
    let delay: Duration
    var displayName: String { id }
    let category = Category.other

    func recognizes(_ service: Service) -> Bool { false }

    func observeStatus(on sprite: String, services: [Service], platform: SpritesPlatform)
        async throws -> IntegrationStatus
    {
        try await Task.sleep(for: delay)
        return IntegrationStatus(summary: "slow ok", isReady: true)
    }

    func actions(services: [Service], metadata: SpriteMetadata?) -> [SpriteAction] { [] }
    func flows(status: IntegrationStatus, services: [Service], metadata: SpriteMetadata?) -> [Flow] { [] }
}

private struct BrokenIntegration: Integration {
    let id = "broken"
    let displayName = "Broken"
    let category = Category.other
    struct Failure: Error {}

    func recognizes(_ service: Service) -> Bool { false }

    func observeStatus(on sprite: String, services: [Service], platform: SpritesPlatform)
        async throws -> IntegrationStatus
    {
        throw Failure()
    }

    func actions(services: [Service], metadata: SpriteMetadata?) -> [SpriteAction] { [] }
    func flows(status: IntegrationStatus, services: [Service], metadata: SpriteMetadata?) -> [Flow] { [] }
}
