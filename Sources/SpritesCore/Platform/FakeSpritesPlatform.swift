import Foundation

/// In-memory simulation of the Sprites platform for tests.
public actor FakeSpritesPlatform: SpritesPlatform {
    /// When false, every call fails as a revoked/invalid token would.
    public var isAuthorized: Bool

    private var sprites: [String: SpriteMetadata] = [:]
    private var order: [String] = []

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
