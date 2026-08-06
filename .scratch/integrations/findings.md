# Integrations wave — exploration findings

Evidence for the future integrations effort (T3 Connect, Tailscale, Log in
to GitHub) plus the cross-cutting vocabulary decisions they hang on. Split
from the 2026-08-04 backlog exploration: code deep-dives at `d820891`, live
probes via the authenticated `sprite` CLI against a throwaway sprite, docs
fetches, and a source sweep of the t3code clone at
`~/Developer/Personal/t3code`. UI-fix evidence moved to
`.scratch/ui-fixes/findings.md`; the Claude Code service/heartbeat effort has
its own spec and findings under `.scratch/claude-code-service/`.

## Probe results

| Probe | Result |
|---|---|
| `gh` in base image | **Yes** — `/.sprite/bin/gh`, v2.79.0 (2025-09-09). Base image also ships bun, deno, go, cargo, java, elixir, ruby toolchains. No install step needed. |
| Sudo / privileges | The `sprite` user has **passwordless sudo**. `/dev/net/tun` exists. |
| `tailscaled` on a sprite | **Works, kernel tun mode.** Official install script + sudo OK; a real `tailscale0` interface comes up (not just userspace); `tailscale up` prints `https://login.tailscale.com/a/<id>` then blocks until browser-side approval — the "open URL, then wait for the CLI" prompt shape. |
| Init system | PID 1 is **tini** (`/.pilot/tini -- tail -f /dev/null`) on Ubuntu 26.04 LTS — no systemd, no service manager. Exec'd processes appear with PPID 0 (injected by the platform's "pilot" agent). **The only supervisor on a sprite is the Sprites Services API.** Anything long-lived (tailscaled, `t3 serve`) must be a Sprites Service. |
| `t3 connect` semantics | **Exists in the pinned t3 0.0.31, sprite-side, cloudflared-based** (the mvp spec's "Cloudflare tunnel path" note was right). Root command = install relay client (`RelayClient.layerCloudflared`, prompts to download the `cloudflared` binary) + Clerk OAuth login + mark environment for linking; the tunnel launches when the server starts. Subcommands: `login`, `link` (with `--publish-only`), `publish` (push notifications + Live Activities to mobile clients), `status`, `unlink`, `logout`. Build-gated on baked-in relay/Clerk config — present in the npm 0.0.31 (verified live on a sprite). |
| `t3 connect login` headless | Clerk OAuth with loopback callback, or an out-of-band variant that prints a URL and takes a pasted authorization code (auto-selected inside SSH sessions) — the *existing* `.openURLAndEnterCode` prompt shape; no new FlowPrompt case needed for Connect. Needs one live PTY probe to confirm path selection under our exec. |
| T3 Tailscale integration (source) | Shells out to exactly two commands: `tailscale status --json` (reads `Self.DNSName` MagicDNS + CGNAT-filtered IPs) and `tailscale serve --bg --https=<port> http://127.0.0.1:<localPort>`. Enforced preconditions: tailscaled running, logged in, **MagicDNS enabled**, permission for `tailscale serve`, plain-HTTP local target; HTTPS certs provision lazily (5×1s probe retries). `t3 pair --tailscale`'s serve mapping persists; `t3 serve --tailscale-serve`'s is released on shutdown. |
| Version compatibility | **No client/server handshake** — advisory string equality against `serverVersion` from `/.well-known/t3/environment`, with a dismissible mismatch hint (web only; mobile has no skew UI). Pin `t3@<exact>` on the sprite. Node requirement `^22.16 \|\| ^23.11 \|\| >=24.10`; base image has 24.18.0. |

## What "T3 Connect" is

Account-authorized managed cloudflared tunnel for the T3 control plane.
Design consequences:

- It can **replace both the public-URL consent step and pairing creation**
  for users with T3 accounts — a privacy improvement per the URL-visibility
  rule in CONTEXT.md. Pairing stays as the account-less path. `Flow` has no
  conditionals, so this is a second flow (`t3-setup-connect` beside
  `t3-setup-pairing`) offered from the T3 integration, or a new capability +
  separate integration.
- `t3 connect status` ("persisted T3 Connect and relay client state") plus
  the CLI credential in `ServerSecretStore` give observation artifacts; find
  the on-disk paths for a cheap file probe.
- `unlink`/`logout` are the first revoke-shaped flows (see cross-cutting).
- Composes with Tailscale via `link --publish-only`: tunnel-free Connect
  (push notifications, Live Activities) + tailnet reachability is a
  legitimate third topology.

Open: live `t3 connect login` PTY probe; whether `link` requires a `t3
serve` restart under our supervised Service; cloudflared download size/time;
consent copy for routing through T3's relay.

## Log in to GitHub

`gh` ships in the base image — no install step. Shape: closest to Claude
Code (interactive login, no Service), but fits neither existing capability.
Status observation: prefer a hosts-file existence probe (ADR-0001-friendly)
plus `gh auth status` in the flow's verify step. Open: auth mode — device
flow (`gh auth login --web` prints a one-time code the user types *into* the
browser; needs an inverted prompt case) vs PAT over stdin (non-interactive
but miserable on a phone); scopes (`repo`, `read:org`, `workflow`); whether
`gh auth setup-git` is a required second step; checkpoint-restore semantics
for the stored token (restoring resurrects an old credential).

## Tailscale

Viable, kernel tun mode confirmed. `tailscaled` runs as a supervised Sprites
Service (no systemd — see init probe). Auth-key mode (`--authkey`) avoids
the new prompt case but needs a secret store the app doesn't have; ephemeral
keys would also solve stale-node-after-restore. The integration should
ensure MagicDNS and surface the `https://<magicdns>/` URL for the
`t3 serve --tailscale-serve` composition. Shipping Tailscale re-opens SSH
(the mvp spec excluded SSH *because* it needed an overlay network).

Open: node state across checkpoint restore (`/var/lib/tailscale` resurrects
an old node key), interactive-auth vs auth-key decision, whether the app
should verify the phone is on the same tailnet before calling the
integration ready, install latency (consider checkpointing after setup).

## What a new integration must implement (checklist)

- Conform to `Integration` — the 7 protocol requirements (id, displayName,
  provides, requires, recognizes, observeStatus, actions, flows).
- Register in `Integrations.all`; optionally add a playlist entry — two
  separate hand-maintained lists.
- Flows: one file per integration; non-interactive steps via the capturing
  exec helper; PTY steps copy the Claude login pattern (TERM unset/0×0 at
  start; Enter as a separate later keystroke).
- Verification doubled: the CLI's own status probe plus the artifact the
  detail screen observes.
- Tests against the fake platform copying the established suites
  (recognition, flow offering, login-flow scripting, setup idempotence,
  cold-deep-call tripwire), plus a `SPRITES_INTERACTIVE=1` live rig, plus
  findings entries here.
- Glossary entries in CONTEXT.md (mandatory per docs/agents/domain.md).

## Cross-cutting decisions this wave must open with

1. **Capability vocabulary.** `Capability` is a closed 2-case enum. GitHub
   login is neither coding agent nor control plane; Tailscale and T3 Connect
   both provide "private reachability". Each new case must read well in the
   blocked-playlist sentence and get a CONTEXT.md category entry. An
   integration with `provides: []` is legal but can never be a prerequisite.
2. **New `FlowPrompt` cases**: open-URL-and-wait (`tailscale up` — the step
   must keep draining the PTY while the prompt shows; no existing step does
   this); URL-plus-displayed-code (gh device flow — the inverse of
   `.openURLAndEnterCode`); secret entry (PAT / tailnet auth key). Each case
   ripples into the exhaustive prompt-view switch (core→UI, by design).
3. **`SpriteAction.Kind.copy(String)`** — tailnet address, connection
   string; deferred from the ui-fixes wave.
4. **`IntegrationStatus` structured details** — T3 smuggles a version into
   the summary string; Tailscale wants hostname/tailnet/IPs, gh the account
   login, Connect linked/relay state. Consider `details: [(label, value)]`.
5. **Observation cost**: integration statuses are awaited serially; 2 → 5+
   integrations makes a refresh a chain of sequential deep execs. Prefer
   file probes over exec probes; consider concurrency before the registry
   grows.
6. **Revoke-shaped flows**: all flows are additive today; `gh auth logout`,
   `tailscale logout`, `t3 connect unlink/logout` need a destructive-flow
   affordance that doesn't exist.
7. **Integrations recognizing platform tasks** the way they recognize
   Services (deferred future feature; the claude-code-service status
   endpoint is groundwork).
8. **Naming**: CONTEXT.md bans the word "connect" (platform Connectors
   collision — the Connectors API is real). "T3 Connect" is the product's
   proper noun and likely stays, with a glossary entry drawing the line;
   GitHub tickets say "Log in to GitHub".
