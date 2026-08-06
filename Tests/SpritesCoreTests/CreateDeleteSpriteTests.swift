import Testing
import SpritesCore

@MainActor
struct CreateDeleteSpriteTests {
    @Test func suggestedNamesAreAdjectiveNounToken() async throws {
        // With a stubbed RNG picking the first word of each list and token 42,
        // the flyctl word lists give this exact name.
        var draws = [0, 0, 42]
        let name = Haikunator.suggestName(randomNumber: { _ in draws.removeFirst() })
        #expect(name == "autumn-waterfall-42")

        // The default RNG still produces the adjective-noun-token shape.
        let random = Haikunator.suggestName()
        let parts = random.split(separator: "-")
        #expect(parts.count == 3)
        #expect(Int(parts[2]) != nil)
    }

    @Test func createSpriteModelSuggestsAndRegeneratesNames() async throws {
        let model = CreateSpriteModel(platform: FakeSpritesPlatform())

        let first = model.name
        #expect(first.split(separator: "-").count == 3)

        model.suggestAnotherName()
        #expect(model.name != first)
    }

    @Test func createdSpriteAppearsInTheList() async throws {
        let fake = FakeSpritesPlatform()
        let listModel = SpriteListModel(platform: fake)
        let model = CreateSpriteModel(platform: fake)
        model.name = "my-edited-name"

        let created = await model.create()

        #expect(created?.name == "my-edited-name")
        await listModel.refresh()
        #expect(listModel.sprites.map(\.name) == ["my-edited-name"])
    }

    @Test func nameTakenFailureSurfacesInline() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "taken-name-1")
        let model = CreateSpriteModel(platform: fake)
        model.name = "taken-name-1"

        let created = await model.create()

        #expect(created == nil)
        #expect(model.errorMessage != nil)
    }

    @Test func deleteRemovesTheSpriteFromTheList() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "doomed-sprite-1")
        let listModel = SpriteListModel(platform: fake)
        await listModel.refresh()

        let failure = await listModel.delete("doomed-sprite-1").value

        #expect(failure == nil)
        #expect(listModel.sprites.isEmpty)
        #expect(try await fake.listSprites().isEmpty)
    }

    @Test func deleteTracksInFlightSpritesUntilDone() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "doomed-sprite-1")
        await fake.holdDeletes()
        let listModel = SpriteListModel(platform: fake)
        await listModel.refresh()

        let deleting = listModel.delete("doomed-sprite-1")
        try await Task.sleep(for: .milliseconds(50))
        #expect(listModel.deletingSprites == ["doomed-sprite-1"])

        await fake.releaseDeletes()
        let failure = await deleting.value
        #expect(failure == nil)
        #expect(listModel.deletingSprites.isEmpty)
        #expect(listModel.sprites.isEmpty)
    }

    @Test func overlappingDeletesAreTrackedIndependently() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "doomed-sprite-1")
        await fake.addSprite(name: "doomed-sprite-2")
        await fake.holdDeletes()
        let listModel = SpriteListModel(platform: fake)
        await listModel.refresh()

        let first = listModel.delete("doomed-sprite-1")
        let second = listModel.delete("doomed-sprite-2")
        try await Task.sleep(for: .milliseconds(50))
        #expect(listModel.deletingSprites == ["doomed-sprite-1", "doomed-sprite-2"])

        await fake.releaseDeletes()
        _ = await first.value
        _ = await second.value
        #expect(listModel.deletingSprites.isEmpty)
        #expect(listModel.sprites.isEmpty)
    }

    @Test func failedDeleteSurfacesErrorAndClearsInFlight() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "survivor-sprite-1")
        let listModel = SpriteListModel(platform: fake)
        await listModel.refresh()

        let failure = await listModel.delete("no-such-sprite").value

        #expect(failure != nil)
        #expect(listModel.lastError != nil)
        #expect(listModel.deletingSprites.isEmpty)
        #expect(listModel.sprites.map(\.name) == ["survivor-sprite-1"])
    }

    @Test func deleteSucceededButRefreshFailedStillClearsInFlight() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "doomed-sprite-1")
        await fake.holdDeletes()
        let listModel = SpriteListModel(platform: fake)
        await listModel.refresh()

        let deleting = listModel.delete("doomed-sprite-1")
        try await Task.sleep(for: .milliseconds(50))
        // The platform delete lands, then the follow-up list observation fails.
        await fake.setAuthorized(false)
        await fake.releaseDeletes()

        let failure = await deleting.value
        #expect(failure == nil)
        #expect(listModel.deletingSprites.isEmpty)
        #expect(listModel.lastError != nil)

        await fake.setAuthorized(true)
        #expect(try await fake.listSprites().isEmpty)
    }
}
