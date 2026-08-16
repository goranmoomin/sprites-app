# Sprites App

iOS app for provisioning disposable Fly Sprites as remote coding environments: log in coding agents, run supporting services (t3 serve, etc.), and hand off to client apps like T3 Code.

## Language

**Sprite token**:
The credential the user copies from the Fly dashboard after logging in through the in-app browser; the app detects the copied token and fills it in for confirmation. The app's unit of access: everything the app sees is scoped to a token. One token in the MVP; a revoked token returns the user to the login screen.
_Avoid_: Sprites token, organization, account, workspace, "connect" (collides with the platform's Connectors)

**Sprite**:
A persistent Linux sandbox managed through the Fly Sprites platform API. The root aggregate the app operates on.

**Agent**:
The credential plus installed binary that a coding-agent Integration manages on a Sprite. Sprite-scoped: "logged in" always means "on this Sprite".
_Avoid_: Provider, agent service

**Saved login**:
A credential the app keeps for an Integration whose credential does not rotate: obtained once during the login Flow (Claude Code and GitHub mint it on a Sprite; Tailscale takes a pasted auth key), then planted into later Sprites silently. App-scoped (the deliberate exception to Agent's Sprite-scoping), at most one per Integration; forgetting it removes it from the app only, revoking nothing and unplanting nothing. T3 Connect has none: its credential rotates on use, so each Sprite authorizes itself.
_Avoid_: Account, reuse Flow

**Service**:
A Sprite-managed supervised long-running process on a Sprite, with optional HTTP port (e.g. `t3 serve`, Claude Code remote control). Exactly the Sprites API concept.
_Avoid_: Daemon, process

**Exec session**:
A process the app runs on a Sprite, with platform-assigned identity that outlives any one connection. Dropping the connection neither pauses nor ends it: the app re-attaches by ID or kills it explicitly.

**Integration**:
First-party support for one capability of a third-party product on a Sprite. Declares its Category; observes its own status, recognizes Services as its instances by command match (whoever created them), offers Flows, and contributes Actions. One integration per capability, not per product: Claude Code (coding agent) and Claude Remote Control (control plane) are separate.
_Avoid_: Template, preset, service template

**Category**:
The Board row an Integration declares itself into: coding agent, control plane, or other. Grouping only; carries no requirement semantics.
_Avoid_: Capability, role

**Coding agent**:
Category of Integrations that manage an Agent's login (Claude Code, Codex, Gemini CLI).

**Control plane**:
Category of Integrations that run a Service exposing the Sprite to a client app (T3 Code, Claude Remote Control).

**Requirement**:
What a Flow needs on the Sprite before it runs: a set of Integrations, any one of which observed ready satisfies it; a Flow needs all of its Requirements. Names products, never categories: T3 Code's Flows require Claude Code or Codex, tailnet pairing requires Tailscale.
_Avoid_: Capability, dependency, prerequisite

**Flow**:
A guided, possibly interactive, multi-step operation an Integration offers on a Sprite (log in to Claude, set up t3 serve, pair with T3 Code). Steps prefer non-interactive exec; interactive steps drive a PTY headlessly behind native UI. A Flow is a flat list of steps with no branches: alternatives are peer Flows (T3 Code offers pairing over the public URL, pairing over the tailnet, and T3 Connect). Flows are always launched from the Board; the create-sprite wizard is only a name plus the Board.
_Avoid_: Wizard, onboarding, operation

**Board**:
Every Integration on a Sprite as one tile each, in Category rows, showing its observed status and launching its offered Flows (a chooser when there are several). The create-sprite wizard's second page and the detail screen's integrations section are the same Board; nothing about it is ordered or remembered.
_Avoid_: Playlist, checklist

**Action**:
A one-tap operation on the sprite detail screen (Open in T3 Code, Run command, SSH).

**Task**:
The platform's named, expiring keep-running record on a Sprite, shown as-is on the detail screen so cost is never mysterious. Keep-alive and Heartbeat are both Tasks.

**Keep-alive**:
The single named platform task our app holds on the user's behalf to keep a Sprite running. Not an abstraction: one Keep-alive is one task, its TTL set by the gesture (Wake to inspect holds 5 minutes, Keep active holds 1h, the platform max), extended or released explicitly from the detail screen. Waking is not a separate operation: the Wake gesture is taking this hold. A Flow step may hold its own short task for its duration; those are step-scoped, not this.
_Avoid_: Lease, lock

**Heartbeat**:
A short-expiry task an Integration keeps refreshed while its Agent is evidently working, released when the work stops. Installed by the Integration, not held by the user.

**Shallow observation**:
Reading control-plane metadata about a Sprite (name, status, URL). Never wakes it.

**Deep observation**:
Inspecting state inside a Sprite (agent logins, services, pairing). Counts as activity, so it is only done on a running Sprite; ambient refreshes never wake, only the explicit Wake gesture does.

**Custom service**:
A Service not recognized by any Integration. Gets generic controls only.

**URL visibility**:
A Sprite's URL auth setting (private / public), shown on the detail screen. Making a Sprite public is always an explicit consent step inside a Flow, never implicit.

**Pairing**:
T3 integration term only: the one-time credential created on the Sprite that the official T3 Code app uses to connect. Single-use and short-lived: opening the pairing URL redeems it. Observed from the Sprite; re-created via the "Pair again" Flow. T3 Connect mints one invisibly (2-minute TTL, never displayed) when the user taps Connect in the T3 Code app. Other integrations name their own equivalents when they arrive.

**T3 Connect**:
T3's account-authorized managed tunnel: the Sprite registers with T3's relay under the user's T3 account and appears in the T3 Code app's list under its Sprite name, reached by tapping Connect there. No public URL and no visible Pairing. Each Sprite logs in through the CLI itself; there is no Saved login. A proper noun: "connect" as a common noun stays avoided.
_Avoid_: Connect, cloud connect, relay

**Checkpoint**:
A deliberate snapshot of a Sprite's writable filesystem, restorable later on the same Sprite only. Restore is destructive and captures disk, not running processes. The platform also takes automatic checkpoints (restore-only, pruned by the platform); deleting a Sprite destroys all its checkpoints.
_Avoid_: Snapshot, backup
