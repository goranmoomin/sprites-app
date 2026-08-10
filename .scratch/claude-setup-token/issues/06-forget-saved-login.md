# 06: Forget saved login app menu

Spec: `.scratch/claude-setup-token/spec.md`

What to build: the sprite list gains the app's first app-level toolbar
menu. Its one item shows the saved Claude login's mint date ("saved
2026-08-10") and offers Forget; the confirmation reminds that forgetting
removes the token from this app only: it does not revoke the token and does
not unplant it from Sprites it is already on. When no login is saved, the
item reflects that instead of offering Forget.

The mint date is display-only: no expiry timers or warnings key off it.
This menu is the natural seed for future app-level items (platform logout
has no UI today either).

Blocked by: 03 (save and one-click reuse).

Status: done (2026-08-10)

- [x] With a saved login: menu shows the mint date, Forget clears the
      Keychain slot, and the next login Flow run mints again
- [x] Without a saved login: no Forget offered
- [x] Forget confirmation carries the does-not-revoke, does-not-unplant
      copy
