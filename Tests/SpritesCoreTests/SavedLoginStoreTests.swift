import Foundation
import Testing
import SpritesCore

/// The one central store: typed payloads per integration id, forgetting
/// one leaves the others, and the app-menu line comes from the integration.
struct SavedLoginStoreTests {
    private struct SavedOtherLogin: Codable, Equatable {
        var key: String
    }

    @Test func eachIntegrationHasItsOwnSlot() {
        let store = InMemorySavedLoginStore()
        store.save(SavedClaudeLogin(token: "sk-ant-oat01-A", mintedAt: Date()), for: ClaudeCodeIntegration.id)
        store.save(SavedOtherLogin(key: "tskey-auth-B"), for: "other")

        #expect(store.load(SavedClaudeLogin.self, for: ClaudeCodeIntegration.id)?.token == "sk-ant-oat01-A")
        #expect(store.load(SavedOtherLogin.self, for: "other") == SavedOtherLogin(key: "tskey-auth-B"))

        store.clear(for: ClaudeCodeIntegration.id)
        #expect(store.load(for: ClaudeCodeIntegration.id) == nil)
        #expect(store.load(SavedOtherLogin.self, for: "other") == SavedOtherLogin(key: "tskey-auth-B"))
    }

    @Test func aPayloadOfTheWrongShapeReadsAsNoLogin() {
        let store = InMemorySavedLoginStore()
        store.save(SavedOtherLogin(key: "x"), for: ClaudeCodeIntegration.id)
        #expect(store.load(SavedClaudeLogin.self, for: ClaudeCodeIntegration.id) == nil)
    }

    @Test func integrationsDescribeTheirOwnSavedLogin() {
        let store = InMemorySavedLoginStore()
        let claude = ClaudeCodeIntegration(loginStore: store)
        #expect(claude.describeSavedLogin(in: store) == nil)
        #expect(Integrations.t3Code.describeSavedLogin(in: store) == nil)

        store.save(
            SavedClaudeLogin(token: "sk-ant-oat01-A", mintedAt: Date(timeIntervalSince1970: 1_786_000_000)),
            for: claude.id)
        #expect(claude.describeSavedLogin(in: store)?.hasPrefix("Saved login from ") == true)
    }
}
