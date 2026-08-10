import Foundation
import Testing
import SpritesCore

@MainActor
struct CheckpointTests {
    static let sprite = "morning-cherry-1234"

    private func makeModel() async -> (FakeSpritesPlatform, SpriteDetailModel) {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        let model = SpriteDetailModel(platform: fake, sprite: Self.sprite)
        await model.refresh()
        return (fake, model)
    }

    @Test func createWithCommentStreamsProgressAndAppearsInTheList() async throws {
        let (_, model) = await makeModel()

        await model.createCheckpoint(comment: "before risky work")

        let activity = try #require(model.checkpointActivity)
        #expect(activity.phase == .succeeded)
        #expect(activity.log.contains("ID: v1"))
        let checkpoint = try #require(model.checkpoints?.last)
        #expect(checkpoint.comment == "before risky work")
        #expect(!checkpoint.isAuto)
    }

    @Test func completedActivityStaysUntilDismissed() async throws {
        let (_, model) = await makeModel()
        await model.createCheckpoint(comment: "kept")

        // The finished log remains readable; only an explicit dismissal,
        // or a new operation, clears it.
        await model.refresh()
        #expect(model.checkpointActivity?.phase == .succeeded)

        model.dismissCheckpointActivity()
        #expect(model.checkpointActivity == nil)
    }

    @Test func aNewOperationReplacesThePreviousActivity() async throws {
        let (_, model) = await makeModel()
        await model.createCheckpoint(comment: "first")
        let firstLog = model.checkpointActivity?.log

        await model.restoreCheckpoint(id: "v1")

        let activity = try #require(model.checkpointActivity)
        #expect(activity.log != firstLog)
        #expect(activity.title.contains("v1"))
        #expect(activity.phase == .succeeded)
    }

    @Test func restoreRollsBackToObservedEarlierState() async throws {
        let (fake, model) = await makeModel()

        // A checkpoint of the clean sprite.
        await model.createCheckpoint(comment: "clean")
        let clean = try #require(model.checkpoints?.last)

        // Later: an agent login and a service exist. The login marker is
        // the planted settings token, which the checkpoint captures.
        await ClaudeCodeLoginFlowTests.plantLoggedIn(fake, sprite: Self.sprite)
        await fake.setService(
            on: Self.sprite,
            Service(name: "t3", cmd: "/home/sprite/.local/bin/t3", args: ["serve"]))
        await model.refresh()
        #expect(model.integrationLines?.first { $0.title == "Claude Code" }?.summary == "logged in")
        #expect(model.services?.isEmpty == false)

        // Restore. Correctness comes entirely from re-observation.
        await model.restoreCheckpoint(id: clean.id)

        #expect(model.integrationLines?.first { $0.title == "Claude Code" }?.summary == "not logged in")
        #expect(model.services?.isEmpty == true)
    }

    @Test func automaticCheckpointsDoNotClutterThePrimaryList() async throws {
        let (fake, model) = await makeModel()
        await fake.setCheckpoint(on: Self.sprite, Checkpoint(id: "auto-1", isAuto: true))
        await model.createCheckpoint(comment: "mine")
        await model.refresh()

        #expect(model.manualCheckpoints.map(\.isAuto) == [false])
        #expect(model.manualCheckpoints.first?.comment == "mine")
        #expect(model.automaticCheckpoints.map(\.id) == ["auto-1"])
    }

    @Test func manualCheckpointsSortByVersionOrdinalNotCreateTime() async throws {
        // Probed live: create_time is untrustworthy for ordering.
        let (fake, model) = await makeModel()
        await fake.setCheckpoint(on: Self.sprite, Checkpoint(id: "v10"))
        await fake.setCheckpoint(on: Self.sprite, Checkpoint(id: "v2"))
        await model.refresh()

        #expect(model.manualCheckpoints.map(\.id) == ["v2", "v10"])
    }

    @Test func deleteRemovesAManualCheckpoint() async throws {
        let (fake, model) = await makeModel()
        await model.createCheckpoint(comment: "doomed")
        let checkpoint = try #require(model.checkpoints?.last)

        await model.deleteCheckpoint(id: checkpoint.id)

        #expect(model.lastError == nil)
        #expect(model.manualCheckpoints.isEmpty)
        #expect(try await fake.checkpoints(on: Self.sprite).isEmpty)
    }

    @Test func theActiveCheckpointRefusesDeletion() async throws {
        // Pinned live: DELETE on the active checkpoint answers 409
        // "cannot delete active checkpoint".
        let (fake, model) = await makeModel()
        await fake.setCheckpoint(on: Self.sprite, Checkpoint(id: "Current"))

        await model.deleteCheckpoint(id: "Current")

        #expect(model.lastError != nil)
        #expect(try await fake.checkpoints(on: Self.sprite).map(\.id) == ["Current"])
    }
}
