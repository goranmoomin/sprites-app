import Foundation
import Testing
import SpritesCore

@MainActor
struct ServiceManagementTests {
    private func makeFake() async -> FakeSpritesPlatform {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        return fake
    }

    @Test func createServiceFormMapsOneToOneToThePlatformDefinition() async throws {
        let fake = await makeFake()
        let model = CreateServiceModel(platform: fake, spriteName: "morning-cherry-1234")
        model.name = "my-service"
        model.executable = "/usr/local/bin/thing"
        model.arguments = ["--port", "8080"]
        model.workingDirectory = "/home/sprite/app"
        model.environment = ["MODE": "prod"]
        model.httpPort = 8080
        model.needs = ["other-service"]

        let succeeded = await model.create()

        #expect(succeeded)
        let services = try await fake.services(on: "morning-cherry-1234")
        let service = try #require(services.first { $0.name == "my-service" })
        #expect(service.cmd == "/usr/local/bin/thing")
        #expect(service.args == ["--port", "8080"])
        #expect(service.dir == "/home/sprite/app")
        #expect(service.env == ["MODE": "prod"])
        #expect(service.httpPort == 8080)
        #expect(service.needs == ["other-service"])
    }

    @Test func upsertProgressEventsAreShownLive() async throws {
        let fake = await makeFake()
        let model = CreateServiceModel(platform: fake, spriteName: "morning-cherry-1234")
        model.name = "my-service"
        model.executable = "/bin/thing"

        _ = await model.create()

        #expect(model.progress.map(\.type).first == "started")
        #expect(model.progress.map(\.type).last == "complete")
    }

    @Test func startStopRestartReObserveServiceState() async throws {
        let fake = await makeFake()
        await fake.setService(
            on: "morning-cherry-1234",
            Service(name: "svc", cmd: "/bin/thing", args: [], state: ServiceState(status: "stopped")))
        let model = SpriteDetailModel(platform: fake, spriteName: "morning-cherry-1234")
        await model.refresh()

        await model.startService("svc")
        #expect(model.services?.first?.state?.status == "running")

        await model.stopService("svc")
        #expect(model.services?.first?.state?.status == "stopped")

        // The documented restart endpoint 404s; restart is stop+start.
        await model.startService("svc")
        await model.restartService("svc")
        #expect(model.services?.first?.state?.status == "running")
    }

    @Test func crashLoopingServiceSurfacesObservedFailureState() async throws {
        let fake = await makeFake()
        let nextRestart = Date(timeIntervalSince1970: 1_800_000_000)
        await fake.setService(
            on: "morning-cherry-1234",
            Service(name: "t3", cmd: "/bin/t3", args: ["serve"],
                    state: ServiceState(status: "failed", error: "exited with code 1",
                                        restartCount: 4, nextRestartAt: nextRestart)))
        let model = SpriteDetailModel(platform: fake, spriteName: "morning-cherry-1234")

        await model.refresh()

        let state = try #require(model.services?.first?.state)
        #expect(state.status == "failed")
        #expect(state.error == "exited with code 1")
        #expect(state.restartCount == 4)
        #expect(state.nextRestartAt == nextRestart)
    }

    @Test func recentServiceLogsAreViewableAsText() async throws {
        let fake = await makeFake()
        await fake.setService(on: "morning-cherry-1234", Service(name: "svc", cmd: "/bin/thing", args: []))
        await fake.setServiceLogs(on: "morning-cherry-1234", service: "svc", "line one\nline two\n")
        let model = ServiceLogsModel(platform: fake, spriteName: "morning-cherry-1234", serviceName: "svc")

        await model.load()

        #expect(model.logs == "line one\nline two\n")
    }

    @Test func deletingAServiceRemovesItFromObservation() async throws {
        let fake = await makeFake()
        await fake.setService(on: "morning-cherry-1234", Service(name: "svc", cmd: "/bin/thing", args: []))
        let model = SpriteDetailModel(platform: fake, spriteName: "morning-cherry-1234")
        await model.refresh()

        await model.deleteService("svc")

        #expect(model.services?.isEmpty == true)
    }
}
