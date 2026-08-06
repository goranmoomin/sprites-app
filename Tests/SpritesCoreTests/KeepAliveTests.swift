import Foundation
import Testing
import SpritesCore

@MainActor
struct KeepAliveTests {
    @Test func keepActiveCreatesTheNamedTaskWithVisibleExpiry() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        let model = SpriteDetailModel(platform: fake, sprite: "morning-cherry-1234")
        await model.refresh()

        await model.keepActive()

        let task = try #require(model.keepAliveTask)
        #expect(task.name == SpriteDetailModel.keepAliveTaskName)
        let now = await fake.now
        #expect(task.expiresAt == now.addingTimeInterval(3600))
        // Shown alongside any other live tasks, platform naming intact.
        #expect(model.tasks?.contains(task) == true)
    }

    @Test func extendRefreshesTheExpiry() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        let model = SpriteDetailModel(platform: fake, sprite: "morning-cherry-1234")
        await model.refresh()
        await model.keepActive()

        await fake.advanceClock(by: 1800)
        await model.keepActive()  // extend

        let now = await fake.now
        #expect(model.keepAliveTask?.expiresAt == now.addingTimeInterval(3600))
    }

    @Test func releaseDeletesTheTask() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        let model = SpriteDetailModel(platform: fake, sprite: "morning-cherry-1234")
        await model.refresh()
        await model.keepActive()

        await model.releaseKeepAlive()

        #expect(model.keepAliveTask == nil)
        #expect(try await fake.listTasks(on: "morning-cherry-1234").isEmpty)
    }

    @Test func anExpiredKeepAliveDisappearsFromObservation() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        let model = SpriteDetailModel(platform: fake, sprite: "morning-cherry-1234")
        await model.refresh()
        await model.keepActive()

        await fake.advanceClock(by: 3601)
        await model.refresh()

        #expect(model.keepAliveTask == nil)
    }

    @Test func keepActiveOnAColdSpriteWakesItKnowingly() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "quiet-frog-5678", status: .cold)
        let model = SpriteDetailModel(platform: fake, sprite: "quiet-frog-5678")
        await model.refresh()

        await model.keepActive()

        #expect(model.metadata?.status == .running)
        #expect(model.keepAliveTask != nil)
    }

    @Test func wakeToInspectHoldsTheSpriteWithAFiveMinuteKeepAlive() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "quiet-frog-5678", status: .cold)
        let model = SpriteDetailModel(platform: fake, sprite: "quiet-frog-5678")
        await model.refresh()

        await model.wakeToInspect()

        let task = try #require(model.keepAliveTask)
        let now = await fake.now
        #expect(task.expiresAt == now.addingTimeInterval(300))
        #expect(model.metadata?.status == .running)
        #expect(!model.needsWakeToInspect)
    }

    @Test func keepActiveExtendsTheWakeHoldToAnHour() async throws {
        // Wake to inspect and Keep active are the same task with different
        // TTLs: extending upgrades the one hold, it does not add a second.
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "quiet-frog-5678", status: .cold)
        let model = SpriteDetailModel(platform: fake, sprite: "quiet-frog-5678")
        await model.refresh()
        await model.wakeToInspect()

        await model.keepActive()

        let now = await fake.now
        #expect(model.keepAliveTask?.expiresAt == now.addingTimeInterval(3600))
        #expect(model.tasks?.count == 1)
    }

    @Test func noOtherFeatureCreatesAKeepAlive() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        await fake.scriptExec(where: { _ in true }) { _, io in io.exit(0) }
        let model = SpriteDetailModel(platform: fake, sprite: "morning-cherry-1234")
        await model.refresh()

        let exec = ExecActionModel(platform: fake, sprite: "morning-cherry-1234")
        await exec.run("echo hi")
        await model.refresh()

        #expect(model.keepAliveTask == nil)
        #expect(try await fake.listTasks(on: "morning-cherry-1234").isEmpty)
    }
}
