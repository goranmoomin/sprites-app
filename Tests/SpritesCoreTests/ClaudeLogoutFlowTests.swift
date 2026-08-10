import Foundation
import Testing
import SpritesCore

/// The logout Flow (claude-setup-token ticket 05): unplants the token
/// merge-preservingly, sweeps the legacy credential store, and flips the
/// observed status.
@MainActor
struct ClaudeLogoutFlowTests {
    static let sprite = "morning-cherry-1234"

    private func makeLoggedInFake() async -> FakeSpritesPlatform {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        // A sprite with a planted token, another env key, hooks, and a
        // legacy credential file from the old interactive login.
        await fake.setFile(
            on: Self.sprite, path: "/home/sprite/.claude/settings.json",
            content: """
                {"env": {"CLAUDE_CODE_OAUTH_TOKEN": "sk-ant-oat01-PLANTED", "FOO": "bar"},
                 "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "sprite-env curl"}]}]}}
                """)
        await fake.setFile(
            on: Self.sprite, path: "/home/sprite/.claude/.credentials.json", content: "{}")
        await ClaudeCodeLoginFlowTests.scriptAuthStatus(fake, sprite: Self.sprite)
        await ClaudeCodeLoginFlowTests.scriptFileRemoval(fake, sprite: Self.sprite)
        return fake
    }

    @Test func logoutUnplantsPreservinglyAndFlipsTheObservedStatus() async throws {
        let fake = await makeLoggedInFake()
        let detail = SpriteDetailModel(platform: fake, sprite: Self.sprite)
        await detail.refresh()
        #expect(detail.offeredFlows?.map(\.id).contains("claude-code-logout") == true)

        let run = FlowRun(
            flow: Integrations.claudeCode.logoutFlow(),
            platform: fake, sprite: Self.sprite)
        let responder = Task {
            let prompt = await run.nextPrompt()
            guard case .consent(let title, let message, _) = prompt else {
                Issue.record("expected the logout consent, got \(String(describing: prompt))")
                return
            }
            #expect(title.contains("Log out"))
            // The rider: logging out is not revocation.
            #expect(message.contains("revokes nothing"))
            run.respond(.approved)
        }
        await run.start()
        await responder.value

        #expect(run.phase == .succeeded)
        let settings = try #require(await fake.fileContents(
            on: Self.sprite, path: "/home/sprite/.claude/settings.json"))
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(settings.utf8)) as? [String: Any])
        let env = try #require(json["env"] as? [String: Any])
        #expect(env["CLAUDE_CODE_OAUTH_TOKEN"] == nil)
        // Everything else in the file survives: env keys and hooks.
        #expect(env["FOO"] as? String == "bar")
        #expect(settings.contains("sprite-env curl"))
        // The legacy credential store is swept too.
        #expect(await fake.fileContents(
            on: Self.sprite, path: "/home/sprite/.claude/.credentials.json") == nil)

        // The detail screen flips and offers login again.
        await detail.refresh()
        #expect(detail.integrationLines?.first { $0.title == "Claude Code" }?.summary
            == "not logged in")
        #expect(detail.offeredFlows?.map(\.id).contains("claude-code-login") == true)
    }

    @Test func decliningTheConsentChangesNothing() async throws {
        let fake = await makeLoggedInFake()

        let run = FlowRun(
            flow: Integrations.claudeCode.logoutFlow(),
            platform: fake, sprite: Self.sprite)
        let responder = Task {
            if await run.nextPrompt() != nil {
                run.respond(.declined)
            }
        }
        await run.start()
        await responder.value

        #expect(run.phase == .cancelled)
        let settings = try #require(await fake.fileContents(
            on: Self.sprite, path: "/home/sprite/.claude/settings.json"))
        #expect(settings.contains("sk-ant-oat01-PLANTED"))
        #expect(await fake.fileContents(
            on: Self.sprite, path: "/home/sprite/.claude/.credentials.json") != nil)
    }
}
