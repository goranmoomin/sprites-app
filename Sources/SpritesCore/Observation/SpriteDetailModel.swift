import Foundation
import Observation

/// One sprite's detail screen: shallow data always, deep observation only
/// when the sprite is already running or the user explicitly wakes it
/// (ADR 0001). Everything shown is re-observed on each refresh.
@MainActor
@Observable
public final class SpriteDetailModel {
    public let sprite: String

    public private(set) var metadata: SpriteMetadata?
    public private(set) var services: [Service]?
    public private(set) var tasks: [PlatformTask]?
    public private(set) var checkpoints: [Checkpoint]?
    public private(set) var isWaking = false
    public private(set) var lastError: Error?

    /// Per-integration status lines, e.g. "Claude Code: logged in".
    public private(set) var integrationLines: [IntegrationStatusLine]?
    /// One-tap Actions contributed by integrations.
    public private(set) var actions: [SpriteAction]?
    /// Flows the injected integrations currently offer, in registry order.
    public private(set) var offeredFlows: [Flow]?

    public struct IntegrationStatusLine: Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var summary: String
        public var isReady: Bool
    }

    private let platform: SpritesPlatform
    private let session: Session?
    private let integrations: [any Integration]
    private let focusRefreshMinimumInterval: TimeInterval
    private var refreshInFlight: Task<Void, Never>?
    private var lastRefreshEnded: Date?

    public init(
        platform: SpritesPlatform, sprite: String, session: Session? = nil,
        integrations: [any Integration] = Integrations.all,
        focusRefreshMinimumInterval: TimeInterval = 5
    ) {
        self.platform = platform
        self.sprite = sprite
        self.session = session
        self.integrations = integrations
        self.focusRefreshMinimumInterval = focusRefreshMinimumInterval
    }

    /// A Custom service: recognized by no integration; generic controls only.
    public func isCustom(_ service: Service) -> Bool {
        !integrations.contains { $0.recognizes(service) }
    }

    /// A sprite that is not running needs an explicit wake before deep
    /// observation; its detail screen shows "Wake to inspect" instead.
    public var needsWakeToInspect: Bool {
        metadata?.status != .running
    }

    /// Coalesces with any in-flight refresh: concurrent triggers (task,
    /// pull-to-refresh, scene activation) become one observation.
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

    /// Silent refresh for scene activation: skipped when a refresh just
    /// finished (sheet-dismissal handlers already refresh). Shallow first,
    /// deep only while the sprite is running — focus never wakes (ADR 0001).
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
            metadata = try await platform.getSprite(named: sprite)
            lastError = nil
        } catch {
            lastError = error
            session?.handle(error)
            return
        }
        if metadata?.status == .running {
            await deepObserve()
        }
    }

    /// Explicit user choice to wake a sprite and inspect it: holds it
    /// running for a 5-minute window via the app's Keep-alive task.
    public func wakeToInspect() async {
        await keepActive(forSeconds: 300)
    }

    // MARK: Keep-alive (a named platform task the app holds; max 1h)

    public static let keepAliveTaskName = "sprites-app-keep-alive"

    /// The app's Keep-alive, if currently held: visibly just a task.
    public var keepAliveTask: PlatformTask? {
        tasks?.first { $0.name == Self.keepAliveTaskName }
    }

    /// Creates or extends the Keep-alive. On a cold sprite this is a knowing
    /// wake: an explicit user action surfaced as "waking...".
    public func keepActive(forSeconds seconds: Int = 3600) async {
        let needsWake = metadata?.status != .running
        if needsWake { isWaking = true }
        defer { if needsWake { isWaking = false } }
        do {
            try await platform.upsertTask(
                on: sprite, named: Self.keepAliveTaskName, expiringInSeconds: seconds)
        } catch {
            lastError = error
            session?.handle(error)
        }
        await refresh()
    }

    public func releaseKeepAlive() async {
        do {
            try await platform.deleteTask(on: sprite, named: Self.keepAliveTaskName)
        } catch {
            lastError = error
            session?.handle(error)
        }
        await refresh()
    }

    // MARK: Checkpoints

    public private(set) var checkpointProgress: [CheckpointEvent] = []

    /// Manual checkpoints (the primary list). Automatic `auto-*` checkpoints
    /// and the Current pseudo-entry stay out of the way.
    public var manualCheckpoints: [Checkpoint] {
        (checkpoints ?? []).filter { !$0.isAuto && $0.id != "Current" }
    }

    public var automaticCheckpoints: [Checkpoint] {
        (checkpoints ?? []).filter(\.isAuto)
    }

    public func createCheckpoint(comment: String) async {
        await streamCheckpointOperation {
            try await $0.createCheckpoint(on: $1, comment: comment)
        }
    }

    /// Destructive; rolls back agent logins, services, and Pairing made
    /// after the checkpoint. Afterwards the screen simply re-observes.
    public func restoreCheckpoint(id: String) async {
        await streamCheckpointOperation {
            try await $0.restoreCheckpoint(on: $1, id: id)
        }
    }

    private func streamCheckpointOperation(
        _ operation: (SpritesPlatform, String) async throws -> AsyncThrowingStream<CheckpointEvent, Error>
    ) async {
        checkpointProgress = []
        do {
            for try await event in try await operation(platform, sprite) {
                checkpointProgress.append(event)
            }
        } catch {
            // Active sessions dropping mid-restore is tolerated: what matters
            // is what re-observation finds.
            checkpointProgress.append(CheckpointEvent(type: "error", message: String(describing: error)))
        }
        await refresh()
    }

    // MARK: Service lifecycle (deep; the screen re-observes after each)

    public func startService(_ name: String) async {
        await serviceOperation { try await $0.startService(on: $1, named: name) }
    }

    public func stopService(_ name: String) async {
        await serviceOperation { try await $0.stopService(on: $1, named: name) }
    }

    /// The platform's documented restart endpoint does not exist (observed
    /// 404), so restart is an explicit stop followed by start.
    public func restartService(_ name: String) async {
        await serviceOperation {
            try await $0.stopService(on: $1, named: name)
            try await $0.startService(on: $1, named: name)
        }
    }

    public func deleteService(_ name: String) async {
        await serviceOperation { try await $0.deleteService(on: $1, named: name) }
    }

    private func serviceOperation(_ operation: (SpritesPlatform, String) async throws -> Void) async {
        do {
            try await operation(platform, sprite)
        } catch {
            lastError = error
            session?.handle(error)
        }
        await deepObserve()
    }

    private func deepObserve() async {
        do {
            services = try await platform.services(on: sprite)
            tasks = try await platform.listTasks(on: sprite)
            checkpoints = try await platform.checkpoints(on: sprite)
            try await observeIntegrations()
            lastError = nil
        } catch {
            lastError = error
            session?.handle(error)
        }
    }

    private func observeIntegrations() async throws {
        let services = services ?? []
        var lines: [IntegrationStatusLine] = []
        var actions: [SpriteAction] = []
        var flows: [Flow] = []
        for integration in integrations {
            let status = try await integration.observeStatus(
                on: sprite, services: services, platform: platform)
            lines.append(IntegrationStatusLine(
                id: integration.id, title: integration.displayName,
                summary: status.summary, isReady: status.isReady))
            actions.append(contentsOf: integration.actions(services: services, metadata: metadata))
            flows.append(contentsOf: integration.flows(
                status: status, services: services, metadata: metadata))
        }
        // The app's own contribution to the same list: the one-shot exec
        // sheet behind Run command.
        actions.append(SpriteAction(id: "run-command", title: "Run command", kind: .runCommand))
        integrationLines = lines
        self.actions = actions
        offeredFlows = flows
    }
}
