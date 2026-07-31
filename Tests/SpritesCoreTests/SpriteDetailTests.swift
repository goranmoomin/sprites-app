import Foundation
import Testing
import SpritesCore

@MainActor
struct SpriteDetailTests {
    @Test func coldSpriteShowsShallowDataAndIsNeverWoken() async throws {
        // ADR 0001: deep calls never hit a cold sprite uninvited.
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "quiet-frog-5678", status: .cold)
        let model = SpriteDetailModel(platform: fake, spriteName: "quiet-frog-5678")

        await model.refresh()

        #expect(model.metadata?.status == .cold)
        #expect(model.metadata?.url != nil)
        #expect(model.metadata?.urlVisibility == .private)
        #expect(model.needsWakeToInspect)
        #expect(model.services == nil)
        #expect(model.tasks == nil)
        #expect(model.checkpoints == nil)
        #expect(await fake.deepTouches.isEmpty)
        #expect(await fake.status(of: "quiet-frog-5678") == .cold)
    }

    @Test func runningSpriteDeepObservesServicesTasksAndCheckpoints() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        await fake.setService(
            on: "morning-cherry-1234",
            Service(name: "t3", cmd: "/home/sprite/.local/bin/t3",
                    args: ["serve", "--host", "0.0.0.0"], state: ServiceState(status: "running", pid: 123))
        )
        await fake.setTask(
            on: "morning-cherry-1234",
            PlatformTask(name: "claude-heartbeat", expiresAt: Date(timeIntervalSince1970: 2000)))
        await fake.setCheckpoint(on: "morning-cherry-1234", Checkpoint(id: "v1", comment: "before risky work"))
        let model = SpriteDetailModel(platform: fake, spriteName: "morning-cherry-1234")

        await model.refresh()

        #expect(model.services?.map(\.name) == ["t3"])
        #expect(model.services?.first?.args.first == "serve")
        #expect(model.services?.first?.state?.pid == 123)
        #expect(model.tasks?.map(\.name) == ["claude-heartbeat"])
        #expect(model.checkpoints?.map(\.id) == ["v1"])
        #expect(!model.needsWakeToInspect)
    }

    @Test func wakeToInspectExplicitlyWakesThenDeepObserves() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "quiet-frog-5678", status: .cold)
        await fake.setService(on: "quiet-frog-5678", Service(name: "custom", cmd: "/usr/bin/thing", args: []))
        let model = SpriteDetailModel(platform: fake, spriteName: "quiet-frog-5678")
        await model.refresh()

        await model.wakeToInspect()

        #expect(model.metadata?.status == .running)
        #expect(model.services?.map(\.name) == ["custom"])
        #expect(!model.needsWakeToInspect)
    }

    @Test func wakeConsentOutlivesTheTransientRunningStatus() async throws {
        // Observed live: exec flips a sprite to running only briefly and it
        // settles back to warm. Once the user explicitly woke the sprite,
        // deep observation continues on refresh; no second wake is demanded.
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "quiet-frog-5678", status: .cold)
        await fake.setService(on: "quiet-frog-5678", Service(name: "custom", cmd: "/usr/bin/thing", args: []))
        let model = SpriteDetailModel(platform: fake, spriteName: "quiet-frog-5678")
        await model.refresh()
        await model.wakeToInspect()

        await fake.setStatus("quiet-frog-5678", .warm)
        await model.refresh()

        #expect(model.metadata?.status == .warm)
        #expect(!model.needsWakeToInspect)
        #expect(model.services?.map(\.name) == ["custom"])
    }

    @Test func wakeLatencySurfacesAsWakingStateNotAnError() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "quiet-frog-5678", status: .cold)
        await fake.holdWakes()
        let model = SpriteDetailModel(platform: fake, spriteName: "quiet-frog-5678")
        await model.refresh()

        let waking = Task { await model.wakeToInspect() }
        // Give the wake a moment to start and block on the fake.
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.isWaking)
        #expect(model.lastError == nil)

        await fake.releaseWakes()
        await waking.value
        #expect(!model.isWaking)
        #expect(model.metadata?.status == .running)
    }
}
