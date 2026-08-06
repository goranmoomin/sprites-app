# 01 — Claude Code integration service with heartbeat watcher

Spec: `.scratch/claude-code-service/spec.md`

**What to build:** Claude Code work that runs longer than five minutes — a
long tool call, a subagent, a background job — no longer lets the Sprite
pause mid-prompt. The Claude Code integration installs its own resident
Service on the Sprite, and that Service owns the heartbeat.

The Service is a Bun script (the base image ships Bun and Node; no binary
pipeline) whose source is embedded in this repo, written onto the Sprite
during the login Flow, and defined as a supervised Sprites Service — the
platform supervisor is the only supervisor on a Sprite (PID 1 is tini). It
listens for HTTP over a Unix domain socket, unlinking a stale socket on
boot. This is groundwork the integration needs anyway (future credential
work) and finally gives its service recognition something to recognize.

Hooks become dumb reporters: prompt-submit and post-tool-use POST their stdin
JSON to the socket; Stop reports session end. Every hook command carries a
short timeout and never fails the agent (a down service must not break
Claude). The service keeps per-session leases from these events and refreshes
the singleton `claude-heartbeat` task (5m expiry, ~60s cadence — the
platform's own documented heartbeat pattern; ceiling is a hard 1h) while
there is evidence of live agent work: a fresh lease, or a claude process
alive with a recently written transcript. That second clause is what covers
the gaps hooks cannot see — long tool calls, subagents, background jobs that
outlive the turn (today the Stop hook *deletes* the task while a background
job still runs). When evidence lapses, the service stops refreshing and lets
the task expire; the transcript-recency threshold bounds how long an idle
interactive session can hold the Sprite.

Deployment and observation: the install step is version-stamped; the
integration re-runs it when it observes a stale stamp on an already-logged-in
Sprite (today hooks are only installable at login, so no fix would otherwise
reach existing Sprites). Hook install merges with existing user hooks instead
of clobbering them. The service exposes a status endpoint (hooks version,
active sessions, heartbeat held) that the integration uses as its deep
observation probe. Rewrite the Heartbeat entry in CONTEXT.md.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] Login flow writes the script, defines the supervised Service, installs
      version-stamped hooks that merge with existing user hooks
- [ ] Live probe: a background job or single tool call exceeding 5 minutes
      keeps the Sprite running; turn-end no longer deletes the task while a
      background job runs; idle lets the task expire within the bounded
      window
- [ ] Two concurrent sessions: one ending does not drop the other's hold
- [ ] Hook commands time out fast and never fail the agent when the service
      is down; heartbeat continues via process/transcript evidence
- [ ] Integration recognizes the Service and reads the status endpoint as
      its deep observation; stale version stamp triggers self-repair on an
      already-logged-in Sprite
- [ ] CONTEXT.md Heartbeat entry rewritten; behavioral tests cover lease
      lifecycle and evidence predicate against the fake platform
