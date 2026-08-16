# 04 - Central typed SavedLoginStore

**What to build:** One store for saved logins, holding at most one per Integration id as an opaque payload the integration itself encodes and decodes. Claude Code's saved login migrates onto it, including the Keychain item existing users already have, so nobody re-mints. The app menu lists one row per integration that has a saved login, with its display line and a forget action per row.

**Blocked by:** None - can start immediately.

**Status:** ready-for-agent

- [ ] A `SavedLoginStore` protocol with load/save/clear per integration id over `Data`, a Keychain implementation with one item per id under a shared name prefix, and an in-memory implementation for tests
- [ ] `SavedClaudeLogin` is stored through it; the previous Claude Keychain item is read (and moved) on first launch so an existing saved login survives
- [ ] The app menu shows one row per saved login with the integration's display line and a per-row forget; forgetting one leaves the others
- [ ] Claude login reuse tests pass unchanged in behavior against the in-memory store; migration is tested
