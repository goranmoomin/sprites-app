import Foundation
import Observation

/// The sprite list: shallow observation only, refreshed on appear and
/// pull-to-refresh. Never wakes a sprite (ADR 0001).
@MainActor
@Observable
public final class SpriteListModel {
    public private(set) var sprites: [SpriteMetadata] = []
    public private(set) var lastError: Error?
    public private(set) var hasLoaded = false

    private let platform: SpritesPlatform
    private let session: Session?

    public init(platform: SpritesPlatform, session: Session? = nil) {
        self.platform = platform
        self.session = session
    }

    /// Deletes the sprite on the platform, then re-observes the list.
    public func delete(_ name: String) async {
        do {
            try await platform.deleteSprite(named: name)
        } catch {
            lastError = error
            session?.handle(error)
        }
        await refresh()
    }

    public func refresh() async {
        do {
            sprites = try await platform.listSprites()
            lastError = nil
            hasLoaded = true
        } catch {
            lastError = error
            session?.handle(error)
        }
    }
}
