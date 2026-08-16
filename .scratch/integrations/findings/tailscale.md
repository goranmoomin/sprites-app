# Log in to Tailscale

Evidence from live probes on `probe-ts` (Ubuntu 26.04 base image, tailscale
1.102.2, 2026-08-11), then completed against the user's real tailnet on
2026-08-12. Output is verbatim.

## Verdict, and the decision that overrides it

Two separate things, and the second is what to build.

The mechanism works. One reusable auth key brought up two never-touched
Sprites non-interactively, both live in the user's tailnet at the same time.
Mint-once / plant-many is CONFIRMED for Tailscale, and on paper it is the
best-fitting of the four integrations - an OAuth client secret would mint a
fresh tag-owned ephemeral key per Sprite, so fan-out is by design rather
than by luck.

It is not what we are building. User decision, 2026-08-12: "I just want the
user to feel like they are just logging in via Tailscale in a normal
sprite." No saved credential, no pasted secret, no OAuth client. Every
Sprite logs in interactively as its own node.

That decision is cheap to honour because the interactive path turned out to
be far better than expected: `tailscale up --json` returns the login URL
immediately and `tailscale status --json` keeps serving it, so the app never
holds a PTY or a socket. It costs one thing, described under "State and
checkpoints".

What the decision removes from the wave: the secret-entry `FlowPrompt` case
(nothing is ever pasted), any app-side Tailscale credential and its storage
and revocation questions, the `--advertise-tags` requirement, and any need
to touch the user's ACL.

## The shipping flow

1. Install the pinned static tarball into `~/.local/bin`.
2. Create `tailscaled` as a Sprites Service.
3. `tailscale up --json --timeout=1s`, parse `AuthURL` from stdout.
4. Show an open-URL prompt; the user approves in a browser.
5. Poll `tailscale status --json` until `BackendState` is `Running`.
6. Report `Self.DNSName` and `TailscaleIPs`.

Steps 3-5 are the whole interactive design, and none of them needs a
terminal.

## Install

Use the pinned static tarball, not the official script.

| Path | Time | Cost |
|---|---|---|
| Static tarball to `~/.local/bin` | ~1.05s in-sprite, 38.7 MB | No sudo, nothing outside `~/.local/bin` |
| `curl -fsSL https://tailscale.com/install.sh \| sudo sh` | ~9.3s in-sprite | Needs sudo; writes `/usr/bin/tailscale`, `/usr/sbin/tailscaled`, `/etc/default/tailscaled`, three unit files under `/lib/systemd/system/`, an apt keyring and `/etc/apt/sources.list.d/tailscale.list`, and runs a full `apt-get update` |

Worth correcting a prior assumption: the script does not try and fail on
systemd. It does not try. `grep -i "systemd\|systemctl\|invoke-rc\|deb-systemd\|not been booted"`
over the install output returns no matches; the unit files land on disk and
the postinst silently no-ops. It also does not start tailscaled - the final
line is literally `Installation complete! Log in to start using Tailscale by
running: tailscale up`.

Version pinning resolves from `https://pkgs.tailscale.com/stable/?mode=json`,
which returns `TarballsVersion` plus per-arch filenames. It returned
`1.102.2`; the amd64 tarball is 38,674,341 bytes.

## The Service

No root, no sudo, no systemd, no flags. The `sprite` user carries ambient
`cap_net_admin`, `cap_sys_admin`, `cap_dac_override` and `cap_mknod`, and
`/dev/net/tun` is present, so a bare `tailscaled` as uid 1001 comes up in
real kernel tun mode - `"TUN": true`, `tailscale0` UP, no userspace-networking
fallback. `cap_dac_override` also lets it create `/var/lib/tailscale` and
`/var/run/tailscale` itself.

The definition:

```
cmd = /home/sprite/.local/bin/tailscaled
args = []
dir  = /home/sprite
```

Using the default socket path is load-bearing, because the T3 integration
shells out to a plain `tailscale status --json` with no `--socket`.

Supervisor behaviour, measured: comes up `running` and stays up; `kill -9`
returns it in under 4s with `restart_count: 1` and a new pid; `stop` sends
SIGTERM and shuts down cleanly. Cold start to socket ready is under 1s
(`got LocalBackend in 22ms`, engine up ~300ms after exec).

Footprint, logged out with a live tun: RSS 37-38 MB, VSZ 1.3 GB (Go's usual
reservation, not resident), 0.1-0.7% CPU idle. Fine for a sprite, but it is
permanently resident alongside `t3 serve`, so it should not be on the
default playlist for sprites that do not need it.

## The interactive login

The naive shape, for reference - `tailscale up` in a `--tty` exec, `cat -v`,
no ANSI and nothing Ink-like:

```
To authenticate, visit:

	https://login.tailscale.com/a/155406430136d9

timeout waiting for Tailscale service to enter a Running state; check health with "tailscale status"
```

Do not parse that. Use `--json`:

```
$ tailscale up --json --timeout=1s
{
	"AuthURL": "https://login.tailscale.com/a/353384b0103a5",
	"QR": "data:image/png;base64,iVBORw0KGgoA...",
	"BackendState": "NeedsLogin"
}
```

with `timeout waiting for Tailscale service to enter a Running state` on
stderr and exit 1. That exit 1 is the expected, successful outcome of the
step, not a failure. The JSON is emitted immediately, before the block -
verified by racing a `tailscale status --json` against it at t+3s and
finding the same URL already registered.

The URL is then pollable, which is the design win. After a `--timeout=1s`
run returned, `tailscale debug prefs` showed `"WantRunning": true` and
`"LoggedOut": false`, the daemon log showed it still working the pending
registration, and:

```
$ tailscale status --json | grep -E '"(BackendState|AuthURL)"'
  "BackendState": "NeedsLogin",
  "AuthURL": "https://login.tailscale.com/a/29242720178d0",
```

So the step is: one plain capturing exec (~1.0s) to get the URL, a prompt
that shows it and returns, and a background poll for `BackendState ==
"Running"`. No PTY, no held socket, no reattach logic. A short keep-alive
task is still wanted so the sprite does not decay to cold during the browser
hop, the same as `loginKeepAliveTaskName`.

Confirmed against the real account: the approval page reads "You are about
to connect the device `probe-ts`", so `--hostname=<name>` carries the Sprite
name through with no work on our part. The page also offers a tailnet
selector and a `Join a tailnet` list of the user's GitHub organizations.

Three traps, all observed live:

- `tailscale up` is a complete-set-of-flags command. Omitting a
  previously-set flag errors instead of logging in:

```
Error: changing settings via 'tailscale up' requires mentioning all
non-default flags. To proceed, either re-run your command with --reset or
use the command below to explicitly mention the current value of
all non-default settings:

	tailscale up --json --timeout=1s --ssh
```

  A stray earlier `--ssh` poisoned later runs during the probe, and it will
  bite the app the same way: a second run of the Flow, or a run after the
  user did anything by hand, silently becomes an error instead of a login.
  The integration must pass a fixed complete flag set every time, or always
  pass `--reset`. `--auth-key`, `--force-reauth` and `--qr` are exempt.
- A second `tailscale up` while a login is pending does not re-emit
  `AuthURL` on stdout. Only `status --json` does. Another reason the poll is
  the primary channel and `up`'s stdout is only the bootstrap.
- `tailscale up` does not use the `sprite-browser` channel at all. Confirmed
  in a `--tty` exec with `BROWSER` set: `/tmp/xdg-open.log` was never
  created. See the dead end in `cross-cutting.md`.

`tailscale login` is a separate alpha subcommand with the same flags and no
reason to prefer it. `--json` also hands back a `data:image/png;base64,...`
QR of the login URL for free - useless on the phone driving the flow,
possibly nice for "approve from your laptop". Ignore for now.

`--json` is documented as "output in JSON format (WARNING: format subject to
change)", and `AuthURL` in `status --json` is not documented as a stable
contract either. Both want a pinning test that fails loudly.

## Observation

`tailscale status --json` logged out, verbatim and complete - the whole
document, it is small:

```json
{
  "Version": "1.102.2-t6cac91817-g6ff0ddc72",
  "TUN": true,
  "BackendState": "NeedsLogin",
  "AuthURL": "",
  "TailscaleIPs": null,
  "Self": {
    "ID": "", "NodeID": 0,
    "PublicKey": "nodekey:0000...0000",
    "HostName": "probe-ts", "DNSName": "", "OS": "linux", "UserID": 0,
    "TailscaleIPs": null, "Addrs": [], "Online": false, "Active": false,
    "InNetworkMap": false, "InMagicSock": false, "InEngine": false
  },
  "Health": [ "Tailscale is stopped." ],
  "MagicDNSSuffix": "",
  "CurrentTailnet": null,
  "CertDomains": null,
  "Peer": null,
  "User": null,
  "ClientVersion": null
}
```

Logged in, confirmed live:

```
BackendState= Running
DNSName= probe-ts.tailcc654.ts.net.
IPs= ['100.90.6.35', 'fd7a:115c:a1e0::be36:624']
Tailnet= goranmoomin@gmail.com MagicDNS= True
```

Note the trailing dot on `DNSName` - strip it before building a URL.

`BackendState` values worth handling: `NoState`, `NeedsLogin`,
`NeedsMachineAuth` (the device-approval case), `Stopped`, `Starting`,
`Running`.

Exit codes, all measured:

| Command | Condition | Exit |
|---|---|---|
| `tailscale status --json` | daemon up, logged out | 0 |
| `tailscale status` | daemon up, logged out | 1, prints `Logged out.` |
| `tailscale status --json` | daemon down | 1, `Failed to connect to local Tailscale daemon` |
| `tailscale serve ...` | logged out | 1, prints `Logged out.` |
| `tailscale down` / `logout` / `dns status` | logged out | 0 |

So parse the JSON, never test the exit code - the same rule already noted on
`ClaudeCodeIntegration.observeStatus`, for a different reason.

The cheapest file probe for "logged in": read
`/var/lib/tailscale/tailscaled.state` and look for `_current-profile`. It is
mode 0600 owned by `sprite`, so `platform.readFile` reaches it. It goes
stale relative to the daemon (the file can say logged in while the Service
is stopped), so combine it with the Service state the app already has from
`services(on:)` - no extra call at all in the common case.

What the detail screen should show, as `IntegrationStatus` details:

- MagicDNS name: `Self.DNSName`, trailing dot stripped
- Tailnet: `CurrentTailnet.Name`
- Addresses: `TailscaleIPs`, CGNAT-filtered (100.64.0.0/10), exactly what T3
  does
- Service state, from the Service

The MagicDNS name is what `SpriteAction.Kind.copy(String)` is for.

## State and checkpoints - the cost of the decision

Paths, all defaults, all created by a non-root tailscaled:

- `/var/lib/tailscale/tailscaled.state` - 119 bytes when logged out,
  containing only `_machinekey`. When logged in it gains `_current-profile`,
  `_profiles` and a `profile-<id>` entry.
- `/var/lib/tailscale/tailscaled.log*` - logtail state.
- `/var/lib/tailscale/ssh/` - host keys, created eagerly even with SSH off,
  so its presence is not evidence SSH is on (read `tailscale debug prefs` ->
  `RunSSH` instead).
- `/var/run/tailscale/tailscaled.sock` - `/var/run` is a symlink to `/run`,
  which is tmpfs.

`/` is an overlay with `upperdir=/mnt/user-data/root-upper/upper`, so
`/var/lib/tailscale` is on the captured writable layer while `/run` is not.
The machine key was verified byte-identical across a Service restart.

So a Checkpoint taken after login captures a node key, and restoring it
resurrects a node the control plane may have expired, removed, or that is
still live elsewhere - a duplicate or conflicting node.

This is precisely what the decision costs. Ephemeral auth keys would have
solved it for free, because ephemeral nodes self-remove 30-60 minutes after
going offline. Interactive logins are not ephemeral. Remaining remedies:

1. `tailscaled --state=mem:` - "use 'mem:' to not store state and register
   as an ephemeral node". Tested live: the daemon starts clean and writes no
   state file. Nothing on disk for a Checkpoint to capture and nothing to go
   stale. But every restart is a re-registration, which with an interactive
   login means re-authenticating after every supervisor restart. That is
   unacceptable on this path, so `--state=mem:` is effectively unavailable
   to us now.
2. A post-restore repair Flow: `tailscale logout` then log in again. The
   same shape as `ClaudeCodeIntegration.logoutFlow`, which exists for
   exactly this reason.
3. `tailscale up --force-reauth`, which re-authenticates without changing
   other settings and is exempt from the complete-set-of-flags rule.
   Adequate when the node still exists but its key expired.

Guidance on checkpointing: do not checkpoint after Tailscale setup. The
whole install is about a second, so there is nothing to save, and the
Checkpoint actively creates the stale-node problem. If anything, checkpoint
before login.

`tailscaled --cleanup` exists and exits 0; it tears down interface and
firewall state but does not remove the state file.

## MagicDNS and `tailscale serve`

Preconditions for the T3 composition, confirmed:

- tailscaled running, or every call exits 1 with `failed to connect to local
  tailscaled`.
- Logged in: `tailscale serve` logged out prints exactly `Logged out.`,
  exit 1.
- MagicDNS enabled, and HTTPS certificates enabled, both tailnet-wide
  settings at `https://login.tailscale.com/admin/dns`.
- A plain-HTTP local target, with certs provisioning lazily - the T3 source
  already encodes both, with 5x1s probe retries.

Detecting MagicDNS-disabled: `status --json` ->
`CurrentTailnet.MagicDNSEnabled`. `CurrentTailnet` is `null` while logged
out, so the check is `logged in && CurrentTailnet?.MagicDNSEnabled == true`.
`tailscale dns status --json` is too thin to use (`{"TailscaleDNS": true}`).

And a fourth precondition, found late and not in T3's list at all. Serve is
off by default per tailnet:

```
$ tailscale serve --bg --https=443 http://127.0.0.1:3773

Serve is not enabled on your tailnet.
To enable, visit:

         https://login.tailscale.com/f/serve?node=nVHfATME8G11CNTRL
```

`tailscale serve status` then reports `No serve config`. Without a bounding
`timeout` the command hangs rather than failing fast, so any step running it
must bound it. It was not enabled on a real, long-standing personal tailnet,
so "most users will already have it on" is not a safe assumption. It was not
enabled during the probe, since it is a tailnet-wide capability toggle and
the user's call - which also means the HTTPS-cert provisioning time T3
retries for is still unmeasured.

`tailscale serve status --json` returns `{}` with exit 0 when nothing is
configured, including while logged out - a safe, cheap read.

The resulting user-visible URL is `https://<hostname>.<tailnet>.ts.net/`,
built from `Self.DNSName` with the trailing dot stripped. That is the
privacy win over a public sprite URL: on a tailnet-reachable sprite, the T3
setup Flow's `PublicURLConsentStep` becomes unnecessary.

Note that MagicDNS, HTTPS certificates and Serve enablement are all the same
shape - an external precondition the user fixes in a web console, which the
app has no Flow vocabulary for. See `cross-cutting.md` item 9.

## Logout and revoke

Both fully non-interactive, no prompt, no TTY, exit 0 even with nothing to
do:

- `tailscale down` sets `WantRunning=false`, keeps the node registered and
  the credentials on disk, and is reversible with `tailscale up` without
  re-auth. This is pause, not logout.
- `tailscale logout` clears the profile. Observed live: it wipes the pending
  `AuthURL` (a subsequent `up` produced a brand new URL) and leaves the state
  file at 119 bytes containing only `_machinekey`. It does not delete the
  machine key, so the sprite keeps a stable machine identity across
  logout/login.

What lingers: the node row. A non-ephemeral node stays listed at
`/admin/machines` until an admin removes it, with its key expired.

So the destructive-flow affordance needs three rungs here, and the copy has
to be honest about each:

1. Stop the Service. Nothing removed; the sprite is simply off the tailnet.
2. `tailscale logout`. Credentials gone from this Sprite; the node row may
   linger in the admin console.
3. Remove the node in the admin console. The app cannot do this, and cannot
   revoke anything - say so.

## SSH, and why it stays out

`tailscale set --ssh` (preferable to `up --ssh`, which is subject to the
complete-set-of-flags rule) turns the sprite into a Tailscale SSH server.
For a default tailnet the stock ACL already permits it - `"action":
"check"`, `src: autogroup:member`, `dst: autogroup:self` - so no ACL edit is
needed unless the user has customised their policy. Note `autogroup:self`
does not cover tag-owned devices, so any future move to `--advertise-tags`
would need an explicit rule naming the tag.

The MVP spec excluded SSH precisely because it needed an overlay network,
and shipping Tailscale removes that blocker. It should still stay out of
this wave: an SSH Action needs a terminal, and ADR-0002 says we ship no
terminal emulator. The honest framing is that Tailscale makes SSH possible
from other devices on the tailnet, and the app's contribution is at most a
`copy` action for `ssh sprite@<magicdns-name>`. Do not enable `--ssh` by
default; it is a listening service the user did not ask for.

## Evidence that fan-out works, kept for the record

Not the shipping design, but it was proven against the real account, and it
is what makes the interactive choice a preference rather than a necessity.
If the decision is ever revisited, this is the starting point.

An auth key is generated at `/admin/settings/keys` via `Generate auth key`,
whose controls are exactly `Description`, `Reusable`, `Expiration`,
`Ephemeral`, `Tags`. With Reusable and Ephemeral on and Tags off - verified
as `[true, true, false]` before submitting - the result is a
`tskey-auth-...` string, 62 characters.

Sprite 1, tailscaled already running as a Service:

```
tailscale up --auth-key=file:$HOME/.config-tskey --hostname=probe-ts --timeout=60s
```

Exit 0, no output, no prompt. Sprite 2, which had never seen Tailscale, from
a cold start in one command - detect arch, resolve the pinned version, fetch
the tarball, run `tailscaled` with plain `nohup` as the ordinary user, then
`up` with the same key:

```
arch=amd64 version=1.102.2
tarball bytes: 38674341
UP_EXIT=0
BackendState= Running
DNSName= probe-integrations.tailcc654.ts.net.
IPs= ['100.89.85.103', 'fd7a:115c:a1e0::1336:5569']
```

Both live simultaneously, each seeing the other in `tailscale status`.

Two credential shapes exist, and the OAuth client is the better one:
reusable auth keys cap at 90 days, while an OAuth client secret
(`tskey-client-...`) has no such clock - `tailscale up` detects the prefix
and exchanges it at `https://api.tailscale.com/api/v2/tailnet/-/keys` for a
freshly minted, tag-owned, ephemeral key per node. Confirmed live by the
error path: a bogus secret produced `Post ".../keys": oauth2: cannot fetch
token: 401 Unauthorized`, and without tags it produced `oauth authkeys
require --advertise-tags`, exit 1. That tag requirement is what would force
ACL edits, and is the reason the OAuth path was not exercised on a tailnet
holding the user's real devices.

Neither credential is CLI-mintable; both come from the admin console. That
is why this path would have needed a secret-entry prompt rather than the
existing open-URL one.

`--auth-key=file:` is the right form regardless of path: argv leaks to
`ps aux` and to the exec-session list the app itself reads and displays.

## Open questions

1. Capability vocabulary. Tailscale provides "private reachability", which
   the closed 2-case `Capability` enum cannot express. Does T3 then require
   it, or is it optional-and-preferred? The latter has no vocabulary at all,
   and `Flow` has no conditionals, so "T3 over tailnet" is probably a
   separate Flow (`t3-setup-tailscale`) beside `t3-setup-pairing` - the same
   conclusion T3 Connect reached.
2. Does the `t3` Service want `needs: ["tailscaled"]`? It would guarantee
   ordering, but it couples two integrations' Services, and
   `T3CodeIntegration.recognizes` matches on command shape precisely to
   avoid caring who created what.
3. Where does the canonical `tailscale up` flag list live, given the
   complete-set-of-flags rule, and what happens when the user has run
   `tailscale set` by hand? `--reset` is the blunt answer but it silently
   discards their configuration.
4. Running a Sprite's login is not free of side effects on a shared
   resource: a node appears in the user's tailnet. "Deep observation never
   changes anything" still holds, but "run the Flow again" is no longer
   free, which is a new property none of the other integrations have.
5. Still unmeasured, all needing the user's account: the HTTPS-cert
   provisioning time behind enabling Serve; the verbatim failure wordings
   for revoked, expired and exhausted keys; and the checkpoint stale-node
   hazard in practice.

## Implemented (integrations ticket 07, 2026-08-16)

Decision reversed from the 2026-08-12 one above (grilled 2026-08-16): the
interactive per-Sprite login is not built. `TailscaleIntegration` plus
`TailscaleLoginFlow` join with a reusable, non-ephemeral auth key pasted
once through the existing `.openURLAndEnterCode` prompt on the admin keys
page, saved with consent as `SavedTailscaleLogin`, and planted on every
Sprite with `tailscale up --json --auth-key=file:<600 file, removed after>
--hostname=<sprite> --timeout=60s`: the same complete flag set every run,
never `--reset`; the complete-set-of-flags error surfaces verbatim
(anchored on "requires mentioning all", which the CLI wraps across two
lines). Install is the pinned static tarball into `~/.local/bin` resolved
from the stable JSON index at flow time; `tailscaled` is a Service with no
args and the default socket. Observation costs no exec until the Service
runs, then one `status --json`, parsed never by exit code, with MagicDNS
name, tailnet, CGNAT addresses and Service state as details.

Any `up` failure other than the flag-set error or a daemon that is not
answering reads as a rejected key: a saved one is forgotten and re-pasted.
The exact expired/revoked wording is still unmeasured; the live rig
`InteractiveTailscaleTests` records it when run with
`SPRITES_LIVE_TAILSCALE_BADKEY=1`. Ephemeral keys are wrong for Sprites
that go cold; the OAuth client (`tskey-client-`, `?ephemeral=false`) is the
recorded upgrade and is not built.
