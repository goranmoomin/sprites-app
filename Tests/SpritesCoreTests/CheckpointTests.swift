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

        #expect(model.checkpointProgress.first?.type == "info")
        #expect(model.checkpointProgress.last?.type == "complete")
        let checkpoint = try #require(model.checkpoints?.last)
        #expect(checkpoint.comment == "before risky work")
        #expect(!checkpoint.isAuto)
    }

    @Test func restoreRollsBackToObservedEarlierState() async throws {
        let (fake, model) = await makeModel()

        // A checkpoint of the clean sprite.
        await model.createCheckpoint(comment: "clean")
        let clean = try #require(model.checkpoints?.last)

        // Later: an agent login and a service exist.
        await fake.setFile(on: Self.sprite, path: "/home/sprite/.claude/.credentials.json", content: "{}")
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
}
