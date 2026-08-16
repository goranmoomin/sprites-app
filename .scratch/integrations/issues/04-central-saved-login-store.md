# 04 - Central typed SavedLoginStore

**What to build:** One store for saved logins, holding at most one per Integration id as an opaque payload the integration itself encodes and decodes. Claude Code's saved login migrates onto it, including the Keychain item existing users already have, so nobody re-mints. The app menu lists one row per integration that has a saved login, with its display line and a forget action per row.

**Blocked by:** None - can start immediately.

**Status:** resolved

- [x] A `SavedLoginStore` protocol with load/save/clear per integration id over `Data`, a Keychain implementation with one item per id under a shared name prefix, and an in-memory implementation for tests
- [x] `SavedClaudeLogin` is stored through it; the previous Claude Keychain item is read (and moved) on first launch so an existing saved login survives
- [x] The app menu shows one row per saved login with the integration's display line and a per-row forget; forgetting one leaves the others
- [x] Claude login reuse tests pass unchanged in behavior against the in-memory store; migration is tested

## Answer

Done in cb0fa87. `SavedLoginStore` protocol with typed JSON/ISO8601 helpers, `KeychainSavedLoginStore` (one item per id, migrates the legacy Claude item in init), `InMemorySavedLoginStore`; `Integrations.savedLogins`; app menu lists one row per saved login with per-row forget. Migration is exercised only through the Keychain path (not unit-testable without a Keychain); the payload encoding is pinned by test.
