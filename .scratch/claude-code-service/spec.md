# Claude Code Integration Service

Evidence: `findings.md` in this directory. Decisions grilled to shared
understanding 2026-08-04. Implementation ticket: `issues/01`.

## Problem Statement

When Claude Code works on something for more than about five minutes without
producing a hook event — a long build inside one tool call, a background
job, a subagent grinding through a big task — the Sprite pauses mid-work.
A warm pause drops the agent's open connections, so the prompt the user is
paying for dies quietly while they aren't looking. Background jobs are worse
than uncovered: the turn ending actively releases the wake-hold while the
job still runs. And because the heartbeat hooks are only installed during
login, no fix can reach Sprites that are already logged in.

## Solution

The Claude Code Integration installs its own resident Service on the Sprite:
a small supervised process that watches for evidence that the agent is
actually working — hook-reported activity, or a live claude process with a
recently written transcript — and holds the `claude-heartbeat` task up while
that evidence is fresh, in the platform's own recommended refresh pattern.
Hooks stop being the heartbeat and become simple activity reporters. The
Service is versioned and self-repairing, so future changes to hooks or
watcher logic reach existing Sprites automatically, and it exposes a status
endpoint the app reads as its deep observation of the integration.

## User Stories

1. As a Sprite user running a long prompt, I want the Sprite to stay awake
   through a single tool call that takes more than five minutes, so that a
   long build or test suite doesn't die mid-run.
2. As a Sprite user, I want background jobs started by the agent to keep
   the Sprite awake after the turn ends, so that fire-and-forget work
   actually finishes.
3. As a Sprite user, I want a subagent's long tool calls covered the same
   as the main conversation's, so that delegating work doesn't reintroduce
   the pause.
4. As a Sprite user with two concurrent agent sessions, I want one session
   finishing to leave the other's wake-hold intact, so that parallel work
   is safe.
5. As a Sprite user answering a permission prompt slowly, I want the Sprite
   still awake when I approve, so that a locked phone doesn't kill the
   turn.
6. As a Sprite user, I want the Sprite to stop being held awake within a
   bounded window after the agent goes idle, so that I don't pay for an
   abandoned session indefinitely.
7. As a Sprite user whose agent crashed without a Stop event, I want the
   hold to lapse on its own, so that a crash never bills me until I notice.
8. As a Sprite user, I want the heartbeat hold visible in the detail
   screen's Tasks section, so that I can see why the Sprite is awake.
9. As a Sprite user on the detail screen, I want the Claude Code
   Integration to show whether its service is healthy and whether the agent
   is currently active, so that "logged in" and "working right now" are
   distinguishable at a glance.
10. As a Sprite user who logged in long ago, I want heartbeat improvements
    to reach my existing Sprite without logging out and back in, so that
    fixes deploy themselves.
11. As a Sprite user with my own Claude Code hooks configured, I want the
    integration's hook install to merge with mine rather than overwrite
    them, so that my customizations survive.
12. As a Sprite user, I want a momentarily crashed or restarting watcher to
    never break the agent itself, so that heartbeat plumbing can fail
    without failing my work.
13. As a Sprite user restoring a checkpoint, I want the service to come
    back under supervision and resume watching, so that restores don't
    silently disable heartbeats.
14. As the app developer, I want the watcher's decision logic testable off
    the Sprite, so that heartbeat behavior is pinned by tests rather than
    by live reproduction.
15. As the app developer, I want a place for future sprite-side integration
    work (credential refresh and similar), so that the next resident
    feature doesn't need new infrastructure.

## Implementation Decisions

- **The Service is a single-file Bun script**, source embedded in this
  repo, written onto the Sprite by the Claude Code login Flow, and defined
  as a supervised Sprites Service — the platform supervisor is the only
  supervisor on a Sprite (PID 1 is tini; no systemd). No binary
  distribution: the base image ships Bun and Node, so there is no download,
  hosting, architecture, or release-pipeline concern. Promoting to a
  distributed binary later changes only the install step.
- **Transport is HTTP over a Unix domain socket** (the platform's own
  in-sprite idiom). The service unlinks a stale socket file on boot. Chosen
  over a spool file for the reply channel (future hooks can ask, not just
  tell) and the status endpoint.
- **Hooks become dumb reporters.** Prompt-submit and post-tool-use pipe
  their stdin JSON to the socket; Stop reports session end. Every hook
  command carries a short timeout and never propagates failure — a hook
  must never block or fail the agent, and a down service must never break
  Claude. Hook install merges with existing user hooks.
- **The service owns the heartbeat**: it maintains per-session leases from
  hook events and refreshes the singleton `claude-heartbeat` task (5-minute
  expiry, roughly 60-second cadence — the platform's documented pattern;
  the ceiling is a hard hour) while evidence of live agent work exists:
  a fresh session lease, or a claude process alive with a recently written
  transcript. The second clause covers everything hooks cannot see — long
  tool calls, subagents, background jobs, lost deliveries. Session end
  retires that session's lease rather than deleting the task; when evidence
  lapses the service stops refreshing and the task expires naturally. The
  transcript-recency threshold bounds how long an idle interactive session
  can hold the Sprite.
- **The task name stays a singleton.** Multi-session accounting lives in
  the leases; the Tasks UI shows one comprehensible hold.
- **Version-stamped self-repair.** The install step records a content
  stamp; the integration's observation compares it and re-runs the install
  when stale — the deployment path to already-logged-in Sprites and to
  every future revision.
- **Status endpoint as deep observation.** The service reports hooks
  version, active sessions, whether the hold is currently held, and last
  event over the socket; the integration recognizes the Service and reads
  this endpoint (via exec) as its deep observation. Groundwork for the
  deferred integrations-wave feature of recognizing platform tasks.
- **Glossary**: the Heartbeat entry in the domain glossary is rewritten —
  an agent-evidence-driven refresher owned by the integration's Service,
  released by evidence lapse rather than by a Stop hook.

## Testing Decisions

Good tests here assert externally observable behavior: which files and
hooks the install step produces, which platform task exists after a given
event history, what the status endpoint reports — never the watcher's
internal bookkeeping.

- **Swift side, at the existing platform seam** (the fake platform): the
  login Flow's install step (script written, Service defined, hooks merged
  not clobbered, stamp recorded), the integration's observation (Service
  recognized; status endpoint read via scripted exec; stale stamp triggers
  re-install), all in the style of the existing login-flow and setup-flow
  behavioral suites. The cold-deep-call tripwire applies unchanged.
- **Service logic, at one new seam**: the script is structured as a pure
  decision core (lease lifecycle, evidence predicate, refresh/expire
  decisions as data in, decisions out) with a thin IO shell, and the core
  is tested with Bun's test runner in-repo. This is the only new seam the
  feature introduces; the shell stays too thin to need tests.
- **Live acceptance, at the existing interactive-rig seam**
  (`SPRITES_INTERACTIVE=1`): the probes that prove the design — a >5-minute
  background job and a >5-minute single tool call keep the Sprite running;
  turn-end no longer releases the hold under a live background job; idle
  lets the hold lapse within the bounded window. The spec is not
  sign-off-able from unit tests alone.

## Out of Scope

- The binary distribution pipeline (revisit when the script outgrows Bun).
- Credential/auth maintenance itself — a separate upcoming effort; this
  Service is its future home, not its implementation.
- Integrations recognizing platform tasks (integrations wave; the status
  endpoint is deliberate groundwork).
- Codex / Gemini coverage — the evidence predicate generalizes, but only
  Claude Code is in scope.
- Any change to the manual Keep-alive or the unified app hold task (ticket
  02 of the ui-fixes effort owns those).

## Further Notes

- Platform facts this design rests on (probed live, recorded in
  findings.md): CPU activity never prevents pausing; warm pauses drop open
  TCP connections; the task-expiry ceiling is a hard 3600 seconds; the
  platform's own documented long-running pattern is a 5m-expiry/60s-refresh
  periodic refresher; the Tasks API is in-sprite HTTP over a management
  socket.
- Outstanding verification (non-blocking; sizes the margin): subagent hook
  semantics on the pinned claude version, hook and transcript behavior
  under T3-driven turns. The status endpoint should make both observable.
- The alternatives considered (TTL-bump stopgap, hook-spawned detached
  refresher) and the reasons they lost are recorded in findings.md.
