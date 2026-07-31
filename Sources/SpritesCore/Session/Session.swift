import Foundation
import Observation

/// The app's identity: one Sprite token. Logging in validates the token with
/// a cheap list call; an unauthorized error at any later point returns the
/// user to the login screen.
@MainActor
@Observable
public final class Session {
    public private(set) var platform: SpritesPlatform?

    private let tokenStore: TokenStore
    private let platformFactory: @Sendable (String) -> SpritesPlatform

    public init(tokenStore: TokenStore, platformFactory: @escaping @Sendable (String) -> SpritesPlatform) {
        self.tokenStore = tokenStore
        self.platformFactory = platformFactory
    }

    public var isLoggedIn: Bool { platform != nil }

    /// Validates the token with a cheap list call, then persists it.
    public func logIn(token: String) async throws {
        let candidate = platformFactory(token)
        _ = try await candidate.listSprites()
        tokenStore.save(token)
        platform = candidate
    }

    /// Boots from a previously stored token, if any. Validation is lazy: a
    /// dead token surfaces as unauthorized on first use and ends the session.
    public func restore() {
        guard let token = tokenStore.load() else { return }
        platform = platformFactory(token)
    }

    /// Models report platform errors here; a revoked/invalid token ends the
    /// session and returns the user to login.
    public func handle(_ error: Error) {
        guard case PlatformError.unauthorized = error else { return }
        tokenStore.clear()
        platform = nil
    }
}
