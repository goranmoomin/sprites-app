import Foundation
import Testing
import SpritesCore

@MainActor
struct IntegrationRecognitionTests {
    private func makeFake() async -> FakeSpritesPlatform {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        return fake
    }

    @Test func t3ServeServiceShowsStatusLineAndOpenAction() async throws {
        // Given a running sprite with a service whose command is `t3 serve ...`,
        // the detail model exposes an Open in T3 Code action.
        let fake = await makeFake()
        await fake.setService(
            on: "morning-cherry-1234",
            Service(name: "anything-at-all", cmd: "/home/sprite/.local/bin/t3",
                    args: ["serve", "--host", "0.0.0.0", "--port", "3773"],
                    state: ServiceState(status: .running, pid: 42)))
        let model = SpriteDetailModel(platform: fake, sprite: "morning-cherry-1234")

        await model.refresh()

        let t3Line = model.integrationLines?.first { $0.title == "T3 Code" }
        #expect(t3Line?.summary == "service running")
        // No package.json on this sprite: nothing to show, nothing invented.
        #expect(t3Line?.details == [])
        // One uniform list: the integration's handoff plus the app's own
        // Run command contribution.
        #expect(model.actions == [
            SpriteAction(
                id: "open-in-t3-code", title: "Open in T3 Code",
                kind: .openURL(T3CodeIntegration.appURL)),
            SpriteAction(id: "run-command", title: "Run command", kind: .runCommand),
        ])
    }

    @Test func recognitionIsByCommandMatchNotServiceName() async throws {
        let fake = await makeFake()
        // A service *named* t3 whose command is something else stays Custom.
        await fake.setService(
            on: "morning-cherry-1234",
            Service(name: "t3", cmd: "/usr/bin/python3", args: ["-m", "http.server"]))
        let model = SpriteDetailModel(platform: fake, sprite: "morning-cherry-1234")

        await model.refresh()

        let service = try #require(model.services?.first)
        #expect(model.isCustom(service))
        #expect(model.actions == [
            SpriteAction(id: "run-command", title: "Run command", kind: .runCommand)
        ])
    }

    @Test func nearMissCommandsStayCustom() async throws {
        let fake = await makeFake()
        await fake.setService(
            on: "morning-cherry-1234",
            Service(name: "a", cmd: "/usr/local/bin/t33", args: ["serve"]))
        await fake.setService(
            on: "morning-cherry-1234",
            Service(name: "b", cmd: "/home/sprite/.local/bin/t3", args: ["auth", "whoami"]))
        let model = SpriteDetailModel(platform: fake, sprite: "morning-cherry-1234")

        await model.refresh()

        #expect(model.services?.allSatisfy { model.isCustom($0) } == true)
    }

    @Test func multipleInstancesOfOneIntegrationAreAllRecognized() async throws {
        let fake = await makeFake()
        await fake.setService(
            on: "morning-cherry-1234",
            Service(name: "t3-main", cmd: "/home/sprite/.local/bin/t3",
                    args: ["serve", "--base-dir", "/home/sprite/a"]))
        await fake.setService(
            on: "morning-cherry-1234",
            Service(name: "second", cmd: "/home/sprite/.local/bin/t3",
                    args: ["serve", "--base-dir", "/home/sprite/b"]))
        let model = SpriteDetailModel(platform: fake, sprite: "morning-cherry-1234")

        await model.refresh()

        #expect(model.services?.allSatisfy { !model.isCustom($0) } == true)
    }

    @Test func claudeCodeStatusLineFollowsTheCLIsAuthProbe() async throws {
        let fake = await makeFake()
        await ClaudeCodeLoginFlowTests.scriptAuthStatus(fake, sprite: "morning-cherry-1234")
        let model = SpriteDetailModel(platform: fake, sprite: "morning-cherry-1234")

        await model.refresh()
        #expect(model.integrationLines?.first { $0.title == "Claude Code" }?.summary == "not logged in")

        await fake.setFile(on: "morning-cherry-1234", path: "/home/sprite/.claude/settings.json",
                           content: #"{"env": {"CLAUDE_CODE_OAUTH_TOKEN": "sk-ant-oat01-PLANTED"}}"#)
        await model.refresh()
        #expect(model.integrationLines?.first { $0.title == "Claude Code" }?.summary == "logged in")
    }

    @Test func t3InstalledVersionIsADetailNotPartOfTheSummary() async throws {
        let fake = await makeFake()
        await fake.setService(
            on: "morning-cherry-1234",
            Service(name: "t3", cmd: "/home/sprite/.local/bin/t3", args: ["serve"],
                    state: ServiceState(status: .stopped, pid: nil)))
        await fake.setFile(
            on: "morning-cherry-1234", path: T3CodeIntegration.packageJSONPath,
            content: #"{"name":"t3","version":"0.0.31"}"#)
        let model = SpriteDetailModel(platform: fake, sprite: "morning-cherry-1234")

        await model.refresh()

        let t3Line = model.integrationLines?.first { $0.title == "T3 Code" }
        #expect(t3Line?.summary == "service stopped")
        #expect(t3Line?.details == [IntegrationStatus.Detail("Version", "0.0.31")])
    }

    @Test func t3SetupRequiresASupportedCodingAgentByName() {
        let t3 = Integrations.t3Code
        #expect(t3.category == .controlPlane)
        #expect(Integrations.claudeCode.category == .codingAgent)
        #expect(t3.setupFlow().requires == [T3CodeIntegration.supportedCodingAgents])
        #expect(T3CodeIntegration.supportedCodingAgents.anyOf == [Integrations.claudeCode.id])
        #expect(t3.pairAgainFlow().requires.isEmpty)
    }
}
