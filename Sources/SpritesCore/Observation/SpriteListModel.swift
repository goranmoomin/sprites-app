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
    private let focusRefreshMinimumInterval: TimeInterval
    private var refreshInFlight: Task<Void, Never>?
    private var lastRefreshEnded: Date?

    public init(
        platform: SpritesPlatform, session: Session? = nil,
        focusRefreshMinimumInterval: TimeInterval = 5
    ) {
        self.platform = platform
        self.session = session
        self.focusRefreshMinimumInterval = focusRefreshMinimumInterval
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

    /// Coalesces with any in-flight refresh: concurrent triggers (task,
    /// pull-to-refresh, scene activation, navigate-back) become one
    /// observation.
    public func refresh() async {
        if let refreshInFlight {
            await refreshInFlight.value
            return
        }
        let task = Task { await performRefresh() }
        refreshInFlight = task
        await task.value
        refreshInFlight = nil
        lastRefreshEnded = Date()
    }

    /// Silent refresh for scene activation and navigating back: skipped
    /// when a refresh just finished. Shallow only: never wakes (ADR 0001).
    public func refreshOnFocus() async {
        if refreshInFlight == nil, let lastRefreshEnded,
            Date().timeIntervalSince(lastRefreshEnded) < focusRefreshMinimumInterval
        {
            return
        }
        await refresh()
    }

    private func performRefresh() async {
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
