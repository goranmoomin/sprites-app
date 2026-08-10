import Foundation
import Security
import Synchronization

/// A setup-token saved for reuse across Sprites: the token plus its mint
/// date. The date is display-only; nothing is keyed off it. There is no
/// refresh chain, so no rotation or atomic-persist discipline applies.
public struct SavedClaudeLogin: Sendable, Equatable, Codable {
    public var token: String
    public var mintedAt: Date

    public init(token: String, mintedAt: Date) {
        self.token = token
        self.mintedAt = mintedAt
    }

    /// The Keychain item encoding, public so the round-trip is testable
    /// without touching a real Keychain.
    public static func encode(_ login: SavedClaudeLogin) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(login)
    }

    public static func decode(_ data: Data) -> SavedClaudeLogin? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SavedClaudeLogin.self, from: data)
    }
}

/// Where the saved Claude login lives between launches. One slot,
/// local-only: forgetting it here revokes nothing and unplants nothing.
public protocol ClaudeLoginStore: Sendable {
    func load() -> SavedClaudeLogin?
    func save(_ login: SavedClaudeLogin)
    func clear()
}

/// Test/preview store.
public final class InMemoryClaudeLoginStore: ClaudeLoginStore {
    private let login = Mutex<SavedClaudeLogin?>(nil)

    public init(login: SavedClaudeLogin? = nil) {
        self.login.withLock { $0 = login }
    }

    public func load() -> SavedClaudeLogin? { login.withLock { $0 } }
    public func save(_ login: SavedClaudeLogin) { self.login.withLock { $0 = login } }
    public func clear() { login.withLock { $0 = nil } }
}

/// Stores the saved login as a generic password in the iOS Keychain, in
/// the KeychainTokenStore idiom.
public final class KeychainClaudeLoginStore: ClaudeLoginStore {
    private let service: String

    public init(service: String = "dev.goranmoomin.sprites.claude-login") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "claude-login",
        ]
    }

    public func load() -> SavedClaudeLogin? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return SavedClaudeLogin.decode(data)
    }

    public func save(_ login: SavedClaudeLogin) {
        guard let data = SavedClaudeLogin.encode(login) else { return }
        clear()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
