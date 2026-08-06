# 04 — Login token auto-fill and dashboard redirect

**What to build:** Logging in becomes: tap the button, grab the token from
the Fly dashboard, come back, and find it already filled in.

The in-app browser now opens the Sprites dashboard page
(`fly.io/dashboard/personal/sprites`) instead of the generic tokens page. It
still opens on an explicit button tap — no auto-present (avoids the
re-opening-sheet trap after a rejected token or a mid-session logout). The
pasteboard change count is snapshotted per browser visit; when the sheet is
dismissed and the pasteboard changed during the visit, the app reads it —
accepting the one-time system paste alert, which lands at the exact moment
the user just copied a token on purpose — and, if the contents match the
Sprite token format, writes it into the token field. Never auto-submits: the
user reviews and taps Log in. If the read is denied or the contents don't
match, the flow falls back to today's manual entry.

The token matcher lives in SpritesCore and is unit-tested. Captured format:
`<org-slug>/<number>/<32 hex chars>/<64 hex chars>` — verify the slug
charset against a second org before finalizing the regex.

The Claude Code login flow gets the same treatment: the sign-in link still
opens system Safari (the user's logged-in browser session), and when the
scene becomes active again with a changed pasteboard, the code field fills
with the copied text — unvalidated for now, since nothing auto-submits into
the live PTY. A ticket task: run the interactive login rig once to capture
the real code's shape and add a matcher later.

Update the mvp spec notes and the CONTEXT.md Sprite-token entry, which
describe the old paste-prompt-on-tap design as resolved behavior.

**Blocked by:** None — can start immediately.

**Status:** resolved

- [x] Browser button opens the Sprites dashboard page; no auto-present on
      appear, after a rejected token, or after mid-session logout
- [x] Copy token in browser, dismiss: system paste alert appears once, field
      is filled on match, nothing auto-submits
- [x] Nothing copied during the visit: no alert, no read
- [x] Token matcher in SpritesCore with unit tests; mismatch falls back to
      manual entry with the existing error copy
- [x] Claude flow: returning to the app with a fresh clipboard fills the code
      field; submit stays manual
- [ ] Interactive rig run captures the real Claude code shape (recorded in
      findings); docs updated

## Comments

Implemented. `SpriteTokenFormat` in SpritesCore (unit-tested); LoginView
opens `/dashboard/personal/sprites`, snapshots the pasteboard change count
per visit, and fills the SecureField on dismissal when the pasteboard
changed and matches — no auto-submit, manual entry unchanged as fallback.
The Claude prompt fills its code field on scene reactivation with a fresh
pasteboard (unvalidated by design until the shape is captured). The
interactive rig now logs the code's length/charset classes; the actual
capture run needs a live login session, so that box stays open. CONTEXT.md
Sprite-token entry updated; mvp docs left as historical record.
