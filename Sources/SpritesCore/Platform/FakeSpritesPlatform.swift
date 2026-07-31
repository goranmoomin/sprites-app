import Foundation

/// In-memory simulation of the Sprites platform for tests.
public actor FakeSpritesPlatform: SpritesPlatform {
    /// When false, every call fails as a revoked/invalid token would.
    public var isAuthorized: Bool

    private var sprites: [SpriteMetadata] = []

    public init(isAuthorized: Bool = true) {
        self.isAuthorized = isAuthorized
    }

    public func setAuthorized(_ authorized: Bool) {
        isAuthorized = authorized
    }

    private func checkAuthorized() throws {
        guard isAuthorized else { throw PlatformError.unauthorized }
    }

    public func listSprites() async throws -> [SpriteMetadata] {
        try checkAuthorized()
        return sprites
    }
}
