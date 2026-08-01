# 08 — Claude Code login Flow

**What to build:** The Claude Code integration's login Flow, end to end. Interactive steps drive a `tty: true` exec session headlessly (ADR 0002): the app starts `claude setup-token`, extracts the OAuth URL from the PTY stream (verified: it appears after "Browser didn't open?" inside an OSC-8 hyperlink), shows native step UI (open-URL button, code paste field), sends the pasted code back over the socket, and verifies login. Setup also installs the Heartbeat hooks (prompt/tool events refresh a short-expiry named task; stop events delete it) into user-level Claude settings. Afterwards the detail screen observes "Claude Code: logged in". A derailed step shows the raw output as text with retry. This ticket builds the TTY exec transport and the Flow engine (step sequencing, interactive/non-interactive modes, failure surface).

**Blocked by:** 04 — Sprite detail with deep observation.

**Status:** resolved

- [ ] Login Flow completes against a scripted fake transcript and against a real sprite
- [ ] OAuth URL is extracted and offered as an open-in-browser button; pasted code completes login
- [ ] No terminal emulator UI anywhere; failure shows raw output as text with retry (ADR 0002)
- [ ] Heartbeat hooks are installed during setup; a Claude prompt on the sprite creates/refreshes the heartbeat task and releases it on stop
- [ ] Detail screen shows "Claude Code: logged in" via observation (config/credential presence), not app-side memory
- [ ] A reworded-prompt fake transcript fails visibly, not silently
- [ ] Empirical check performed: hooks fire when the `claude` CLI is driven programmatically/headlessly (T3 stand-in), recorded in findings.md

## Comments

Implemented and verified against scripted fake transcripts (happy path,
reworded-prompt derail, retry). The two live checks (real-sprite login run
and hooks firing under T3-driven claude) require a real sprite plus a
Claude subscription and remain pending; findings.md already records that a
UserPromptSubmit hook fires for headless `claude -p` even while logged out.

Live validation completed against apptest-probe4 (findings.md, fourth
probe): the full login ran end-to-end through FlowRun with a real OAuth
code. The flow now drives `claude auth login --claudeai` (setup-token
persists nothing by design), verifies via `claude auth status --json`, and
the hooks were seen firing, refreshing, and releasing around a headless
`claude -p`. Only T3-driven claude turns remain unverified (needs a paired
client).
