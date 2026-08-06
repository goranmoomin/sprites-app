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

    /// In-flight delete names; rows for these show progress and lose actions.
    public private(set) var deletingSprites: Set<String> = []

    /// Deletes the sprite on the platform, then re-observes the list. Runs
    /// in a model-owned task so dismissing a screen mid-delete cannot cancel
    /// it; the returned task resolves to the failure, if any.
    @discardableResult
    public func delete(_ name: String) -> Task<Error?, Never> {
        Task {
            deletingSprites.insert(name)
            defer { deletingSprites.remove(name) }
            do {
                try await platform.deleteSprite(named: name)
            } catch {
                lastError = error
                session?.handle(error)
                return error
            }
            await refresh()
            return nil
        }
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
