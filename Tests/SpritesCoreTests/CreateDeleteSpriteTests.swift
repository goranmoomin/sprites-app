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

        await listModel.delete("doomed-sprite-1")

        #expect(listModel.sprites.isEmpty)
        #expect(try await fake.listSprites().isEmpty)
    }
}
