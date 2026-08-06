import Foundation

/// In-memory simulation of the Sprites platform for tests.
public actor FakeSpritesPlatform: SpritesPlatform {
    /// The ADR 0001 tripwire firing: a deep operation hit a cold sprite
    /// that was never explicitly woken.
    public struct ColdDeepCallViolation: Error {
        public let sprite: String
    }

    /// When false, every call fails as a revoked/invalid token would.
    public var isAuthorized: Bool

    private var sprites: [String: SpriteMetadata] = [:]
    private var order: [String] = []
    private var services: [String: [Service]] = [:]
    private var serviceLogs: [String: [String: String]] = [:]
    private var files: [String: [String: String]] = [:]
    private var tasks: [String: [PlatformTask]] = [:]
    private var checkpointLists: [String: [Checkpoint]] = [:]

    /// What a checkpoint captures: disk, not running processes or tasks.
    private struct CheckpointContents {
        var files: [String: String]
        var services: [Service]
        var serviceLogs: [String: String]
    }

    private var checkpointContents: [String: [String: CheckpointContents]] = [:]

    /// The injected clock: task expiry is evaluated against this.
    public private(set) var now = Date(timeIntervalSince1970: 1_000_000)

    private var wakesHeld = false
    private var heldWakes: [CheckedContinuation<Void, Never>] = []

    private var deletesHeld = false
    private var heldDeletes: [CheckedContinuation<Void, Never>] = []

    /// Sprites knowingly woken: an explicit wake() or a wake-holding task
    /// upsert (Keep-alive). Deep calls on a cold sprite outside this set
    /// are ADR 0001 violations.
    private var explicitlyWoken: Set<String> = []

    private struct ExecScript {
        let matches: @Sendable (ExecCommand) -> Bool
        let script: @Sendable (ExecCommand, FakeExecIO) async -> Void
    }

    private var execScripts: [ExecScript] = []

    /// Persistent session records (PID-style ids) that outlive their sockets.
    private var execRecords: [String: FakeExecRecord] = [:]
    private var execRecordOrder: [String] = []
    private var nextExecSessionID = 101

    /// Commands the app actually ran, for behavioral assertions.
    public private(set) var execLog: [(sprite: String, command: ExecCommand)] = []

    /// Reattaches the app performed, for lazy-reattach assertions.
    public private(set) var attachLog: [(sprite: String, sessionID: String)] = []

    /// Kills the app requested, for session-hygiene assertions.
    public private(set) var killLog: [(sprite: String, sessionID: String)] = []

    /// Sprite names touched by deep observation (exec/services/tasks/etc.).
    /// ADR 0001 compliance tests assert on this.
    public private(set) var deepTouches: [String] = []

    public init(isAuthorized: Bool = true) {
        self.isAuthorized = isAuthorized
    }

    public func setAuthorized(_ authorized: Bool) {
        isAuthorized = authorized
    }

    private func checkAuthorized() throws {
        guard isAuthorized else { throw PlatformError.unauthorized }
    }

    // MARK: Test setup and inspection

    public func addSprite(name: String, status: SpriteStatus = .cold) {
        sprites[name] = SpriteMetadata(
            name: name,
            status: status,
            url: URL(string: "https://\(name)-fake.sprites.app")
        )
        order.append(name)
    }

    public func setStatus(_ name: String, _ status: SpriteStatus) {
        sprites[name]?.status = status
    }

    public func status(of name: String) -> SpriteStatus? {
        sprites[name]?.status
    }

    public func setService(on sprite: String, _ service: Service) {
        services[sprite, default: []].removeAll { $0.name == service.name }
        services[sprite, default: []].append(service)
    }

    public func setTask(on sprite: String, _ task: PlatformTask) {
        tasks[sprite, default: []].removeAll { $0.name == task.name }
        tasks[sprite, default: []].append(task)
    }

    public func setCheckpoint(on sprite: String, _ checkpoint: Checkpoint) {
        checkpointLists[sprite, default: []].append(checkpoint)
    }

    public func setServiceLogs(on sprite: String, service: String, _ logs: String) {
        serviceLogs[sprite, default: [:]][service] = logs
    }

    public func setFile(on sprite: String, path: String, content: String) {
        files[sprite, default: [:]][path] = content
    }

    public func removeFile(on sprite: String, path: String) {
        files[sprite]?.removeValue(forKey: path)
    }

    public func fileContents(on sprite: String, path: String) -> String? {
        files[sprite]?[path]
    }

    public func advanceClock(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }

    /// Makes wake() block until releaseWakes(), to observe "waking..." states.
    public func holdWakes() {
        wakesHeld = true
    }

    public func releaseWakes() {
        wakesHeld = false
        for continuation in heldWakes { continuation.resume() }
        heldWakes = []
    }

    /// Makes deleteSprite() block after the platform-side removal until
    /// releaseDeletes(), to observe in-flight delete states.
    public func holdDeletes() {
        deletesHeld = true
    }

    public func releaseDeletes() {
        deletesHeld = false
        for continuation in heldDeletes { continuation.resume() }
        heldDeletes = []
    }

    /// Registers a canned CLI dialogue. The first matching script answers an
    /// exec; unmatched commands exit 127 with a visible complaint.
    public func scriptExec(
        where matches: @escaping @Sendable (ExecCommand) -> Bool,
        _ script: @escaping @Sendable (ExecCommand, FakeExecIO) async -> Void
    ) {
        execScripts.append(ExecScript(matches: matches, script: script))
    }

    // MARK: Deep-touch bookkeeping

    /// Every deep call funnels through here: it records the touch and wakes
    /// a cold sprite, exactly like the real platform treats activity. Deep
    /// on a cold, never-woken sprite fails loudly (ADR 0001 tripwire).
    private func deepTouch(_ name: String) throws -> SpriteMetadata {
        try checkAuthorized()
        guard var sprite = sprites[name] else { throw PlatformError.notFound }
        guard sprite.status != .cold || explicitlyWoken.contains(name) else {
            throw ColdDeepCallViolation(sprite: name)
        }
        deepTouches.append(name)
        if sprite.status != .running {
            sprite.status = .running
            sprites[name] = sprite
        }
        return sprite
    }

    // MARK: SpritesPlatform

    public func getSprite(named name: String) async throws -> SpriteMetadata {
        try checkAuthorized()
        guard let sprite = sprites[name] else { throw PlatformError.notFound }
        return sprite
    }

    public func setURLVisibility(sprite name: String, _ visibility: URLVisibility) async throws {
        try checkAuthorized()
        guard sprites[name] != nil else { throw PlatformError.notFound }
        sprites[name]?.urlVisibility = visibility
    }

    /// Test helper mirroring the discipline: an explicit wake is knowing.
    public func wake(sprite name: String) async throws {
        try checkAuthorized()
        guard sprites[name] != nil else { throw PlatformError.notFound }
        if wakesHeld {
            await withCheckedContinuation { heldWakes.append($0) }
        }
        explicitlyWoken.insert(name)
        sprites[name]?.status = .running
    }

    public func services(on sprite: String) async throws -> [Service] {
        _ = try deepTouch(sprite)
        return services[sprite] ?? []
    }

    public func listTasks(on sprite: String) async throws -> [PlatformTask] {
        _ = try deepTouch(sprite)
        return (tasks[sprite] ?? []).filter { task in
            guard let expiresAt = task.expiresAt else { return true }
            return expiresAt > now
        }
    }

    public func upsertTask(on sprite: String, named name: String, expiringInSeconds seconds: Int) async throws {
        // Holding a sprite awake is itself a knowing wake (Keep-alive on a
        // cold sprite), so it passes the cold-deep tripwire.
        explicitlyWoken.insert(sprite)
        if wakesHeld, sprites[sprite]?.status != .running {
            await withCheckedContinuation { heldWakes.append($0) }
        }
        _ = try deepTouch(sprite)
        setTask(on: sprite, PlatformTask(
            name: name, startedAt: now, expiresAt: now.addingTimeInterval(TimeInterval(seconds))))
    }

    public func deleteTask(on sprite: String, named name: String) async throws {
        _ = try deepTouch(sprite)
        tasks[sprite]?.removeAll { $0.name == name }
    }

    public func checkpoints(on sprite: String) async throws -> [Checkpoint] {
        _ = try deepTouch(sprite)
        return checkpointLists[sprite] ?? []
    }

    public func deleteCheckpoint(on sprite: String, id: String) async throws {
        _ = try deepTouch(sprite)
        guard id != "Current" else {
            throw PlatformError.api("cannot delete active checkpoint")
        }
        guard checkpointLists[sprite]?.contains(where: { $0.id == id }) == true else {
            throw PlatformError.notFound
        }
        checkpointLists[sprite]?.removeAll { $0.id == id }
        checkpointContents[sprite]?.removeValue(forKey: id)
    }

    public func createCheckpoint(on sprite: String, comment: String)
        async throws -> AsyncThrowingStream<CheckpointEvent, Error>
    {
        _ = try deepTouch(sprite)
        let id = "v\((checkpointLists[sprite] ?? []).filter { !$0.isAuto }.count + 1)"
        checkpointLists[sprite, default: []].append(
            Checkpoint(id: id, createTime: now, comment: comment, isAuto: false))
        checkpointContents[sprite, default: [:]][id] = CheckpointContents(
            files: files[sprite] ?? [:],
            services: services[sprite] ?? [],
            serviceLogs: serviceLogs[sprite] ?? [:])
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: CheckpointEvent.self)
        continuation.yield(CheckpointEvent(type: "info", message: "Creating checkpoint..."))
        continuation.yield(CheckpointEvent(type: "info", message: "  ID: \(id)"))
        continuation.yield(CheckpointEvent(type: "complete", message: "Checkpoint created"))
        continuation.finish()
        return stream
    }

    public func restoreCheckpoint(on sprite: String, id: String)
        async throws -> AsyncThrowingStream<CheckpointEvent, Error>
    {
        _ = try deepTouch(sprite)
        guard let contents = checkpointContents[sprite]?[id] else { throw PlatformError.notFound }
        files[sprite] = contents.files
        services[sprite] = contents.services
        serviceLogs[sprite] = contents.serviceLogs
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: CheckpointEvent.self)
        continuation.yield(CheckpointEvent(type: "info", message: "Restoring \(id)..."))
        continuation.yield(CheckpointEvent(type: "complete", message: "Restore complete"))
        continuation.finish()
        return stream
    }

    public func upsertService(on sprite: String, named name: String, definition: ServiceDefinition)
        async throws -> AsyncThrowingStream<ServiceUpsertEvent, Error>
    {
        _ = try deepTouch(sprite)
        setService(
            on: sprite,
            Service(
                name: name, cmd: definition.cmd, args: definition.args, dir: definition.dir,
                env: definition.env, httpPort: definition.httpPort, needs: definition.needs,
                state: ServiceState(status: .running, pid: 1000 + (services[sprite]?.count ?? 0))))
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: ServiceUpsertEvent.self)
        continuation.yield(ServiceUpsertEvent(type: "started", message: "starting \(name)"))
        continuation.yield(ServiceUpsertEvent(type: "complete", message: "service \(name) running"))
        continuation.finish()
        return stream
    }

    private func setServiceStatus(on sprite: String, named name: String, _ status: ServiceStatus) throws {
        guard let index = services[sprite]?.firstIndex(where: { $0.name == name }) else {
            throw PlatformError.notFound
        }
        services[sprite]![index].state = ServiceState(
            status: status, pid: status == .running ? 1234 : nil)
    }

    public func startService(on sprite: String, named name: String) async throws {
        _ = try deepTouch(sprite)
        try setServiceStatus(on: sprite, named: name, .running)
    }

    public func stopService(on sprite: String, named name: String) async throws {
        _ = try deepTouch(sprite)
        try setServiceStatus(on: sprite, named: name, .stopped)
    }

    public func deleteService(on sprite: String, named name: String) async throws {
        _ = try deepTouch(sprite)
        services[sprite]?.removeAll { $0.name == name }
    }

    public func serviceLogs(on sprite: String, named name: String, lines: Int) async throws -> String {
        _ = try deepTouch(sprite)
        return serviceLogs[sprite]?[name] ?? ""
    }

    public func fileExists(on sprite: String, path: String) async throws -> Bool {
        _ = try deepTouch(sprite)
        return files[sprite]?[path] != nil
    }

    public func readFile(on sprite: String, path: String) async throws -> String? {
        _ = try deepTouch(sprite)
        return files[sprite]?[path]
    }

    public func writeFile(on sprite: String, path: String, content: String) async throws {
        _ = try deepTouch(sprite)
        files[sprite, default: [:]][path] = content
    }

    public func exec(on sprite: String, command: ExecCommand) async throws -> any ExecSession {
        _ = try deepTouch(sprite)
        execLog.append((sprite, command))
        let record = FakeExecRecord(id: String(nextExecSessionID), sprite: sprite, argv: command.argv)
        nextExecSessionID += 1
        execRecords[record.id] = record
        execRecordOrder.append(record.id)
        let io = FakeExecIO(record: record)
        if let script = execScripts.first(where: { $0.matches(command) }) {
            Task { await script.script(command, io) }
        } else {
            io.stderr("fake platform: no scripted dialogue for \(command.argv)\n")
            io.exit(127)
        }
        return record.makeClient()
    }

    public func attachExec(on sprite: String, sessionID: String) async throws -> any ExecSession {
        _ = try deepTouch(sprite)
        attachLog.append((sprite, sessionID))
        guard let record = execRecords[sessionID], record.sprite == sprite, record.isAlive else {
            // A dead or unknown session fails the attach handshake.
            throw PlatformError.notFound
        }
        return record.makeClient()
    }

    public func listExecSessions(on sprite: String) async throws -> [ExecSessionSummary] {
        _ = try deepTouch(sprite)
        return execRecordOrder.compactMap { execRecords[$0] }
            .filter { $0.sprite == sprite && $0.isAlive }
            .map { ExecSessionSummary(id: $0.id, command: $0.command) }
    }

    public func killExecSession(on sprite: String, sessionID: String) async throws {
        _ = try deepTouch(sprite)
        killLog.append((sprite, sessionID))
        guard let record = execRecords[sessionID], record.sprite == sprite, record.isAlive else {
            throw PlatformError.notFound
        }
        record.kill()
    }

    /// Shallow observations performed, for refresh-coalescing assertions.
    public private(set) var listSpritesCalls = 0

    public func listSprites() async throws -> [SpriteMetadata] {
        listSpritesCalls += 1
        try checkAuthorized()
        return order.compactMap { sprites[$0] }
    }

    public func createSprite(named name: String) async throws -> SpriteMetadata {
        try checkAuthorized()
        guard sprites[name] == nil else {
            throw PlatformError.api("a sprite named \(name) already exists")
        }
        addSprite(name: name, status: .warm)
        return sprites[name]!
    }

    public func deleteSprite(named name: String) async throws {
        try checkAuthorized()
        guard sprites.removeValue(forKey: name) != nil else {
            throw PlatformError.notFound
        }
        order.removeAll { $0 == name }
        if deletesHeld {
            await withCheckedContinuation { heldDeletes.append($0) }
        }
    }
}
