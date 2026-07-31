import Foundation

/// In-memory simulation of the Sprites platform for tests.
public actor FakeSpritesPlatform: SpritesPlatform {
    /// When false, every call fails as a revoked/invalid token would.
    public var isAuthorized: Bool

    private var sprites: [String: SpriteMetadata] = [:]
    private var order: [String] = []
    private var services: [String: [Service]] = [:]
    private var tasks: [String: [PlatformTask]] = [:]
    private var checkpointLists: [String: [Checkpoint]] = [:]

    private var wakesHeld = false
    private var heldWakes: [CheckedContinuation<Void, Never>] = []

    private struct ExecScript {
        let matches: @Sendable (ExecCommand) -> Bool
        let script: @Sendable (ExecCommand, FakeExecIO) async -> Void
    }

    private var execScripts: [ExecScript] = []

    /// Commands the app actually ran, for behavioral assertions.
    public private(set) var execLog: [(sprite: String, command: ExecCommand)] = []

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

    /// Makes wake() block until releaseWakes(), to observe "waking..." states.
    public func holdWakes() {
        wakesHeld = true
    }

    public func releaseWakes() {
        wakesHeld = false
        for continuation in heldWakes { continuation.resume() }
        heldWakes = []
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
    /// a cold sprite, exactly like the real platform treats activity.
    private func deepTouch(_ name: String) throws -> SpriteMetadata {
        try checkAuthorized()
        guard var sprite = sprites[name] else { throw PlatformError.notFound }
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

    public func wake(sprite name: String) async throws {
        try checkAuthorized()
        guard sprites[name] != nil else { throw PlatformError.notFound }
        if wakesHeld {
            await withCheckedContinuation { heldWakes.append($0) }
        }
        sprites[name]?.status = .running
    }

    public func services(on sprite: String) async throws -> [Service] {
        _ = try deepTouch(sprite)
        return services[sprite] ?? []
    }

    public func listTasks(on sprite: String) async throws -> [PlatformTask] {
        _ = try deepTouch(sprite)
        return tasks[sprite] ?? []
    }

    public func checkpoints(on sprite: String) async throws -> [Checkpoint] {
        _ = try deepTouch(sprite)
        return checkpointLists[sprite] ?? []
    }

    public func exec(on sprite: String, command: ExecCommand) async throws -> any ExecSession {
        _ = try deepTouch(sprite)
        execLog.append((sprite, command))
        if let script = execScripts.first(where: { $0.matches(command) }) {
            return FakeExecSession { io in await script.script(command, io) }
        }
        return FakeExecSession { io in
            io.stderr("fake platform: no scripted dialogue for \(command.argv)\n")
            io.exit(127)
        }
    }

    public func listSprites() async throws -> [SpriteMetadata] {
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
    }
}
