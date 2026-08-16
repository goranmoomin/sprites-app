import Foundation
import Security
import Synchronization

/// Where Saved logins live between launches: at most one per Integration
/// id, as an opaque payload the integration itself encodes and decodes.
/// Local-only; forgetting one here revokes nothing and unplants nothing
/// (ADR 0007).
public protocol SavedLoginStore: Sendable {
    func load(for integrationID: String) -> Data?
    func save(_ data: Data, for integrationID: String)
    func clear(for integrationID: String)
}

extension SavedLoginStore {
    /// Typed round trip: JSON with ISO8601 dates, the encoding the Claude
    /// item has always used, so nothing re-mints across this change.
    public func load<Login: Decodable>(_ type: Login.Type, for integrationID: String) -> Login? {
        guard let data = load(for: integrationID) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    public func save<Login: Encodable>(_ login: Login, for integrationID: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(login) else { return }
        save(data, for: integrationID)
    }
}

/// Test/preview store.
public final class InMemorySavedLoginStore: SavedLoginStore {
    private let logins = Mutex<[String: Data]>([:])

    public init() {}

    public func load(for integrationID: String) -> Data? {
        logins.withLock { $0[integrationID] }
    }

    public func save(_ data: Data, for integrationID: String) {
        logins.withLock { $0[integrationID] = data }
    }

    public func clear(for integrationID: String) {
        _ = logins.withLock { $0.removeValue(forKey: integrationID) }
    }
}

/// Stores each saved login as a generic password in the iOS Keychain, one
/// item per integration id, in the KeychainTokenStore idiom.
public final class KeychainSavedLoginStore: SavedLoginStore {
    private let servicePrefix: String

    public init(servicePrefix: String = "dev.goranmoomin.sprites.saved-login") {
        self.servicePrefix = servicePrefix
        // The Claude login predates the central store; move the item users
        // already have so nobody re-mints.
        migrateLegacyItem(
            service: "dev.goranmoomin.sprites.claude-login", account: "claude-login",
            to: ClaudeCodeIntegration.id)
    }

    private func query(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func query(for integrationID: String) -> [String: Any] {
        query(service: "\(servicePrefix).\(integrationID)", account: "saved-login")
    }

    private func read(_ query: [String: Any]) -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func migrateLegacyItem(service: String, account: String, to integrationID: String) {
        let legacy = query(service: service, account: account)
        guard load(for: integrationID) == nil, let data = read(legacy) else { return }
        save(data, for: integrationID)
        SecItemDelete(legacy as CFDictionary)
    }

    public func load(for integrationID: String) -> Data? {
        read(query(for: integrationID))
    }

    public func save(_ data: Data, for integrationID: String) {
        clear(for: integrationID)
        var query = query(for: integrationID)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    public func clear(for integrationID: String) {
        SecItemDelete(query(for: integrationID) as CFDictionary)
    }
}
