# 01 — Log in with a Sprite token

**What to build:** The app boots to a login screen. A button opens an in-app browser to the Fly dashboard token page; on return, a copied token is offered one-tap (system paste prompt), with a manual paste field as fallback. The token is validated with a cheap sprite-list call, stored in the Keychain, and the user lands on an (empty) sprite list. A revoked or invalid token at any later point returns to login. This ticket bootstraps the project: SwiftUI app, the single Sprites-platform seam protocol, the real HTTP client, the in-memory fake, and Swift Testing.

**Blocked by:** None — can start immediately.

**Status:** resolved

- [ ] Tapping Log in opens the Fly dashboard token page in an in-app browser
- [ ] Returning with a token on the clipboard offers one-tap use; manual paste works
- [ ] A bad token fails at login with a clear error; a good token proceeds
- [ ] Token persists in the Keychain across app restarts
- [ ] An invalidated token drops the user back to the login screen
- [ ] Use-case tests run against the in-memory fake platform; the real client is exercised for the list call shape

## Comments

Superseded in part by `.scratch/ui-fixes/issues/04-login-token-autofill.md`:
the browser now opens the Sprites dashboard page and a copied token matching
the captured format auto-fills the token field (no separate "Use copied
token" button). Manual paste, validation, Keychain storage, and revocation
behavior are unchanged.
