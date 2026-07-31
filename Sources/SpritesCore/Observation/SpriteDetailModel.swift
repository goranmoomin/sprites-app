import Foundation
import Observation

/// One sprite's detail screen: shallow data always, deep observation only
/// when the sprite is already running or the user explicitly wakes it
/// (ADR 0001). Everything shown is re-observed on each refresh.
@MainActor
@Observable
public final class SpriteDetailModel {
    public let spriteName: String

    public private(set) var metadata: SpriteMetadata?
    public private(set) var services: [Service]?
    public private(set) var tasks: [PlatformTask]?
    public private(set) var checkpoints: [Checkpoint]?
    public private(set) var isWaking = false
    public private(set) var lastError: Error?

    /// Whether the user explicitly woke this sprite to inspect it. Observed
    /// live: exec flips a sprite to running only transiently and it settles
    /// back to warm, so consent (not the status field) gates deep
    /// observation once given (ADR 0001: "or explicit wake").
    private var hasWokenForInspection = false

    private let platform: SpritesPlatform
    private let session: Session?

    public init(platform: SpritesPlatform, spriteName: String, session: Session? = nil) {
        self.platform = platform
        self.spriteName = spriteName
        self.session = session
    }

    /// A sprite that is not running needs an explicit wake before deep
    /// observation; its detail screen shows "Wake to inspect" instead.
    public var needsWakeToInspect: Bool {
        metadata?.status != .running && !hasWokenForInspection
    }

    /// Deletes the sprite on the platform. Returns true when confirmed.
    public func deleteSprite() async -> Bool {
        do {
            try await platform.deleteSprite(named: spriteName)
            return true
        } catch {
            lastError = error
            session?.handle(error)
            return false
        }
    }

    public func refresh() async {
        do {
            metadata = try await platform.getSprite(named: spriteName)
            lastError = nil
        } catch {
            lastError = error
            session?.handle(error)
            return
        }
        if metadata?.status == .running || hasWokenForInspection {
            await deepObserve()
        }
    }

    /// Explicit user choice to wake a cold sprite and inspect it.
    public func wakeToInspect() async {
        isWaking = true
        defer { isWaking = false }
        do {
            try await platform.wake(sprite: spriteName)
        } catch {
            lastError = error
            session?.handle(error)
            return
        }
        hasWokenForInspection = true
        await refresh()
    }

    private func deepObserve() async {
        do {
            services = try await platform.services(on: spriteName)
            tasks = try await platform.listTasks(on: spriteName)
            checkpoints = try await platform.checkpoints(on: spriteName)
            lastError = nil
        } catch {
            lastError = error
            session?.handle(error)
        }
    }
}
