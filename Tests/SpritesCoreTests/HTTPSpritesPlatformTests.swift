import Foundation
import Replay
import Testing
import SpritesCore

@Suite(.playbackIsolated(replaysFrom: Bundle.module))
struct HTTPSpritesPlatformTests {
    @Test(.replay("listSprites", matching: [.method, .url, .headers(["Authorization"])], filters: [], scope: .test))
    func listCallSendsBearerTokenAndDecodesSpriteMetadata() async throws {
        let platform = HTTPSpritesPlatform(token: "test-token", session: Replay.session)

        let sprites = try await platform.listSprites()

        #expect(sprites == [
            SpriteMetadata(
                name: "morning-cherry-1234",
                status: .warm,
                url: URL(string: "https://morning-cherry-1234-bhmkr.sprites.app"),
                urlVisibility: .private
            ),
            SpriteMetadata(
                name: "quiet-frog-5678",
                status: .cold,
                url: URL(string: "https://quiet-frog-5678-bhmkr.sprites.app"),
                urlVisibility: .public
            ),
        ])
    }

    @Test(.replay("listSpritesNovelStatus", matching: [.method, .url, .headers(["Authorization"])], filters: [], scope: .test))
    func novelStatusValueDecodesToUnknownShownVerbatim() async throws {
        let platform = HTTPSpritesPlatform(token: "test-token", session: Replay.session)

        let sprites = try await platform.listSprites()

        #expect(sprites.first?.status == .unknown("hibernating"))
        #expect(sprites.first?.status.display == "hibernating")
    }

    @Test(.replay("listSpritesUnauthorized", matching: [.method, .url], filters: [], scope: .test))
    func http401SurfacesAsUnauthorized() async throws {
        let platform = HTTPSpritesPlatform(token: "revoked-token", session: Replay.session)

        await #expect(throws: PlatformError.unauthorized) {
            _ = try await platform.listSprites()
        }
    }
}
