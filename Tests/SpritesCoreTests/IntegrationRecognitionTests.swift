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
                    state: ServiceState(status: "running", pid: 42)))
        let model = SpriteDetailModel(platform: fake, sprite: "morning-cherry-1234")

        await model.refresh()

        let t3Line = model.integrationLines?.first { $0.title == "T3 Code" }
        #expect(t3Line?.summary == "service running")
        #expect(model.actions?.contains { $0.id == "open-in-t3-code" } == true)
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
        #expect(model.actions?.contains { $0.id == "open-in-t3-code" } != true)
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

    @Test func claudeCodeStatusLineObservesCredentialPresence() async throws {
        let fake = await makeFake()
        let model = SpriteDetailModel(platform: fake, sprite: "morning-cherry-1234")

        await model.refresh()
        #expect(model.integrationLines?.first { $0.title == "Claude Code" }?.summary == "not logged in")

        await fake.setFile(on: "morning-cherry-1234", path: "/home/sprite/.claude/.credentials.json",
                           content: "{\"claudeAiOauth\":{}}")
        await model.refresh()
        #expect(model.integrationLines?.first { $0.title == "Claude Code" }?.summary == "logged in")
    }

    @Test func t3DeclaresItsCodingAgentDependency() {
        let t3 = Integrations.t3Code
        #expect(t3.role == .controlPlane)
        #expect(t3.requirements.contains(.loggedInCodingAgent))
        #expect(Integrations.claudeCode.role == .codingAgent)
    }
}
