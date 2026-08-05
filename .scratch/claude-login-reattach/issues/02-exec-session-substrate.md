# 02 — Exec-session substrate: identity, attach, list, kill

**What to build:** exec sessions become first-class, re-findable platform objects instead of fire-and-forget sockets. A session exposes the platform's session ID (today the `session_info` control message is discarded). The platform can attach to an existing session by ID — receiving the scrollback replay as ordinary output and a working stdin — plus list active sessions and kill one. The Fake platform models sessions that outlive their sockets and replay scrollback, so flow-level disconnection tests become possible.

**Blocked by:** None. Ticket 01's findings are in (`.scratch/claude-login-reattach/findings.md`): build against the observed shapes — `session_info` re-sent on every attach with `session_id` as a decimal PID string and untrustworthy `cols`/`rows`; list `command` is resolved path + args; exit arrives as a text frame followed by an abrupt TCP drop, no WS close frame.

**Status:** resolved (2026-08-05)

- [x] A started exec session surfaces its platform session ID to callers (real and Fake).
- [x] Attach-by-ID returns a normal exec session: scrollback arrives as stdout, subsequent stdin reaches the process, exit is delivered.
- [x] Active sessions can be listed with enough fidelity to match on the exact command; a session can be killed and stops appearing.
- [x] Fake platform: a scripted session persists after its socket is cancelled and replays its scrollback on attach; a scripted detach, attach, kill round trip passes in tests.
- [x] Existing exec consumers (one-shot capturing runs, flows) are unaffected (full suite green).

Also verified against the real platform through the app's own client code: the
`execSessionSurvivesDetachAttachesAndDies` live smoke (detach, list, attach
with scrollback replay, stdin, kill) passed on a live sprite.
