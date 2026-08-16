# Log in to GitHub

Evidence from live probes on the throwaway sprite `probe-gh` (Ubuntu 26.04
base image, `gh` 2.79.0 at `/.sprite/bin/gh`, 2026-08-11), then completed
against the user's real GitHub account on 2026-08-12. Output is verbatim.
Non-ASCII in gh's output is written as `<U+xxxx>`: gh prints `<U+2713>` for
success lines and a plain ASCII `X` for failures.

## Verdict

Mint-once / plant-many CONFIRMED. The credential is an OAuth user-to-server
token for the GitHub CLI OAuth app (`client_id=178c6fc778ccc68e1d6a`),
issued by the device flow. It does not rotate, it is not machine-bound, and
one login fans out to any number of Sprites - exactly the property that
makes the Claude setup token safe to reuse.

Simpler than the Claude equivalent in two ways:

- Minting needs no interaction. `gh auth login --web` is fully
  non-interactive: no Ink repaint parsing, no Enter-as-a-separate-keystroke
  trick. It still runs in a PTY (see "The mint") because only TTY sessions
  survive the Safari hop, so the reattach-by-identity dance stays.
- Capturing the credential is a command, not a screen-scrape: `gh auth
  token` prints it on stdout, exit 0.

Harder in one way, and different in one:

- The plant is two files, both load-bearing, and there is no
  `settings.json`-style env block to merge into.
- `gh auth status` is not presence-only. It round-trips the API, so
  verification is free and needs no consent gate. That breaks the assumption
  behind CONTEXT.md's Verification entry, which is written as though probing
  always costs something.

The one thing that does not work: the mint cannot be completed unattended.
See "Why the mint needs a human".

## The mint

The command (run in a PTY with `GH_PROMPT_DISABLED=1 NO_COLOR=1
TERM=xterm-256color`; the plain non-TTY output below is identical apart from
CRLF, and was the form first observed):

```
gh auth login --hostname github.com --git-protocol https --web
```

Everything it prints goes to stderr; stdout is empty. `cat -v` shows no
escape sequences at all:

```

! First copy your one-time code: 4261-1EFE
Open this URL to continue in your web browser: https://github.com/login/device
```

Note the leading blank line. `gh auth login`, `gh auth login --web` and the
fully-specified form behave identically under a non-TTY exec, so `--web` is
not required - but passing it pins the intent.

Parsing:

- The code is `XXXX-XXXX`, uppercase, hyphen in the middle. Observed
  samples: `E6AB-AB38`, `BACC-88BF`, `4261-1EFE`, `5EA4-A004`, `B6F3-066B`,
  `647E-AC6D`, `CE2F-D23B`, `A11C-416F`, `B441-7FA1`. The alphabet is
  GitHub's and undocumented; anchor on the literal `one-time code: ` and
  take the rest of the line rather than constraining the character set.
- The URL is always the constant `https://github.com/login/device`. It
  carries no code and no state, so it could be hard-coded, though parsing it
  anchored on `Open this URL` is safer.

Device-flow parameters, read off the wire with `GH_DEBUG=api`:

```
POST https://github.com/login/device/code
  client_id=178c6fc778ccc68e1d6a&scope=repo+read%3Aorg+gist
  -> device_code=... expires_in=899 interval=5 user_code=647E-AC6D
     verification_uri=https%3A%2F%2Fgithub.com%2Flogin%2Fdevice
POST https://github.com/login/oauth/access_token   (every 5s)
```

So the default scopes are `repo`, `read:org`, `gist`. `--scopes` is
additive, not replacing:

```
$ gh auth login ... --scopes workflow,read:user
client_id=178c6fc778ccc68e1d6a&scope=repo+read%3Aorg+gist+workflow+read%3Auser
```

Recommended ask: the default three plus `workflow`, and nothing more.
Without `workflow`, pushing any commit that touches `.github/workflows/` is
rejected by the server, which is a confusing failure to debug from a phone.

Timing and abort. The process blocks silently for up to `expires_in=899`
seconds, printing nothing while it polls. Measured end to end: a login
started at 11:32:0x UTC gave up at 11:47:1x UTC with

```
failed to authenticate via web browser: context deadline exceeded
```

on stderr, exit 1, having written nothing at all - verified from a clean
state, and again twice on 2026-08-12 by letting real codes expire.
`~/.config/gh` does not even get created. That message is a clean anchor for
"the user never finished", and it means a flow can simply wait for the exec
to exit rather than run its own timer.

The mint nevertheless has to run in a PTY, because only TTY exec sessions
survive a WebSocket drop (probed 2026-08-16 on `probe-ghlogin`: the same
`sh` loop under a non-TTY exec died at the drop and vanished from
`GET /exec`; under `tty=true` it kept running and stayed listed
`is_active`). The device flow always spans the Safari hop, iOS suspends
the app and kills the socket, and a non-TTY `gh auth login` was observed
killed mid-poll with `~/.config/gh` never created; the reattach by ID
then 404s. That is the failure the first implementation shipped with.

Under a PTY, gh first asks

```
? Authenticate Git with your GitHub credentials? (Y/n)
```

from a prompter that queries the terminal and will not accept input until
something answers. `GH_PROMPT_DISABLED=1` removes the prompt, but gh still
probes the terminal before printing anything: `ESC]11;?ESC\` (OSC 11
background colour) followed by `ESC[6n` (cursor position), and it blocks
until both are answered. Without `TERM` it repeats the probe in a tight
loop (364 KB/s observed); with `TERM=xterm-256color`, 40x120, it sends the
probe once or twice and waits. Answering as a terminal would
(`ESC]11;rgb:0000/0000/0000ESC\` and `ESC[1;1R`) gets it past the probe:
it then prints the same two lines as the non-TTY path, CRLF-terminated,
and polls as before. `NO_COLOR=1` strips the ANSI colouring from those
lines so the same anchors parse. Verified live: after the probe was
answered and the socket aborted, the gh session stayed listed and alive,
and attaching to it by ID succeeded.

## Why the mint needs a human

Two blockers, both found by driving the real browser, and both invisible to
a probe that never completes an authorization.

1. The Authorize button is disabled until the consent page is scrolled to
   its bottom. Not a timer, not focus, not hydration - all three were tested
   and ruled out. On an account with many organizations the page is several
   screens tall, so anything driving it headlessly hits a permanently dead
   button with no explanation. Keyboard PageDown scrolled it; synthetic
   scroll events did not land at all. Verified twice, on this flow and again
   on Tailscale's GitHub sign-in, so it is a property of GitHub's OAuth
   consent page generally rather than of the device flow.
2. GitHub then enters sudo mode and demands a second factor: passkey,
   GitHub Mobile, authenticator app, or password. This fires even when the
   requested scopes are unchanged from what the account has already granted -
   verified by running a device flow with no `--scopes` at all, which still
   hit it.

Consequence for the design: the login Flow cannot be completed unattended,
even on a machine with a live GitHub session. The plant is unaffected and
stays fully silent. The flow's copy should tell the user to expect a
second-factor prompt, because otherwise the failure looks like a bug.

## The credential and the plant

Two files, both under `$HOME`, both load-bearing.

`~/.config/gh/config.yml`, minimum content:

```yaml
version: "1"
```

This is mandatory, and its absence is the single easiest way to get a plant
wrong. Without it gh treats the config as pre-multi-account and attempts a
migration on every single invocation, which needs either the keyring the
image does not have or a live API call, and hard fails:

```
failed to migrate config: cowardly refusing to continue with multi account
migration: couldn't find oauth token for "github.com": exec: "dbus-launch":
executable file not found in $PATH
```

`~/.config/gh/hosts.yml`, the shape verified end to end:

```yaml
github.com:
    users:
        <login>:
            oauth_token: <token>
    git_protocol: https
    user: <login>
    oauth_token: <token>
```

Which keys are load-bearing, established by subtraction:

- Top-level `oauth_token` is the one gh actually reads. Without it (users
  map only, `config.yml` present), `gh auth token` says `no oauth token
  found for github.com`, exit 1, and status reports `X Failed to log in to
  github.com account <login> (default)`.
- `user` names the account in status and is what `--user` matches.
- The `users:` map is what `gh auth logout` and `gh auth switch` enumerate.
  Without it, `gh auth logout --hostname github.com --user <login>` fails
  with `not logged in to github.com account <login>`, exit 1 - so a
  hand-planted file must include it or gh's own logout cannot undo our
  plant.
- `git_protocol` is cosmetic for our purposes.

Modes matter, and gh will not help. It creates these files 600, but never
repairs a mode it did not choose: after `chmod 644 hosts.yml` followed by a
gh-driven rewrite, the file was still `-rw-r--r--`. Since the app's
`writeFile` is `sh -c 'mkdir -p <dir> && cat > <path>'`
(`Sources/SpritesCore/Platform/HTTPSpritesPlatform.swift:315`) and creates
at the default umask, a plant lands 644 and stays world-readable for the
life of the Sprite. The plant needs an explicit `chmod 600`.

Order matters too. Two `writeFile` calls are more in the existing idiom than
one heredoc exec, but they are not atomic together, and a half-plant
(`hosts.yml` without `config.yml`) is exactly the hard-failure case above.
Write `config.yml` first.

There is no keyring on this image - no `/run/dbus`, no `dbus-daemon`, no
`DBUS_SESSION_BUS_ADDRESS`, no `secret-tool`, `gnome-keyring-daemon` or
`pass`, no `~/.local/share/keyrings`. So gh's "stored securely in the system
credential store" wording does not apply and `--insecure-storage` is a no-op
in effect. If a future base image gains a keyring, gh may prefer it and the
file plant becomes ambiguous; pin that with a live test.

## Environment variables are a hazard, not a mechanism

`GH_TOKEN` beats `GITHUB_TOKEN` beats `hosts.yml`, and an env token
completely masks the file account in status, which reports the source in
parentheses: `(GH_TOKEN)` rather than the file path. An empty `GH_TOKEN=` is
ignored and the file is used. `GH_ENTERPRISE_TOKEN` applies only to GitHub
Enterprise Server hosts.

But there is nowhere to put one. The app execs argv directly, `~/.bashrc` is
not read by non-interactive shells (Ubuntu's stock early return),
`~/.profile` is read by `bash -lc` but not by `bash -c` or direct exec, and
a Sprites Service gets the same bare platform env - verified live with a
throwaway service, which saw only `BROWSER`, `DEBIAN_FRONTEND`, `HOME`,
`LANG`, `PATH`, `PWD` and `SHLVL`.

So: write the files, and treat a stray `GH_TOKEN` as something to detect
rather than something to use. It silently overrides our plant, and since
`gh auth status` names its source in parentheses, that parenthesis is worth
parsing and surfacing as "this Sprite is using a token from GH_TOKEN, not
the one we planted".

## git integration

`gh auth setup-git` is a mandatory second step, and is separately plantable
as plain text. git never reads `GH_TOKEN` itself: with
`GIT_CONFIG_GLOBAL=/dev/null` and `GH_TOKEN` set, `git credential fill`
still fails with `fatal: could not read Username for
'https://github.com': terminal prompts disabled`, exit 128.

What it writes into `~/.gitconfig`, verbatim, tabs as gh emits them:

```
[credential "https://github.com"]
	helper = 
	helper = !/.sprite/bin/gh auth git-credential
[credential "https://gist.github.com"]
	helper = 
	helper = !/.sprite/bin/gh auth git-credential
```

The empty `helper = ` line is deliberate: it resets any inherited helper
list before appending gh's. The path is the absolute resolved `gh`, so an
image that moves the binary breaks a stale plant.

Behaviour worth knowing: it is presence-only and exits 0 even against an
invalid token; it is idempotent (a second run leaves two helper lines, not
four); `--force --hostname github.com` writes the block with no
`~/.config/gh` present at all, so it can be planted before, during or after
the login in any order; and `gh auth logout` does not remove it.

## Commit identity

The base image ships `~/.gitconfig` with `user.name=Sprite`,
`user.email=noreply@sprites.dev`, `init.defaultBranch=main` and nothing else
- verified against an untouched sprite. Commits pushed from a Sprite are
therefore attributed to an address that links to nobody and does not count
as the user's.

The login flow is the only moment the app knows who the user is. `gh api
user` returns `login`, `name` and `id`, and GitHub's
`<id>+<login>@users.noreply.github.com` form is derivable from those two
without any extra scope. Whether to write it is a design decision, not a
technical obstacle - the cost is that the app would be writing to a file the
base image owns.

## Observation and verification

Unlike Claude, the honest probe is free, so there is no reason to hide it
behind a consent gate.

| Command | Logged out | Planted but invalid | Notes |
|---|---|---|---|
| `gh auth status` | `You are not logged into any GitHub hosts...`, exit 1 | the `X Failed to log in ...` block plus `The token in <path> is invalid.`, exit 1 | Round-trips the API. Names its source in parentheses. No JSON mode: `--json` is `unknown flag`. |
| `gh auth token` | `no oauth token found for github.com`, exit 1 | prints the token, exit 0 | Presence-only, no network. Also the mint-capture command. |
| `gh api user` | `To get started with GitHub CLI, please run: gh auth login`, exit 4 | `gh: Bad credentials (HTTP 401)` plus the JSON body, exit 1 | Exit 4 is gh's documented "requires authentication" code. Add `--jq .login` for the account name. |

The cheap artifact probe is a `readFile` of `~/.config/gh/hosts.yml` plus a
content test for `oauth_token:`. Existence alone is wrong, because logout
leaves the file behind as the three bytes `{}`. That probe is presence-only
and cannot see a `GH_TOKEN` planted by someone else.

Recommended split, mirroring `ClaudeCodeIntegration`: `observeStatus` reads
`hosts.yml` and looks for `oauth_token:`, optionally pulling `user:` out for
the status line without any exec; the flow's verify step runs `gh api user
--jq .login`, falling back to reporting `gh auth status` verbatim, because
its wording already says what is wrong and which source it came from.

## Logout and revoke

```
$ gh auth logout --hostname github.com --user <login>
<U+2713> Logged out of github.com account <login>
EXIT:0
```

Non-interactive with `--hostname`; `--user` is optional with a single
account and required to disambiguate more than one. It rewrites `hosts.yml`
to `{}` and leaves both `config.yml` and the gitconfig helper alone. Already
logged out gives `not logged in to any hosts`, exit 1.

It does not revoke server-side, and gh's own help says so, spelling out the
manual procedure and warning that it "will revoke all authentication tokens
ever generated by the GitHub CLI across all your devices". That sentence is
worth quoting in the logout consent copy: it is the same
unplanting-is-not-revoking property the Claude logout flow has, with the
same one-big-hammer alternative.

The app can equally write `{}` itself, which is the exact inverse of the
plant and avoids depending on gh's CLI surface. Prefer that for symmetry
with `ClaudeLogoutStep`, and consider also removing the `[credential ...]`
blocks.

## Checkpoint hazard

`hosts.yml` is in the writable filesystem, so a Checkpoint captures the
token in plaintext and a restore resurrects it. Three consequences:

1. A restore can log a Sprite back in to an account the user has since
   logged out of, or with a token since revoked. The file probe reports
   "logged in" for both.
2. It is cheaply detectable, because `gh auth status` validates online.
   Unlike the Claude case there is no choice between a cheap lie and an
   expensive truth - the truth is free. Run the honest probe after a
   restore, or whenever the status screen opens for a Sprite whose last
   known event was a restore.
3. A restored token is a real credential sitting in plaintext inside a
   snapshot the user may not think of as containing secrets. Worth a line in
   the checkpoint copy, and an argument for the logout flow zeroing the file
   rather than merely deactivating.

There is nothing to sweep from `/tmp/xdg-open.log`: with prompts disabled
(and under a non-TTY exec) the login never invokes `sprite-browser` at all.
Only the interactive TTY path does, after an Enter press, and even then the
URL it logs is the bare `https://github.com/login/device` with no code in it.

## CONFIRMED against a real login (2026-08-12)

Run with the `gho_` token the user's local `gh` already held (account
`goranmoomin`, scopes `gist`, `read:org`, `repo`) - the same credential
class the device flow mints. It was piped over stdin, never placed in argv,
and removed from both Sprites afterwards, verified clean.

| Check | Result |
|---|---|
| Env-var plant under direct exec | Works. `Logged in to github.com account goranmoomin (GH_TOKEN)`; `gh api user --jq .login` returned `goranmoomin`. So `GH_TOKEN` is visible to a `gh` run under `sprite exec` when set in the same command - the problem is only that there is nowhere persistent to put it. |
| File plant, sprite 1 | Works. Status names `/home/sprite/.config/gh/hosts.yml` as the source; real API round-trip returned `goranmoomin`. |
| File plant, sprite 2, never logged in | Works from a cold start with no `~/.config/gh` at all. This is the plant-many claim, and it holds. |
| Concurrent validity | After sprite 2 used the token, sprite 1 still returned `goranmoomin`, and so did the user's laptop. No rotation, no single-holder semantics. |
| `git credential fill` without `setup-git` | `fatal: could not read Username for 'https://github.com': No such device or address`. Confirms setup-git is mandatory and that a planted token alone does not enable git. |
| `gh auth setup-git --hostname github.com` | Exit 0, writes the two `[credential ...]` blocks; afterwards `git credential fill` returns `username=goranmoomin` plus the password. |
| `gh auth logout --hostname github.com` | Exit 0, non-interactive, `Logged out of github.com account goranmoomin`. Local only: sprite 1 and the laptop both still worked afterwards. |
| What logout leaves | `hosts.yml` becomes exactly `{}`, confirmed with `cat -A`. This is why the file-existence probe is wrong. |
| Commit identity after setup-git | Still `user.name = Sprite`, `user.email = noreply@sprites.dev`. |

## What the app builds

1. A new `FlowPrompt` case: open this URL and type THIS code into it, with
   the code prominent and copyable. It is the inverse of
   `.openURLAndEnterCode`, and the copy affordance is the whole user
   experience, because typing `4261-1EFE` on a phone into Safari is the
   thing the user actually does. The step keeps running while the prompt
   shows, and may fail on the 15-minute deadline underneath it.
2. A saved-login store. The Claude store is a single-slot Keychain item
   holding `{token, mintedAt}`. GitHub wants `{token, login, scopes,
   mintedAt}`: the login name is needed to write `hosts.yml` correctly and
   to show "logged in as X" without an exec. That argues for generalising
   `ClaudeLoginStore` into a per-integration saved-login store rather than
   adding a second bespoke one. Note the token is only ever recoverable via
   `gh auth token`, so the app must run it immediately after a successful
   mint or lose the chance.
3. A plant that writes `config.yml` first, then `hosts.yml`, then chmods
   both to 600.
4. A killable login. The mint blocks for up to 899 seconds, which is longer
   than any Keep-alive the app takes by default, so the login step should
   hold its own task the way `claudeCodeLoginFlow` does, sweep stale
   sessions matched on the `gh auth login` command suffix the way
   `ClaudeLoginStep.runDialogue` does, and be killable by session id.
5. `GH_NO_UPDATE_NOTIFIER=1` on every exec. gh's update notifier prints to
   stderr once every 24 hours and would pollute parsed output. No
   `state.yml` appeared during any probe, so no notice ever fired - that is
   luck, not design.

## Open questions

1. Capability. GitHub login is neither coding agent nor control plane. It is
   closest to "an account the tools on this Sprite can act as". With no
   capability it can never be a prerequisite, but a coding agent that cannot
   push is half a product, so a `sourceControl` capability that the T3 and
   Claude playlists optionally require is worth considering.
2. Whether the login flow should fix commit identity, given it means writing
   to a base-image-owned file.
3. Whether to strip the gitconfig helper blocks on logout, or leave them.
   Leaving them is harmless: with no token the helper returns nothing and
   git falls through to prompting, which then fails with the message above.
4. Verification being free here makes the two coding-agent-shaped
   integrations behave differently - Claude gates verification behind
   consent, GitHub would not. That should be a deliberate call rather than
   drift.
5. A real clone and push, to confirm commit-identity behaviour and the
   `workflow` scope end to end. This is the only GitHub question left that
   needs a live account; everything else is settled.

## Smaller gotchas worth pinning

- `GH_CONFIG_DIR` relocates the entire config tree. It is not set on the
  image today, but if it ever were, the plant would land in the wrong place
  and the file probe would read the wrong file. Worth a defensive read.
- All login output is on stderr and none on stdout. A parser reading only
  stdout sees nothing.
- `gh auth login` with no flags at all, under a non-TTY exec, silently
  becomes the device flow - convenient, but it means a mis-specified command
  still starts a 15-minute polling process.
- `--clipboard` warns about missing `xsel`/`xclip`/`wl-clipboard` and
  continues. Never pass it on a Sprite.
- `gh auth login --with-token` validates against the API before writing, so
  it is not a silent plant path: it rejects a fake with `error validating
  token: HTTP 401` and writes nothing. It is a reasonable path for a
  user-supplied PAT, and the only one that would still work if a keyring
  appeared, but it is strictly worse than writing the files when the token
  is already known good.
- `gh` is 2.79.0, baked root-owned at `/.sprite/bin/gh` (55 MB, dated Jul
  30), and is not upgradable by the `sprite` user without installing a
  second copy.

## Implemented (integrations ticket 06, 2026-08-16)

`GitHubIntegration` plus `GitHubLoginFlow`, shaped as recommended above:
device flow behind the new `.openURLAndShowCode` prompt (first shipped as
a non-TTY exec, which died with the socket during the Safari hop; moved to
a PTY with the terminal probe answered by the step, see "The mint"), own
`github-login` keep-alive task, stale sessions swept by the argv suffix,
capture through `gh auth token` plus `gh api user`, save-with-consent as
`SavedGitHubLogin`, plant as `config.yml` then `hosts.yml` then `chmod 600`
then `setup-git`, identity set only while the base image's noreply address
is in place, verify through `gh api user --jq .login` with no consent gate
and a fall-through to a fresh mint on `Bad credentials`. Observation is the
`oauth_token:` line in `hosts.yml` (a bare `{}` is logged out) with the
account as a detail; scopes are not on the Sprite and are not shown.

Live rig: `InteractiveGitHubTests`, which also records the still-unpinned
`config.yml`-without-`hosts.yml` behaviour and the real `gh auth status`.
No logout Flow, per the 2026-08-16 decision.
