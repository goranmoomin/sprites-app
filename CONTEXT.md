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
The one Claude Code credential the app keeps: minted once on a Sprite during the login Flow, then planted into later Sprites to log their Agent in without a browser. App-scoped (the deliberate exception to Agent's Sprite-scoping); forgetting it removes it from the app only, revoking nothing and unplanting nothing.
_Avoid_: Account, reuse Flow

**Service**:
A Sprite-managed supervised long-running process on a Sprite, with optional HTTP port (e.g. `t3 serve`, Claude Code remote control). Exactly the Sprites API concept.
_Avoid_: Daemon, process

**Exec session**:
A process the app runs on a Sprite, with platform-assigned identity that outlives any one connection. Dropping the connection neither pauses nor ends it: the app re-attaches by ID or kills it explicitly.

**Integration**:
First-party support for one capability of a third-party product on a Sprite. Declares the Capabilities it provides and requires; observes its own status, recognizes Services as its instances by command match (whoever created them), offers Flows, and contributes Actions. One integration per capability, not per product: Claude Code (coding agent) and Claude Remote Control (control plane) are separate.
_Avoid_: Template, preset, service template

**Capability**:
What an Integration provides to or requires from a Sprite; a closed set (coding agent, control plane). A requirement is met when some integration providing that capability is observed ready.
_Avoid_: Role

**Coding agent**:
Integration category that manages an Agent's login (Claude Code, Codex, Gemini CLI). Capability-derived: an integration is a coding agent because it provides the coding-agent capability.

**Control plane**:
Integration category that runs a Service exposing the Sprite to a client app (T3 Code, Claude Remote Control). Capability-derived: provides the control-plane capability, and may require the coding-agent one.

**Flow**:
A guided, possibly interactive, multi-step operation an Integration offers on a Sprite (log in to Claude, set up t3 serve, pair with T3 Code). Steps prefer non-interactive exec; interactive steps drive a PTY headlessly behind native UI. Flows are always launchable from the detail screen; the create-sprite wizard is only a name plus a skippable playlist of ordinary Flows.
_Avoid_: Wizard, onboarding, operation

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
T3 integration term only: the one-time credential created on the Sprite that the official T3 Code app uses to connect. Single-use and short-lived: opening the pairing URL redeems it. Observed from the Sprite; re-created via the "Pair again" Flow. Other integrations name their own equivalents when they arrive.

**Checkpoint**:
A deliberate snapshot of a Sprite's writable filesystem, restorable later on the same Sprite only. Restore is destructive and captures disk, not running processes. The platform also takes automatic checkpoints (restore-only, pruned by the platform); deleting a Sprite destroys all its checkpoints.
_Avoid_: Snapshot, backup
