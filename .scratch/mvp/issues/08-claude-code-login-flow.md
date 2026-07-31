# 08 — Claude Code login Flow

**What to build:** The Claude Code integration's login Flow, end to end. Interactive steps drive a `tty: true` exec session headlessly (ADR 0002): the app starts `claude setup-token`, extracts the OAuth URL from the PTY stream (verified: it appears after "Browser didn't open?" inside an OSC-8 hyperlink), shows native step UI (open-URL button, code paste field), sends the pasted code back over the socket, and verifies login. Setup also installs the Heartbeat hooks (prompt/tool events refresh a short-expiry named task; stop events delete it) into user-level Claude settings. Afterwards the detail screen observes "Claude Code: logged in". A derailed step shows the raw output as text with retry. This ticket builds the TTY exec transport and the Flow engine (step sequencing, interactive/non-interactive modes, failure surface).

**Blocked by:** 04 — Sprite detail with deep observation.

**Status:** ready-for-agent

- [ ] Login Flow completes against a scripted fake transcript and against a real sprite
- [ ] OAuth URL is extracted and offered as an open-in-browser button; pasted code completes login
- [ ] No terminal emulator UI anywhere; failure shows raw output as text with retry (ADR 0002)
- [ ] Heartbeat hooks are installed during setup; a Claude prompt on the sprite creates/refreshes the heartbeat task and releases it on stop
- [ ] Detail screen shows "Claude Code: logged in" via observation (config/credential presence), not app-side memory
- [ ] A reworded-prompt fake transcript fails visibly, not silently
- [ ] Empirical check performed: hooks fire when the `claude` CLI is driven programmatically/headlessly (T3 stand-in), recorded in findings.md
