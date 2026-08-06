# Claude Code service — exploration findings

Evidence for the spec in this directory. Sources: code deep-dive at
`d820891`, live probes via the authenticated `sprite` CLI against a
throwaway sprite (2026-08-04), platform docs (keeping-sprites-running,
API reference), and prior live findings in `.scratch/mvp/findings.md`.

## Current heartbeat mechanism

- Installed by a single step inside the Claude Code login Flow. Two shell
  commands are written into the sprite user's Claude settings:
  refresh = `sprite-env curl -s -X PUT -d '{"name":"claude-heartbeat","expire":"5m"}' /v1/tasks/claude-heartbeat`,
  release = `sprite-env curl -s -X DELETE /v1/tasks/claude-heartbeat`.
- Hook wiring: `UserPromptSubmit` → refresh, `PostToolUse` → refresh,
  `Stop` → release. No `PreToolUse`. `SubagentStop` was deliberately given
  no release hook (a subagent can finish while the parent turn keeps
  working). No matcher, no hook timeout is set.
- The install *assigns* rather than merges — it clobbers any pre-existing
  user hooks on those three events.
- The 5-minute TTL is a string literal in the hook command; nothing else
  parameterizes it and no test asserts it.
- Hooks live at the user level, so they also cover T3-driven `claude` turns
  (not yet live-verified under T3; noted as outstanding in mvp findings).
- The install step runs only inside the login Flow, and the login Flow is
  offered only when not logged in. **An already-logged-in sprite cannot
  receive updated hooks without logging out** — no repair/upgrade path.
- Live-verified (mvp findings): hooks fire for headless `claude -p`; the
  task appears during a turn, PUT refreshes it, Stop releases it. POST is
  create-only (409 on an existing name); PUT is the upsert.

## Platform facts (probed live 2026-08-04, plus official docs)

- **CPU activity alone does not prevent pausing.** Only the Tasks API holds
  a sprite active. Warm pause: VM suspends, compute billing stops, process
  state preserved, wake 100-500ms — but **open TCP connections drop even on
  warm**. Cold: memory dropped, processes die, wake 1-2s. A mid-prompt
  pause therefore likely errors the agent's API connection on resume:
  data-loss-adjacent, not just latency.
- **Task `expire` ceiling is a hard 3600 seconds.** `"2h"` → HTTP 400
  `expire 7200 seconds exceeds maximum 3600 seconds`; `"30m"` and `"1h"`
  accepted. PUT create-or-refreshes and resets `expires_at`.
- **The platform's own documented pattern for long-running work is a
  periodic refresher**: expire 5m, refresh every 60s, "four missed
  heartbeats of margin before the Sprite frees itself". Edge-triggered
  hooks are off-pattern by the platform's own docs.
- The Tasks API is in-sprite only: HTTP over the management socket
  (`sprite-env curl` against `/v1/tasks`), not app-side HTTP.
- **PID 1 is tini** (`/.pilot/tini -- tail -f /dev/null`), Ubuntu 26.04
  LTS. No systemd, no service manager of any kind; exec'd processes appear
  with PPID 0 (injected by the platform's "pilot" agent). The Sprites
  Services API is the only supervisor — a supervised Service is the only
  way to keep a resident process alive across crashes and wakes.
- **The base image ships Bun and Node 24** (also go, deno, cargo, etc.) —
  a script service needs no binary distribution.
- The sprite user has passwordless sudo (not needed for this service, but
  relevant context).

## Gap taxonomy (why hooks alone cannot work)

Claude Code hook events are all edge-triggered; no periodic/ticking event
exists. Any interval longer than the TTL between two edges is a gap by
construction:

1. **Single long tool call** — uncovered. The clock starts at the
   *previous* PostToolUse; adding PreToolUse would only re-arm at t=0 of
   the call. A >5m build/test/fetch expires the task mid-call.
2. **Background jobs** — actively broken, not just uncovered. The tool
   returns immediately (PostToolUse fires at t≈0), the job runs unobserved,
   and when the turn ends **Stop DELETEs the task while the job still
   runs** — an immediate release, not an expiry.
3. **Subagents** — mostly covered by accident: per current docs, subagent
   tool calls fire the same user-level hooks (input carries agent_id),
   while the parent sees task-lifecycle events. A subagent's own long tool
   call is case 1 one level down. Caveat: semantics should be re-verified
   on the pinned claude v2.1.220 on the sprite; on older versions the
   whole subagent duration could be one silent gap.
4. **Multi-session release race** — the task name is a per-sprite
   singleton; with two concurrent sessions (e.g. T3-driven), session A's
   Stop deletes the hold session B relies on. (The same flaw SubagentStop
   was excluded for, one level up.)
5. **Waiting on the human** — permission prompts / elicitation idle the
   agent indefinitely with no tool events; phone locked >5m mid-approval
   pauses the sprite.
6. **Model-side stalls** — long extended thinking, large generations, API
   retry backoff produce no hook events. Usually <5m; not guaranteed.
7. **Compaction** — a silent window; compaction events are unhooked.
8. **Silent failure** — the hook's `curl` has no retry and no timeout set;
   a transient refresh failure just skips a beat with no surface anywhere.

## Candidate designs considered (decision: A-variant, see spec)

- **C — TTL bump + PreToolUse + keep Stop release.** One-line-ish; closes
  1/3/5/6/7 under the TTL; capped at the 1h ceiling; does NOT fix
  background jobs (a deletion, not an expiry); worst-case wasted awake
  time after a crashed session grows to the TTL. Rejected as the shipped
  design because the user's core requirement (background jobs) stays
  broken; superseded rather than staged since the service is wanted anyway.
- **B — hook-spawned detached refresher with a lease file.** Pid-guarded
  `setsid` loop refreshing while lease-fresh or claude-pid-alive; Stop
  clears the lease; refresher deletes after grace. Fixes background jobs
  and the multi-session race without a visible Service, but: hooks must
  fully detach stdio (hook timeouts: 600s default, 30s for
  UserPromptSubmit), orphan risk bounded only by liveness checks, and
  strictly more shell embedded in JSON — the least testable part of the
  codebase.
- **A — resident watcher as a supervised Sprites Service.** Matches the
  platform's own refresher pattern; covers all eight gaps uniformly;
  survives crashes/wakes via the supervisor; observable and recognizable
  by the integration. Chosen, upgraded during design review from "watcher
  script" to "the Claude Code integration's service" — a home the
  integration needs regardless for future credential/auth maintenance.
- Transport choice (hooks → service): Unix-socket HTTP over a spool file.
  UDS HTTP is the platform's own idiom (the in-sprite API is exactly
  that), Bun supports it first-class (`Bun.serve({ unix })`), `curl
  --unix-socket` works in hooks, and it buys a reply channel plus a status
  endpoint. Drawbacks accepted: availability coupling (events lost while
  the service is down) mitigated by the process/transcript evidence
  fallback and `|| true` hook discipline; stale socket file unlinked on
  boot.

## Outstanding verification

- Subagent hook semantics on pinned claude v2.1.220 (do subagent tool
  calls fire user-level PostToolUse? does the parent see task-lifecycle
  events or one long tool call?). Non-blocking — the evidence fallback
  covers either answer — but it sizes the margin.
- Hooks under T3-driven turns (mvp findings' outstanding check) — the
  service's evidence fallback must not depend on the answer, but the
  status endpoint should make the answer observable.
- Whether the transcript files are written during T3-driven headless turns
  (affects the evidence predicate's second clause).
