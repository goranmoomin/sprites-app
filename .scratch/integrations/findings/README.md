# Integrations wave - findings

One document per integration, plus the decisions they share.

| Document | Subject |
|---|---|
| `github.md` | Log in to GitHub |
| `tailscale.md` | Log in to Tailscale |
| `t3-connect.md` | T3 Connect, in two parts: the mechanism, then making it one-click |
| `prepopulate.md` | Prepopulating files and running commands |
| `cross-cutting.md` | Shared decisions, the new-integration checklist, and one dead end |

## Provenance

Started from the 2026-08-04 backlog exploration: code deep-dives at
`d820891`, plus a source sweep of the T3 Code clone at
`~/Developer/Personal/t3code`. Extended on 2026-08-11 with live probes on
four throwaway sprites driven through the authenticated `sprite` CLI, and on
2026-08-12 by completing real logins against the user's own GitHub, T3 and
Tailscale accounts, driving their browser.

Read the labels. CONFIRMED means it was executed against a real account.
INFERRED means it is reasoning that has not been run to ground. The
individual documents keep verbatim commands, output and exit codes so an
implementer does not have to re-run anything.

## Status at a glance

| Integration | Verdict |
|---|---|
| Log in to GitHub | Mint-once / plant-many CONFIRMED. One `gho_` token served two never-logged-in Sprites and the user's laptop at once, no rotation, no invalidation. The plant is two files, not an env block. The one-time mint cannot run unattended. |
| Log in to Tailscale | Mechanism CONFIRMED - one reusable key brought up two Sprites - but DELIBERATELY NOT USED. User decision: an ordinary per-Sprite interactive login, so the app holds no Tailscale credential. |
| T3 Connect | Credential COPYING REFUTED: the refresh token rotates, and replaying a stale copy appears to revoke the whole family. So there is no saved login and no plant - each Sprite authorizes for itself through the CLI's own headless login, at three to four interactions. A one-click app-driven design exists and was set aside. |
| Prepopulate files / run commands | Works, needs no credential, and is the only one whose status can be honestly re-observed. Two Flows, and probably not an Integration at all. |

The most consequential finding of the wave is the T3 rotation result,
because it invalidated the design the wave started with. The second is that
GitHub's mint cannot be automated end to end.

## The mechanism being generalized

Claude Code's one-click login, which all four were measured against: mint a
portable credential once through a headless PTY dialogue (`claude
setup-token`), parse it out of the PTY output, save it app-side in the
Keychain behind an explicit consent prompt, then plant it non-interactively
on any number of Sprites by merging it into `~/.claude/settings.json`'s env
block. Interactive once, a silent file write thereafter.

It is safe to fan out precisely because the token carries no refresh chain:
nothing rotates, so N holders never interfere. That clause turned out to be
the whole ballgame. GitHub's token shares it. T3's does not, and that is
what broke T3.

## Base image facts the four depend on

Ubuntu 26.04 LTS. PID 1 is tini, so there is no systemd and no service
manager: the only supervisor is the Sprites Services API.

- `gh` 2.79.0 ships at `/.sprite/bin/gh`. `node` 24.18.0. No `t3`, no
  `tailscale`.
- The `sprite` user has passwordless sudo, and also ambient
  `cap_net_admin`, `cap_sys_admin`, `cap_dac_override` and `cap_mknod`, with
  `/dev/net/tun` present - so `tailscaled` needs no root at all.
- `~/.gitconfig` ships `user.name=Sprite`, `user.email=noreply@sprites.dev`,
  `init.defaultBranch=main` and nothing else, so commits from a Sprite are
  authored by nobody.
- `BROWSER=/.sprite/bin/sprite-browser`. See the dead end in
  `cross-cutting.md`.
- Agent config dirs already exist: `~/.claude`, `~/.codex`, `~/.cursor`,
  `~/.gemini`, each with a copy of the platform's own `sprite` skill.
- `sha256sum` and `md5sum` are present, which is what makes the prepopulate
  status model cheap.
- A 200,001-byte file written through the app's own `writeFile` path
  arrived intact. `writeFile` creates mode 644 and takes no mode argument,
  so any secret plant needs an explicit `chmod 600`.

## What still needs verification

- T3 Connect, the probes listed at the end of `t3-connect.md`. The grant-cap
  question is the important one and it got more important once the
  app-driven design was set aside: the CLI login also produces one grant per
  Sprite, so if Clerk evicts older grants per user per client, older Sprites
  silently stop working - on the path we are actually shipping.
- Tailscale: the HTTPS-cert provisioning time T3 retries 5x1s for, blocked
  behind enabling Serve on the tailnet; the failure wordings for revoked,
  expired and exhausted keys; and the checkpoint stale-node hazard against
  `tailscaled --state=mem:`.
- GitHub: a real clone and push, to confirm commit-identity behaviour end to
  end. Everything else about GitHub is settled.

## Driving a browser from this machine, for future sessions

Recorded because working it out cost most of a session.

There is no Chrome here. The user's browser is Helium (`net.imput.helium`),
a Chromium fork, which cua-driver's typed `browser_*` tools refuse with
`pid <n> is not a recognized browser process`. It exposes CDP on
`127.0.0.1:9222` but serves no HTTP discovery: `/json/version` returns empty
and `/json/list` 404s.

What works: connect straight to `ws://127.0.0.1:9222/devtools/browser` with
`websocket-client`, then `Target.getTargets`, `Target.attachToTarget
{flatten: true}`, `Runtime.evaluate`. Every new WebSocket connection raises
Helium's native "allow remote debugging" sheet, which blocks the call until
answered.

That is why the `chrome-devtools` MCP server is unusable here: an MCP call
holds the agent's turn, so the agent cannot click the dialog the call is
waiting on, and it hangs for the full 30-minute idle timeout. Running the
CDP script as a background shell job leaves the agent free to click the
sheet with `cua-driver click`. That combination is reliable and is the
recommended shape.

Other hard-won details:

- Match CDP targets on a specific path, not a domain, or you attach to a
  stale tab.
- AX and pixel clicks do not reliably land on React pages. Use CDP, or the
  keyboard - PageDown scrolled where synthetic scroll events did nothing.
- React-controlled inputs need the native `HTMLInputElement.value` setter
  plus a dispatched `input` event; plain assignment is ignored.
- Google's account chooser ignores clicks on the inner text node and needs
  `div[data-identifier="<email>"]`.
- Tailscale's admin console redirects every `/admin/*` URL to an onboarding
  wall until a first device joins; the escape hatch is the "Already familiar
  with Tailscale? Skip this introduction" link.

## State left behind

Sprites, all left running: `probe-gh`, `probe-t3`, `probe-ts`,
`probe-integrations`, plus the pre-existing `mellowed-sky-5063`. Each
document's own "Sprite state" section has the detail.

- `probe-gh`: gh config removed entirely, `~/.gitconfig` back to base-image
  content. Clean.
- `probe-integrations`: gh config removed; carries a throwaway `~/AGENTS.md`,
  `/home/sprite/probe/big.txt`, two synthetic `/tmp/xdg-open.log` entries,
  and a tailscale install joined to the user's tailnet as an ephemeral node.
- `probe-t3`: t3 v0.0.33 with cloudflared installed; T3 logged out and the
  credential removed; nothing linked, so no server-side environment record.
- `probe-ts`: tailscale 1.102.2 with a `tailscaled` Sprites Service running;
  joined to the user's tailnet as an ephemeral node.

Accounts:

- The stray Tailscale tailnet `goranmoomin.github`, created by a GitHub SSO
  sign-in during the probe, was deleted at the user's request. Confirmed:
  `Your tailnet has been deleted.` Its warning is worth carrying into the
  design: signing in again with the same identity silently creates a NEW
  tailnet rather than reporting that none exists, so "does this user have a
  tailnet?" can never be answered by attempting a sign-in.
- The temporary Tailscale auth key was revoked; the console reports no valid
  auth keys and one recently invalidated. Revoking does not deauthenticate
  already-joined nodes, and the two Sprite nodes are ephemeral, so they
  self-remove once offline.
- GitHub OAuth grants created during the probes and still live:
  `T3 Code by Ping.gg` (read-only email and profile) and `Tailscale`
  (read-only org membership). Both revocable at
  github.com/settings/applications.
- The user's real GitHub token was planted on two Sprites for the
  portability test and removed afterwards, verified clean.
- Tailscale onboarding required a survey to proceed; it was answered
  "Personal or At-Home Use" with role "Engineer", changeable in the console.
