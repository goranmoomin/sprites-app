import Foundation
import Testing
import SpritesCore

/// The ADR 0001 discipline as a failing test: the fake platform trips on
/// any deep operation against a cold sprite that was never knowingly woken.
@MainActor
struct ColdDeepCallTripwireTests {
    static let sprite = "quiet-frog-5678"

    @Test func deepCallOnAColdNeverWokenSpriteFailsLoudly() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .cold)

        await #expect(throws: FakeSpritesPlatform.ColdDeepCallViolation.self) {
            _ = try await fake.services(on: Self.sprite)
        }
        await #expect(throws: FakeSpritesPlatform.ColdDeepCallViolation.self) {
            _ = try await fake.fileExists(on: Self.sprite, path: "/anything")
        }
    }

    @Test func anExplicitWakeAllowsDeepCalls() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .cold)

        try await fake.wake(sprite: Self.sprite)

        #expect(try await fake.services(on: Self.sprite) == [])
    }

    @Test func keepAliveOnAColdSpriteIsAKnowingWakeNotAViolation() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .cold)
        let model = SpriteDetailModel(platform: fake, sprite: Self.sprite)
        await model.refresh()

        await model.keepActive()

        #expect(model.lastError == nil)
        #expect(model.keepAliveTask != nil)
    }
}
