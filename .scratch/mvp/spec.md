# Sprites App MVP

Status: ready-for-agent

## Problem Statement

I want to vibecode from my iPhone. The T3 Code iOS app is a good client, but it needs a server (`t3 serve`) running somewhere with coding agents already authenticated — and standing that up today means a laptop, a CLI, and a pile of manual steps. Fly Sprites gives me disposable, pausing, cost-effective Linux sandboxes with everything needed (exec, services, checkpoints, wake-on-request URLs), but there is no mobile way to provision one, log agents into it, run the control plane, and hand off to T3 Code. I also don't want a sprite silently burning money, and I don't want an agent's long-running prompt to die just because my phone locked.

## Solution

A native iOS app that turns Sprites into disposable coding environments in a few taps: log in by pasting a Sprite token (created in the Fly dashboard via an in-app browser), see your sprites, create one with a suggested name, run guided Flows to log in Claude Code and set up `t3 serve`, consent to making the sprite URL public, pair the official T3 Code app via a one-time Pairing credential, and start coding. The sprite detail screen observes reality (never caches lies): agent login state, recognized services, live tasks, checkpoints, URL visibility. A manual Keep-alive holds the sprite awake when needed; Claude Code's Heartbeat hooks hold it automatically while a prompt is running. Delete is one honest, destructive tap.

All vocabulary in this spec follows `CONTEXT.md`. ADRs 0001 (observed state only) and 0002 (headless PTY, no terminal emulator) are binding.

## User Stories

1. As a mobile developer, I want to tap "Log in" and get an in-app browser to the Fly dashboard, so that I can create a Sprite token without leaving the app.
2. As a mobile developer, I want the app to detect a copied token when I return from the browser and offer one-tap "Use copied token", so that login is nearly frictionless.
3. As a mobile developer, I want to paste a Sprite token manually as a fallback, so that I can log in even if clipboard detection fails.
4. As a mobile developer, I want the token validated immediately (a cheap list call), so that a bad paste fails at login rather than later.
5. As a mobile developer, I want my token stored in the iOS Keychain, so that it survives app restarts securely.
6. As a mobile developer, I want to be returned to the login screen when my token is revoked or invalid, so that the app never half-works with dead credentials.
7. As a mobile developer, I want to see a list of my sprites with name and platform status (cold/warm/running), so that I know what exists and what is costing compute.
8. As a mobile developer, I want the sprite list to use only shallow observation, so that opening the app never wakes a sprite.
9. As a mobile developer, I want a Create sprite button that suggests a haikunator-style name (adjective-noun-token), so that I don't have to invent unique names.
10. As a mobile developer, I want to edit or replace the suggested name before creation, so that I can name sprites meaningfully.
11. As a mobile developer, I want creation to be a name plus a skippable playlist of ordinary Flows (agent logins, then control-plane setup), so that I can bail at any step and still have a usable sprite.
12. As a mobile developer, I want an interrupted create playlist to be harmless, so that the detail screen simply shows which Flows are still available — no draft state, no cleanup.
13. As a mobile developer, I want a sprite detail screen with Status, URL visibility, Integrations (with per-integration status lines like "Claude Code: logged in", "T3 Code: service running"), Services, Tasks, and Checkpoints, so that one screen tells me everything real about the sprite.
14. As a mobile developer, I want deep observation to run only when the sprite is already running, so that viewing a cold sprite's details never wakes it.
15. As a mobile developer, I want a "Wake to inspect" affordance on a cold sprite's detail screen, so that waking is always my explicit choice.
16. As a mobile developer, I want to run the Claude Code login Flow, so that I can authenticate my Claude subscription on the sprite with native UI (open-URL button, code paste field), never a terminal.
17. As a mobile developer, I want the Claude Code login Flow to install the Heartbeat hooks as part of setup, so that future prompts automatically hold the sprite awake.
18. As a mobile developer, I want a failed interactive Flow step to show the raw CLI output as text, so that I can see what went wrong and retry.
19. As a mobile developer, I want the T3 Code setup Flow to install T3 once (resolving the then-current release) and create the `t3 serve` service running that installed binary, so that the control plane boots deterministically and survives cold wakes.
20. As a mobile developer, I want the T3 setup Flow to ask my consent before making the sprite URL public, so that internet exposure is never silent.
21. As a mobile developer, I want the T3 setup Flow to end with a Pairing screen (hostname, one-time code, QR, copy buttons, "Open T3 Code"), so that connecting the official T3 Code app takes seconds.
22. As a mobile developer, I want a "Pair again" Flow on the detail screen, so that I can recover after a restore or an expired pairing.
23. As a mobile developer, I want an "Open in T3 Code" Action to appear whenever a service recognized by the T3 integration exists, so that the handoff works regardless of who created the service.
24. As a mobile developer, I want service recognition by command match, so that multiple instances (e.g. future per-directory services) and hand-made equivalents are classified correctly.
25. As a mobile developer, I want a general "create service" Flow (name, executable, arguments as an array, working directory, environment, optional HTTP port), so that I can run my own daemons.
26. As a mobile developer, I want to start, stop, and restart services and view their recent logs, so that I can operate the sprite without a laptop.
27. As a mobile developer, I want Custom services to get generic controls only, so that the UI never pretends to understand a service it doesn't recognize.
28. As a mobile developer, I want a manual Keep-alive action ("keep active", extend, release) shown as the named platform task it is, so that I can hold the sprite awake honestly and see the cost.
29. As a mobile developer, I want the Tasks section to list all live platform tasks (including the agent's Heartbeat task), so that I always know why a sprite is awake.
30. As a mobile developer, I want to create a Checkpoint with a comment from the detail screen, so that I can save a known-good environment before risky work.
31. As a mobile developer, I want to list checkpoints and restore one, with a warning that restore is destructive and rolls back agent logins, services, and Pairing made after it, so that time travel is informed.
32. As a mobile developer, I want the detail screen after a restore to simply re-observe and show what's true now, so that recovery is just running the available Flows again.
33. As a mobile developer, I want to delete a sprite with a single destructive confirmation, so that disposal is fast but never accidental.
34. As a mobile developer, I want an optional one-shot exec action (run a command, see captured output as text), so that I can poke at the sprite without any terminal emulator.
35. As a mobile developer, I want API failures and wake latency surfaced as clear inline states (retry affordances, "waking..." indicators), so that the platform's pause/wake model never looks like a bug.

## Implementation Decisions

- Greenfield native iOS app, SwiftUI. No backend of our own: the app talks directly to the Sprites platform API with the user's Sprite token. Provider and platform credentials never transit any server we run.
- Single seam: one protocol representing the entire Sprites platform boundary — sprite CRUD and metadata, URL settings, exec (framed non-TTY and TTY sessions over WebSocket), services (definitions, lifecycle, logs), checkpoints (create/list/restore with NDJSON progress), and the in-sprite Tasks API reached via exec (`sprite-env curl`). Two implementations: real (URLSession HTTP + WebSocket) and an in-memory fake for tests.
- Identity is the Sprite token; there is no organization concept in the app. One token in the MVP. Revocation returns to login. The word "connect" is banned (platform Connectors collision).
- Integration architecture per CONTEXT.md: integrations are per role (Claude Code is a coding-agent integration; T3 Code is a control-plane integration), each contributing observed status, a command-match recognizer, Flows, and Actions. Cross-integration dependency is declared (T3 requires at least one coding-agent integration logged in). MVP ships exactly two integrations plus the general service Flow.
- Observed state only (ADR 0001): shallow observation (control-plane metadata) always; deep observation (exec/fs/services/tasks) only on running sprites or explicit wake. No durable app-side sprite state; no cache in the MVP.
- Flows (ADR 0002): steps declare non-interactive (`tty: false`, framed streams, preferred) or interactive (`tty: true`, headlessly driven PTY behind native step UI). No terminal emulator view exists. Flow failure shows raw output as text.
- Claude Code integration: login via the interactive OAuth/setup-token dialogue; installs Heartbeat hooks (prompt/tool events refresh a short-expiry named task, stop events delete it) into user-level Claude settings during setup. Hooks also cover T3-driven Claude turns. No T3 fork, ever, for this purpose.
- T3 Code integration: installs T3 once at Flow time (resolving latest at that moment) under a fixed runtime directory and runs the installed binary as the service — never `npx` in the service command, so cold-start boots are deterministic and offline-safe. The installed version is observable; upgrading is an explicit future "Update T3" action, not automatic. The Flow defines the `t3 serve` service with host 0.0.0.0 and its HTTP port, requires explicit consent to set URL visibility to public, creates Pairing via the CLI's JSON output (non-interactive), renders code + QR + copy + app handoff. "Pair again" is a standalone Flow. Recognizer matches the `t3 serve` command shape, not service names.
- Keep-alive: a named platform task owned by the app (max 1h per platform rules), created/extended/released via exec against the management socket. No auto-lease at T3 handoff. The Tasks list is displayed with platform naming intact.
- Sprite naming: reimplement flyctl's haikunator (same word lists, adjective-noun-token).
- Creation is non-transactional: `POST /sprites`, then a skippable playlist of ordinary Flows. Every Flow is also launchable from the detail screen; the detail screen is the recovery UI.
- Deletion calls the platform delete; one destructive confirmation (concise copy); no archive/soft-delete/export.
- Checkpoint restore gets no special-case logic: post-restore correctness comes entirely from re-observation.
- Login UX: SFSafariViewController to the Fly dashboard token page, clipboard-offer on return (system paste prompt), manual paste fallback, immediate validation, Keychain storage.

## Testing Decisions

- Tests exercise external behavior through app-level use cases against the in-memory fake platform — never implementation details. A good test reads like a user story: "given a running sprite with a service whose command is `t3 serve ...`, the detail model exposes an Open in T3 Code action."
- The fake platform simulates: sprite lifecycle states (cold/warm/running) with wake-on-deep-touch, a service registry, a task registry with expiry against an injected clock, checkpoint create/restore, and scripted exec dialogues (canned CLI transcripts for `claude` login including a reworded-prompt variant, `t3 auth pairing create --json`, `command -v` probes, `sprite-env curl` task calls).
- Key behavioral suites: token login/validation/revocation; shallow vs deep observation (the fake asserts whether it was woken — ADR 0001 compliance is a test, not a convention); command-match recognition including multiple instances and near-misses; Flow execution happy paths and derailment (raw-output failure surface); Keep-alive create/extend/release/expiry; T3 setup end-to-end including the public-consent gate and pairing parse; create-playlist interruption leaving a consistent observable sprite; delete; restore followed by re-observation.
- Framework: Swift Testing. No UI tests in the MVP; view models are thin over observed models and are covered by the use-case tests. No prior art — this repo is greenfield; these tests are the prior art.

## Out of Scope

- Credential portability between sprites (checkpoint-as-template is not supported by the platform; fs-copy approaches deferred).
- Claude Remote Control integration (needs Keep-alive-while-in-use and cannot be woken remotely; future service onboarding Flow with directory picker).
- Multiple Sprite tokens, token naming, multi-account UI.
- SSH access of any kind (no sshd in base image; external terminal apps cannot speak the WSS proxy; would require an overlay network).
- Terminal emulator UI; terminal libraries are permitted later only as headless screen buffers (ADR 0002).
- LLM-driven adaptive login flows.
- Quick actions (one-click repository clone etc.), file browser, filesystem watch, TCP port forwarding UI.
- t3 connect (Cloudflare tunnel path), platform Connectors, network/privilege/resource policies.
- Live Activity for Keep-alive, "last seen" caching for cold sprites, background refresh.
- Automatic Heartbeat coverage for non-Claude agents (Codex/Gemini prompts rely on manual Keep-alive in the MVP).

## Further Notes

- Empirical checks to perform early in implementation (documented behavior, not yet verified end-to-end): T3 WebSocket traffic through the public sprite URL, exec `tty: true` byte-level behavior for Claude's Ink UI, whether services API calls wake a cold sprite (assumed yes, treated as deep observation), pairing creation while the service is running, and hooks firing when T3 drives the `claude` CLI.
- Platform doc quality caveats from research: HTTP exec response framing is underdocumented; the filesystem-watch page contains copied exec text; service upsert may stream rather than return JSON. None block the MVP as scoped, but the seam's real implementation should be written against observed behavior, not just the docs.
- Server/client version skew is possible in both directions (a sprite's installed T3 aging behind the auto-updating App Store client, or a fresh install ahead of a stale client); surface pairing/connection failures clearly and lean on the future "Update T3" action rather than automatic upgrades.
