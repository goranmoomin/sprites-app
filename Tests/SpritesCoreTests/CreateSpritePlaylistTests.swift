import Foundation
import Testing
import SpritesCore

@MainActor
struct CreateSpritePlaylistTests {
    static let sprite = "brand-new-sprite-1"

    private func makeCreatedSprite() async -> FakeSpritesPlatform {
        let fake = FakeSpritesPlatform()
        let create = CreateSpriteModel(platform: fake)
        create.name = Self.sprite
        _ = await create.create()
        return fake
    }

    private func scriptHappyDialogues(_ fake: FakeSpritesPlatform) async {
        await ClaudeCodeLoginFlowTests.scriptHappyClaudeLogin(fake, sprite: Self.sprite)
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
                case .pairing: run.respond(.acknowledged)
                }
            }
        }
    }

    @Test func fullHappyPathEndsOnAFullySetUpSprite() async throws {
        let fake = await makeCreatedSprite()
        await scriptHappyDialogues(fake)
        let playlist = CreateSpritePlaylist(platform: fake, sprite: Self.sprite)

        while let entryID = playlist.nextPendingID {
            let run = try #require(await playlist.startEntry(entryID))
            let responder = autoRespond(run)
            await run.start()
            await responder.value
            playlist.noteCurrentFinished()
        }

        #expect(playlist.isFinished)
        #expect(playlist.entries.allSatisfy { $0.status == .succeeded })

        let detail = SpriteDetailModel(platform: fake, spriteName: Self.sprite)
        await detail.refresh()
        #expect(detail.integrationLines?.allSatisfy(\.isReady) == true)
        #expect(detail.actions?.contains { $0.id == "open-in-t3-code" } == true)
    }

    @Test func everyStepIsSkippableAndTheDetailScreenOffersWhatRemains() async throws {
        let fake = await makeCreatedSprite()
        let playlist = CreateSpritePlaylist(platform: fake, sprite: Self.sprite)

        while let entryID = playlist.nextPendingID {
            playlist.skip(entryID)
        }

        #expect(playlist.isFinished)
        #expect(playlist.entries.allSatisfy { $0.status == .skipped })

        // The sprite is a perfectly ordinary sprite with everything left to
        // do (freshly created it is warm, so inspecting is an explicit wake).
        let detail = SpriteDetailModel(platform: fake, spriteName: Self.sprite)
        await detail.refresh()
        await detail.wakeToInspect()
        #expect(detail.integrationLines?.isEmpty == false)
        #expect(detail.integrationLines?.allSatisfy { !$0.isReady } == true)
    }

    @Test func interruptionMidPlaylistLeavesAConsistentObservableSprite() async throws {
        let fake = await makeCreatedSprite()
        await scriptHappyDialogues(fake)
        let playlist = CreateSpritePlaylist(platform: fake, sprite: Self.sprite)

        // Run only the Claude login, then the app dies. No cleanup runs.
        let entryID = try #require(playlist.nextPendingID)
        let run = try #require(await playlist.startEntry(entryID))
        let responder = autoRespond(run)
        await run.start()
        await responder.value
        // (playlist object abandoned here)

        let detail = SpriteDetailModel(platform: fake, spriteName: Self.sprite)
        await detail.refresh()
        let lines = try #require(detail.integrationLines)
        #expect(lines.first { $0.title == "Claude Code" }?.isReady == true)
        #expect(lines.first { $0.title == "T3 Code" }?.isReady == false)
        #expect(detail.services?.isEmpty == true)
    }

    @Test func controlPlaneStepWithUnmetDependencyExplainsAndOffersPrerequisite() async throws {
        let fake = await makeCreatedSprite()
        let playlist = CreateSpritePlaylist(platform: fake, sprite: Self.sprite)

        // Skip the Claude login, then try the T3 setup.
        playlist.skip(playlist.entries[0].id)
        let t3ID = playlist.entries[1].id
        let run = await playlist.startEntry(t3ID)

        #expect(run == nil)
        guard case .blocked(let reason) = playlist.entries[1].status else {
            Issue.record("expected blocked, got \(playlist.entries[1].status)")
            return
        }
        #expect(reason.contains("coding agent"))
        #expect(playlist.prerequisiteEntryID(for: t3ID) == playlist.entries[0].id)
    }

    @Test func playlistReusesTheSameFlowsTheDetailScreenLaunches() async throws {
        let fake = await makeCreatedSprite()
        let playlist = CreateSpritePlaylist(platform: fake, sprite: Self.sprite)

        #expect(playlist.entries.map(\.flow.id) == [
            Integrations.claudeCode.loginFlow().id,
            Integrations.t3Code.setupFlow().id,
        ])
    }
}
