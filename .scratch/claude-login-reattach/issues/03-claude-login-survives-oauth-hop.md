# 03 — Claude login survives the OAuth hop

**What to build:** the Claude Code login flow no longer dies when iOS suspends the app during the out-app Safari/Mail hop. The login PTY keeps running on the sprite regardless of what happens to the socket; the flow lazily reattaches when — and only when — the connection actually died. Demo: start the login, force-drop the connection during the sign-in hop, return, paste the code, login completes.

Behavior at the code-submission phase:

- Stream still live: send the code on the existing socket (the majority path; short hops often survive suspension).
- Stream ended without an exit: that is the drop signature, so attach by the stored session ID, tolerate the scrollback replay, send the code.
- Stream ended with an exit: the process died while the user was away, so clean, explained step failure; retry starts fresh.

Riders that ship in this slice:

- A self-expiring 15-minute keep-alive task exists exactly for the duration of the login step (deleted on step exit; expiry is the dead-man's switch), so the sprite cannot decay toward cold mid-hop.
- Terminal outcomes that aren't a natural process exit (decline, failure, cancel) kill the remote session.
- Flow start sweeps and kills stale login sessions, cleaning historical zombies and making retry idempotent from any wreckage state. Per the ticket-01 spike: the session list reports the resolved executable path plus args (e.g. `/usr/local/.../claude auth login --claudeai`), so match on the argv suffix, never on argv[0]; ignore `is_active` (observed unreliable).
- Spike-confirmed constraints: the scrollback replay is a rendered snapshot that strips OSC-8 hyperlinks — the sign-in URL exists only on the live phase-1 socket and can never be re-parsed from a replay; session IDs are process PIDs and recyclable, valid only within the flow that captured them; attach to a dead session fails at the WebSocket handshake, which the flow treats as "process ended while away".

Accepted limitation: app termination (not suspension) during the hop loses the in-memory session ID — user restarts, the sweep cleans up, fresh URL. Cross-launch resume is deliberately deferred.

**Blocked by:** 01 — Spike (gates the design: if attach-with-stdin or survival-across-decay fails live, redesign first), 02 — Exec-session substrate.

**Status:** resolved (2026-08-05) — except the final on-device live check, which needs a human with the app on a phone.

- [x] Scripted Fake transcript: socket survives the hop, login completes with zero reattaches (existing happy-path test, now running through the new phase-3 logic).
- [x] Scripted Fake transcript: socket drops during the hop, flow attaches by session ID, submits the code, login completes.
- [x] Scripted Fake transcript: process exits during the hop, clean failure message, no hang, retry runs the sweep and starts fresh.
- [x] Keep-alive task appears when the login step starts and is gone after it ends (success and failure paths).
- [x] Declining or cancelling the flow leaves no live login session behind; starting the flow kills any stale login sessions first (sweep is suffix-matched and spares bystander sessions).
- [ ] Live verification: complete a real login on a device with the connection force-dropped during the hop. (Partial live coverage exists: the flow-to-prompt live smoke ran against a real sprite with the new sweep/keep-alive/kill paths, and the declined run left zero sessions and no task on the sprite.)
