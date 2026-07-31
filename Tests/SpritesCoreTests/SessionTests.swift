import Testing
import SpritesCore

@MainActor
struct SessionTests {
    @Test func loggingInWithValidTokenValidatesAndStoresIt() async throws {
        let fake = FakeSpritesPlatform()
        let store = InMemoryTokenStore()
        let session = Session(tokenStore: store, platformFactory: { _ in fake })

        try await session.logIn(token: "valid-token")

        #expect(session.isLoggedIn)
        #expect(store.load() == "valid-token")
    }

    @Test func loggingInWithBadTokenFailsAndStoresNothing() async throws {
        let store = InMemoryTokenStore()
        let session = Session(tokenStore: store, platformFactory: { _ in
            FakeSpritesPlatform(isAuthorized: false)
        })

        await #expect(throws: PlatformError.unauthorized) {
            try await session.logIn(token: "bad-token")
        }
        #expect(!session.isLoggedIn)
        #expect(store.load() == nil)
    }

    @Test func storedTokenRestoresLoggedInSessionAcrossRestart() async throws {
        let fake = FakeSpritesPlatform()
        let store = InMemoryTokenStore(token: "stored-token")
        let session = Session(tokenStore: store, platformFactory: { _ in fake })

        session.restore()

        #expect(session.isLoggedIn)
    }

    @Test func withoutStoredTokenRestoreStaysLoggedOut() async throws {
        let session = Session(tokenStore: InMemoryTokenStore(), platformFactory: { _ in
            FakeSpritesPlatform()
        })

        session.restore()

        #expect(!session.isLoggedIn)
    }

    @Test func revokedTokenReturnsUserToLogin() async throws {
        let fake = FakeSpritesPlatform()
        let store = InMemoryTokenStore()
        let session = Session(tokenStore: store, platformFactory: { _ in fake })
        try await session.logIn(token: "valid-token")

        // Token gets revoked; some later call fails unauthorized.
        await fake.setAuthorized(false)
        let error: any Error
        do {
            _ = try await fake.listSprites()
            Issue.record("expected unauthorized")
            return
        } catch let caught {
            error = caught
        }
        session.handle(error)

        #expect(!session.isLoggedIn)
        #expect(store.load() == nil)
    }

    @Test func nonAuthErrorsDoNotEndTheSession() async throws {
        let fake = FakeSpritesPlatform()
        let session = Session(tokenStore: InMemoryTokenStore(), platformFactory: { _ in fake })
        try await session.logIn(token: "valid-token")

        session.handle(PlatformError.api("transient"))

        #expect(session.isLoggedIn)
    }
}
