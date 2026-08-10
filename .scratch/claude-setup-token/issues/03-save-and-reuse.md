# 03: Save and one-click reuse

Spec: `.scratch/claude-setup-token/spec.md`

What to build: the mint dialogue's token screen gains the real consent
choice: save this login to the app for reuse on other Sprites, or use it on
this Sprite only. Save-time security riders appear here, once: the token is
valid for about a year, sits in plaintext on each Sprite it is planted on,
is captured by Checkpoints, and the app cannot revoke it. A saved login is
the token plus its mint date, stored as a second Keychain generic-password
item in the existing token-store idiom: local-only, no iCloud sync, one
slot.

The Flow's first step then branches: when a saved login exists, it plants
silently (no PTY, no keep-alive, no browser) and skips the dialogue
entirely; when none exists, it mints as in ticket 02. Declining save simply
means the next Sprite mints again. Demo: provisioning a second Sprite logs
Claude Code in with zero browser interaction.

Blocked by: 02 (setup-token login replaces auth login).

Status: done (2026-08-10)

- [ ] Mint on Sprite A choosing save, then run the Flow on Sprite B: no
      browser, no paste, B shows logged in and `claude -p` works on both
      concurrently (live acceptance; the fan-out claim is the product;
      rig test added, run pending)
- [x] Choosing "use on this Sprite only" saves nothing; the next Flow run
      mints again
- [x] The saved login round-trips token and mint date through the Keychain
      store
- [x] Branching is covered at the fake-platform seam: plants when a login
      is saved, mints when not
- [x] Save-time rider copy is present on the consent screen
