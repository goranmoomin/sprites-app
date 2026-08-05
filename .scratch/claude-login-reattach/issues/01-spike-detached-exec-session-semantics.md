# 01 — Spike: verify detached exec-session semantics live

**What to build:** no product code — a live verification pass against the real Sprites platform, recorded in the findings log in the observed-live style. The Claude Code login redesign (ticket 03) bets on documented-but-unobserved session behaviors; this spike either confirms them or sends ticket 03 back to design before anything is built.

**Blocked by:** None — can start immediately.

**Status:** resolved (2026-08-05, spike sprite `spike-exec-sessions`, since destroyed — see `.scratch/claude-login-reattach/findings.md`)

- [x] `session_info` control message captured verbatim from a real exec connect: field names, `session_id` format, when it arrives relative to output.
- [x] Attach from a fresh connection to a session whose original socket was dropped: scrollback replays as stdout, stdin still reaches the process, exit is delivered on the attached socket.
- [x] Load-bearing: a detached TTY session survives the sprite's running-to-warm decay, and attaching transparently wakes the sprite back into the live process.
- [x] List-sessions response shape recorded (field names for id/command, so exact-command matching is possible) and kill semantics observed (signal, exit event, session disappears from the list).
- [x] Findings recorded in the findings log; any doc-vs-reality divergence explicitly called out with its impact on ticket 03.

Verdict: design green-lit. Both gating behaviors (stdin-after-reattach, survival across warm decay with transparent wake) confirmed. Corrections folded into tickets 02/03: list `command` is the resolved executable path + args, so the sweep matches on argv suffix; scrollback replay strips OSC-8, so the sign-in URL is only capturable live in phase 1; session ids are PIDs (recyclable — valid only within the capturing flow); `is_active` is unreliable; a detached session does not hold the sprite running.
