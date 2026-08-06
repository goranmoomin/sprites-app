import Foundation
import Testing
import SpritesCore

/// Focus-triggered refreshes: silent, coalesced, and never waking. The
/// scene-phase and navigation triggers live in the views; these suites pin
/// the model behavior they call into.
@MainActor
struct RefreshOnFocusTests {
    @Test func focusRefreshOnAColdSpriteStaysShallow() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "quiet-frog-5678", status: .cold)
        let model = SpriteDetailModel(
            platform: fake, sprite: "quiet-frog-5678", focusRefreshMinimumInterval: 0)

        await model.refreshOnFocus()

        #expect(model.metadata?.status == .cold)
        #expect(model.needsWakeToInspect)
        #expect(model.services == nil)
        #expect(model.lastError == nil)
    }

    @Test func focusRefreshGoesDeepOnARunningSprite() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        await fake.setService(on: "morning-cherry-1234", Service(name: "custom", cmd: "/bin/x", args: []))
        let model = SpriteDetailModel(
            platform: fake, sprite: "morning-cherry-1234", focusRefreshMinimumInterval: 0)

        await model.refreshOnFocus()

        #expect(model.services?.map(\.name) == ["custom"])
    }

    @Test func focusRefreshSkipsWhenARefreshJustFinished() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234")
        let model = SpriteListModel(platform: fake)
        await model.refresh()
        let calls = await fake.listSpritesCalls

        await model.refreshOnFocus()

        #expect(await fake.listSpritesCalls == calls)
    }

    @Test func concurrentRefreshesCoalesceIntoOneObservation() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234")
        let model = SpriteListModel(platform: fake)

        async let first: Void = model.refresh()
        async let second: Void = model.refresh()
        _ = await (first, second)

        #expect(await fake.listSpritesCalls == 1)
        #expect(model.sprites.count == 1)
    }
}
