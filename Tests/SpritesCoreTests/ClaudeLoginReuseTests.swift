import Foundation
import Testing
import SpritesCore

/// The branching login (claude-setup-token ticket 03): a saved login
/// plants silently, minting offers to save, and "use here only" leaves
/// the next sprite minting again.
@MainActor
struct ClaudeLoginReuseTests {
    nonisolated static let savedToken =
        "sk-ant-oat01-SAVEDSAVED-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

    @Test func savedLoginPlantsWithoutAnyBrowserDialogue() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "second-sprite-5678", status: .running)
        await ClaudeCodeLoginFlowTests.scriptAuthStatus(fake, sprite: "second-sprite-5678")
        let store = InMemoryClaudeLoginStore(
            login: SavedClaudeLogin(token: Self.savedToken, mintedAt: Date()))

        let run = FlowRun(
            flow: ClaudeCodeLoginFlowTests.loginFlow(store: store),
            platform: fake, sprite: "second-sprite-5678")
        // The only prompt the plant branch may show is the verify offer.
        let watcher = Task {
            while let prompt = await run.nextPrompt() {
                guard case .consent(let title, _, _) = prompt, title.contains("Verify") else {
                    Issue.record("the plant branch prompted: \(String(describing: prompt))")
                    run.respond(.declined)
                    continue
                }
                run.respond(.declined)  // skip the verify offer
            }
        }
        await run.start()
        await watcher.value

        #expect(run.phase == .succeeded)
        // No PTY dialogue ran: nothing minted, nothing to keep alive.
        #expect(await fake.execLog.allSatisfy { $0.command.argv != ["claude", "setup-token"] })
        let settings = try #require(await fake.fileContents(
            on: "second-sprite-5678", path: "/home/sprite/.claude/settings.json"))
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(settings.utf8)) as? [String: Any])
        #expect((json["env"] as? [String: Any])?["CLAUDE_CODE_OAUTH_TOKEN"] as? String
            == Self.savedToken)
        // The heartbeat hooks still land: the flow's second step ran.
        #expect(settings.contains("claude-heartbeat"))

        let detail = SpriteDetailModel(platform: fake, sprite: "second-sprite-5678")
        await detail.refresh()
        #expect(detail.integrationLines?.first { $0.title == "Claude Code" }?.summary == "logged in")
    }

    @Test func mintSavesWhenApprovedAndTheNextSpriteReuses() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "first-sprite-1234", status: .running)
        await fake.addSprite(name: "second-sprite-5678", status: .running)
        await ClaudeCodeLoginFlowTests.scriptHappySetupToken(fake, sprite: "first-sprite-1234")
        let store = InMemoryClaudeLoginStore()

        let mint = FlowRun(
            flow: ClaudeCodeLoginFlowTests.loginFlow(store: store),
            platform: fake, sprite: "first-sprite-1234")
        let responder = Task {
            while let prompt = await mint.nextPrompt() {
                switch prompt {
                case .openURLAndEnterCode: mint.respond(.text("auth-code-42"))
                case .claudeMintedToken: mint.respond(.approved)  // save for other Sprites
                case .consent: mint.respond(.declined)  // skip the verify offer
                default:
                    Issue.record("unexpected prompt \(String(describing: prompt))")
                    mint.respond(.declined)
                }
            }
        }
        await mint.start()
        await responder.value

        #expect(mint.phase == .succeeded)
        let saved = try #require(store.load())
        #expect(saved.token == ClaudeCodeLoginFlowTests.mintedToken)

        // The next sprite reuses it with no browser and no paste.
        let reuse = FlowRun(
            flow: ClaudeCodeLoginFlowTests.loginFlow(store: store),
            platform: fake, sprite: "second-sprite-5678")
        let watcher = Task {
            while let prompt = await reuse.nextPrompt() {
                guard case .consent = prompt else {
                    Issue.record("reuse prompted: \(String(describing: prompt))")
                    reuse.respond(.declined)
                    continue
                }
                reuse.respond(.declined)  // skip the verify offer
            }
        }
        await reuse.start()
        await watcher.value

        #expect(reuse.phase == .succeeded)
        let settings = try #require(await fake.fileContents(
            on: "second-sprite-5678", path: "/home/sprite/.claude/settings.json"))
        #expect(settings.contains(ClaudeCodeLoginFlowTests.mintedToken))
    }

    @Test func useHereOnlySavesNothingAndTheNextRunMintsAgain() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "first-sprite-1234", status: .running)
        await fake.addSprite(name: "second-sprite-5678", status: .running)
        await ClaudeCodeLoginFlowTests.scriptHappySetupToken(fake, sprite: "first-sprite-1234")
        let store = InMemoryClaudeLoginStore()

        let mint = FlowRun(
            flow: ClaudeCodeLoginFlowTests.loginFlow(store: store),
            platform: fake, sprite: "first-sprite-1234")
        let responder = Task {
            while let prompt = await mint.nextPrompt() {
                switch prompt {
                case .openURLAndEnterCode: mint.respond(.text("auth-code-42"))
                case .claudeMintedToken: mint.respond(.acknowledged)  // this Sprite only
                case .consent: mint.respond(.declined)  // skip the verify offer
                default:
                    Issue.record("unexpected prompt \(String(describing: prompt))")
                    mint.respond(.declined)
                }
            }
        }
        await mint.start()
        await responder.value

        #expect(mint.phase == .succeeded)
        #expect(store.load() == nil)

        // With nothing saved, the next sprite walks the dialogue again.
        let again = FlowRun(
            flow: ClaudeCodeLoginFlowTests.loginFlow(store: store),
            platform: fake, sprite: "second-sprite-5678")
        let secondPrompt = Task { () -> Bool in
            guard case .openURLAndEnterCode = await again.nextPrompt() else { return false }
            again.respond(.declined)
            return true
        }
        await again.start()
        #expect(await secondPrompt.value, "expected the mint dialogue on the second sprite")
    }

    @Test func savedLoginRoundTripsThroughTheKeychainEncoding() throws {
        let login = SavedClaudeLogin(
            token: Self.savedToken, mintedAt: Date(timeIntervalSince1970: 1_786_000_000))
        let data = try #require(SavedClaudeLogin.encode(login))
        let decoded = try #require(SavedClaudeLogin.decode(data))
        #expect(decoded.token == login.token)
        // ISO8601 keeps second precision; that is all the display needs.
        #expect(abs(decoded.mintedAt.timeIntervalSince(login.mintedAt)) < 1)
    }
}
