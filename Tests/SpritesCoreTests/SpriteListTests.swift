import Testing
import SpritesCore

@MainActor
struct SpriteListTests {
    @Test func listShowsNameAndPlatformStatusOfEachSprite() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        await fake.addSprite(name: "quiet-frog-5678", status: .cold)
        let model = SpriteListModel(platform: fake)

        await model.refresh()

        #expect(model.sprites.map(\.name) == ["morning-cherry-1234", "quiet-frog-5678"])
        #expect(model.sprites.map(\.status) == [.running, .cold])
    }

    @Test func refreshReObservesPlatformChanges() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        let model = SpriteListModel(platform: fake)
        await model.refresh()

        await fake.setStatus("morning-cherry-1234", .cold)
        await model.refresh()

        #expect(model.sprites.map(\.status) == [.cold])
    }

    @Test func listingNeverWakesASprite() async throws {
        // ADR 0001: the list uses shallow observation only.
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "quiet-frog-5678", status: .cold)
        let model = SpriteListModel(platform: fake)

        await model.refresh()
        await model.refresh()

        #expect(await fake.deepTouches.isEmpty)
        #expect(await fake.status(of: "quiet-frog-5678") == .cold)
    }

    @Test func listFailureSurfacesErrorInsteadOfSprites() async throws {
        let fake = FakeSpritesPlatform()
        await fake.setAuthorized(false)
        let model = SpriteListModel(platform: fake)

        await model.refresh()

        #expect(model.lastError != nil)
    }
}
