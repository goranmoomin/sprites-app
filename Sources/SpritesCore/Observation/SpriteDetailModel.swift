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

    /// The Board (CONTEXT.md): every integration as one tile in Category
    /// rows, observed status plus the Flows it currently offers. The same
    /// Board serves the create path and the detail screen.
    public private(set) var board: [BoardRow]?
    /// One-tap Actions contributed by integrations.
    public private(set) var actions: [SpriteAction]?

    public struct BoardTile: Sendable, Identifiable {
        public var id: String
        public var title: String
        public var category: Category
        public var status: IntegrationStatus
        /// In the integration's own order (its recommended Flow first).
        public var flows: [Flow]
    }

    public struct BoardRow: Sendable, Identifiable {
        public var category: Category
        public var tiles: [BoardTile]
        public var id: Category { category }
    }

    /// Per-integration status lines, e.g. "Claude Code: logged in", in
    /// registry order.
    public var integrationLines: [IntegrationStatusLine]? {
        board?.flatMap(\.tiles).map {
            IntegrationStatusLine(
                id: $0.id, title: $0.title, summary: $0.status.summary,
                isReady: $0.status.isReady, details: $0.status.details)
        }
    }

    /// Flows the injected integrations currently offer, in registry order.
    public var offeredFlows: [Flow]? {
        board?.flatMap(\.tiles).flatMap(\.flows)
    }

    public struct IntegrationStatusLine: Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var summary: String
        public var isReady: Bool
        public var details: [IntegrationStatus.Detail]
    }

    /// The Requirement sentence a Flow would block on, judged from the
    /// statuses already on the Board (no extra observation); nil when it
    /// can run. FlowRun re-checks for real at start.
    public func blockedReason(for flow: Flow) -> String? {
        guard let tiles = board?.flatMap(\.tiles) else { return nil }
        for requirement in flow.requires
        where !tiles.contains(where: { requirement.anyOf.contains($0.id) && $0.status.isReady }) {
            return Integrations.blockedSentence(for: requirement, among: integrations)
        }
        return nil
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
    /// deep only while the sprite is running: focus never wakes (ADR 0001).
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

    /// One checkpoint operation's visible progress: a status line over the
    /// streamed log, kept after completion until explicitly dismissed or a
    /// new operation starts.
    public struct CheckpointActivity: Equatable {
        public enum Phase: Equatable {
            case running, succeeded, failed
        }
        public var title: String
        public var phase: Phase = .running
        public var log = ""
    }

    public private(set) var checkpointActivity: CheckpointActivity?

    public func dismissCheckpointActivity() {
        checkpointActivity = nil
    }

    /// Manual checkpoints (the primary list), in version order: probed
    /// live: create_time is untrustworthy for ordering. Automatic `auto-*`
    /// checkpoints and the Current pseudo-entry stay out of the way.
    public var manualCheckpoints: [Checkpoint] {
        (checkpoints ?? [])
            .filter { !$0.isAuto && $0.id != "Current" }
            .sorted { (ordinal($0), $0.id) < (ordinal($1), $1.id) }
    }

    private func ordinal(_ checkpoint: Checkpoint) -> Int {
        Int(checkpoint.id.dropFirst()) ?? .max
    }

    public var automaticCheckpoints: [Checkpoint] {
        (checkpoints ?? []).filter(\.isAuto)
    }

    public func createCheckpoint(comment: String) async {
        await streamCheckpointOperation(
            title: "Creating checkpoint...", doneTitle: "Checkpoint created"
        ) {
            try await $0.createCheckpoint(on: $1, comment: comment)
        }
    }

    /// Destructive; rolls back agent logins, services, and Pairing made
    /// after the checkpoint. Afterwards the screen simply re-observes.
    public func restoreCheckpoint(id: String) async {
        await streamCheckpointOperation(
            title: "Restoring \(id)...", doneTitle: "Restored \(id)"
        ) {
            try await $0.restoreCheckpoint(on: $1, id: id)
        }
    }

    public func deleteCheckpoint(id: String) async {
        do {
            try await platform.deleteCheckpoint(on: sprite, id: id)
        } catch {
            lastError = error
            session?.handle(error)
            return
        }
        await refresh()
    }

    private func streamCheckpointOperation(
        title: String, doneTitle: String,
        _ operation: (SpritesPlatform, String) async throws -> AsyncThrowingStream<CheckpointEvent, Error>
    ) async {
        var activity = CheckpointActivity(title: title)
        checkpointActivity = activity
        func append(_ line: String) {
            activity.log = activity.log.isEmpty ? line : activity.log + "\n" + line
        }
        do {
            for try await event in try await operation(platform, sprite) {
                if let message = event.message {
                    append(message)
                    checkpointActivity = activity
                }
            }
            activity.title = doneTitle
            activity.phase = .succeeded
        } catch {
            // Active sessions dropping mid-restore is tolerated: what matters
            // is what re-observation finds. The log keeps the evidence.
            append(String(describing: error))
            activity.title = "Checkpoint operation failed"
            activity.phase = .failed
        }
        checkpointActivity = activity
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
            await observeIntegrations()
            lastError = nil
        } catch {
            lastError = error
            session?.handle(error)
        }
    }

    private func observeIntegrations() async {
        let services = services ?? []
        // Every integration observed at once, results kept in registry
        // order; one failing probe leaves the others intact.
        let statuses = await withTaskGroup(of: (Int, IntegrationStatus).self) { group in
            for (index, integration) in integrations.enumerated() {
                group.addTask { [platform, sprite] in
                    let status = (try? await integration.observeStatus(
                        on: sprite, services: services, platform: platform))
                        ?? IntegrationStatus(summary: "observation failed", isReady: false)
                    return (index, status)
                }
            }
            var statuses = [IntegrationStatus?](repeating: nil, count: integrations.count)
            for await (index, status) in group { statuses[index] = status }
            return statuses.compactMap { $0 }
        }
        var tiles: [BoardTile] = []
        var actions: [SpriteAction] = []
        for (integration, status) in zip(integrations, statuses) {
            tiles.append(BoardTile(
                id: integration.id, title: integration.displayName, category: integration.category,
                status: status,
                flows: integration.flows(status: status, services: services, metadata: metadata)))
            actions.append(contentsOf: integration.actions(services: services, metadata: metadata))
        }
        // The app's own contribution to the same list: the one-shot exec
        // sheet behind Run command.
        actions.append(SpriteAction(id: "run-command", title: "Run command", kind: .runCommand))
        board = Category.allCases.compactMap { category in
            let rowTiles = tiles.filter { $0.category == category }
            return rowTiles.isEmpty ? nil : BoardRow(category: category, tiles: rowTiles)
        }
        self.actions = actions
    }
}
