import Foundation
import Synchronization

/// Where the Sprite token lives between launches.
public protocol TokenStore: Sendable {
    func load() -> String?
    func save(_ token: String)
    func clear()
}

/// Test/preview store.
public final class InMemoryTokenStore: TokenStore {
    private let token = Mutex<String?>(nil)

    public init(token: String? = nil) {
        self.token.withLock { $0 = token }
    }

    public func load() -> String? { token.withLock { $0 } }
    public func save(_ token: String) { self.token.withLock { $0 = token } }
    public func clear() { token.withLock { $0 = nil } }
}
