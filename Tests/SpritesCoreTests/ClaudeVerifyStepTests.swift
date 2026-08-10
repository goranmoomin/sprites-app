import Foundation
import Testing
import SpritesCore

/// The skippable verify (claude-setup-token ticket 04): an inference
/// probe offered at the end of both login branches, with dead-token
/// recovery in the plant branch.
@MainActor
struct ClaudeVerifyStepTests {
    static let sprite = "morning-cherry-1234"

    private func makeFake() async -> FakeSpritesPlatform {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        return fake
    }

    @Test func approvedVerifyRunsTheProbeAndShowsTheReply() async throws {
        let fake = await makeFake()
        await ClaudeCodeLoginFlowTests.scriptHappySetupToken(fake, sprite: Self.sprite)

        let run = FlowRun(
            flow: ClaudeCodeLoginFlowTests.loginFlow(),
            platform: fake, sprite: Self.sprite)
        let shownReply = SharedBox<String?>(nil)
        let responder = Task {
            while let prompt = await run.nextPrompt() {
                switch prompt {
                case .openURLAndEnterCode: run.respond(.text("auth-code-42"))
                case .claudeMintedToken: run.respond(.acknowledged)
                case .consent(let title, _, _) where title.contains("Verify"):
                    run.respond(.approved)
                case .consent(let title, let message, _):
                    #expect(title == "Login verified")
                    shownReply.value = message
                    run.respond(.approved)
                default:
                    Issue.record("unexpected prompt \(String(describing: prompt))")
                    run.respond(.declined)
                }
            }
        }
        await run.start()
        await responder.value

        #expect(run.phase == .succeeded)
        #expect(shownReply.value?.contains("ok") == true)
        #expect(await fake.execLog.contains { $0.command.argv.contains("-p") })
    }

    @Test func plantBranchDeadTokenIsForgottenAndFallsThroughToMint() async throws {
        let fake = await makeFake()
        // The probe fails like a revoked token; the mint dialogue and its
        // scripts stand ready for the fall-through.
        await ClaudeCodeLoginFlowTests.scriptInferenceProbe(fake, ok: false)
        await ClaudeCodeLoginFlowTests.scriptHappySetupToken(fake, sprite: Self.sprite)
        let store = InMemoryClaudeLoginStore(
            login: SavedClaudeLogin(token: "sk-ant-oat01-DEADDEAD", mintedAt: Date()))

        let run = FlowRun(
            flow: ClaudeCodeLoginFlowTests.loginFlow(store: store),
            platform: fake, sprite: Self.sprite)
        let sawMintDialogue = SharedBox(false)
        let verifyOffers = SharedBox(0)
        let responder = Task {
            while let prompt = await run.nextPrompt() {
                switch prompt {
                case .consent(let title, _, _) where title.contains("Verify"):
                    verifyOffers.value += 1
                    // Verify the plant; skip the re-verify after the mint.
                    run.respond(verifyOffers.value == 1 ? .approved : .declined)
                case .openURLAndEnterCode:
                    sawMintDialogue.value = true
                    run.respond(.text("auth-code-42"))
                case .claudeMintedToken:
                    run.respond(.acknowledged)
                default:
                    Issue.record("unexpected prompt \(String(describing: prompt))")
                    run.respond(.declined)
                }
            }
        }
        await run.start()
        await responder.value

        #expect(run.phase == .succeeded)
        #expect(sawMintDialogue.value, "expected the fall-through into the mint dialogue")
        // The dead login was forgotten, and the fresh mint was planted.
        #expect(store.load() == nil)
        let settings = try #require(await fake.fileContents(
            on: Self.sprite, path: "/home/sprite/.claude/settings.json"))
        #expect(settings.contains(ClaudeCodeLoginFlowTests.mintedToken))
        #expect(!settings.contains("DEADDEAD"))
    }

    @Test func mintBranchVerifyFailureReportsWithoutForgetting() async throws {
        let fake = await makeFake()
        await ClaudeCodeLoginFlowTests.scriptInferenceProbe(fake, ok: false)
        await ClaudeCodeLoginFlowTests.scriptHappySetupToken(fake, sprite: Self.sprite)
        let store = InMemoryClaudeLoginStore()

        let run = FlowRun(
            flow: ClaudeCodeLoginFlowTests.loginFlow(store: store),
            platform: fake, sprite: Self.sprite)
        let responder = Task {
            while let prompt = await run.nextPrompt() {
                switch prompt {
                case .openURLAndEnterCode: run.respond(.text("auth-code-42"))
                case .claudeMintedToken: run.respond(.approved)  // save it
                case .consent: run.respond(.approved)  // verify
                default:
                    Issue.record("unexpected prompt \(String(describing: prompt))")
                    run.respond(.declined)
                }
            }
        }
        await run.start()
        await responder.value

        #expect(run.phase == .failed)
        #expect(run.failureMessage?.contains("verification probe") == true)
        // Nothing forgotten: the save made at consent time stands.
        #expect(store.load()?.token == ClaudeCodeLoginFlowTests.mintedToken)
    }

    @Test func hungProbeFailsTheStepButLeavesThePlantInPlace() async throws {
        let fake = await makeFake()
        await ClaudeCodeLoginFlowTests.scriptAuthStatus(fake, sprite: Self.sprite)
        // A probe that never answers (EOF included: runCapturing sends one).
        await fake.scriptExec(where: { $0.argv.contains("-p") }) { _, io in
            try? await Task.sleep(for: .seconds(60))
            io.exit(0)
        }
        let store = InMemoryClaudeLoginStore(
            login: SavedClaudeLogin(token: ClaudeLoginReuseTests.savedToken, mintedAt: Date()))

        let run = FlowRun(
            flow: ClaudeCodeLoginFlowTests.loginFlow(
                store: store, verifyTimeout: .milliseconds(200)),
            platform: fake, sprite: Self.sprite)
        let responder = Task {
            while let prompt = await run.nextPrompt() {
                if case .consent = prompt {
                    run.respond(.approved)  // verify
                } else {
                    Issue.record("unexpected prompt \(String(describing: prompt))")
                    run.respond(.declined)
                }
            }
        }
        await run.start()
        await responder.value

        #expect(run.phase == .failed)
        #expect(run.failureMessage?.contains("timed out") == true)
        // A hung CLI is not a dead credential: nothing forgotten, the
        // planted token stays.
        #expect(store.load() != nil)
        let settings = try #require(await fake.fileContents(
            on: Self.sprite, path: "/home/sprite/.claude/settings.json"))
        #expect(settings.contains(ClaudeLoginReuseTests.savedToken))
    }
}

/// MainActor-confined mutable capture for responder tasks.
@MainActor
final class SharedBox<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}
