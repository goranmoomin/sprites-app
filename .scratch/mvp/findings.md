# Empirical findings against a real Sprite (apptest-probe, since destroyed)

Verified with the `sprite` CLI and `sprite api` on 2026-07-31.

## Verified

- Sprite metadata: `GET /v1/sprites` returns org name, warm/cold/running counts and limits, and per-sprite `status` (observed `warm` shortly after create), `url`, `url_settings` (`auth: sprite|public`, `private_access`), `created_at`, `last_running_at`, `last_warming_at`. Shallow observation has everything the list and detail header need.
- URL visibility: private URL answers `302` (auth redirect), not 401. After `sprite url update --auth public`, the URL serves the sprite's HTTP service directly.
- Base image: `claude`, `codex`, `gemini` preinstalled under the sprite user's local bin; `cursor`/`opencode`/`grok`/`t3` absent; Node v24.18.0; user is `sprite`. No `sshd`, `openssh-server` not installed — SSH assumptions confirmed.
- Tasks API: in-sprite only via the management socket; `sprite-env curl` works. `POST /v1/tasks` (`name`, `expire`), `GET /v1/tasks`, `DELETE /v1/tasks/{name}` all behave as documented; task shape is `{name, started_at, expires_at}`.
- Claude interactive login: `claude setup-token` without a TTY produces no output (hangs); under a PTY it emits spinner ANSI, then "Browser didn't open? Use the url below to sign in (c to copy)" with the OAuth URL in an OSC-8 hyperlink. Headless PTY driving (ADR 0002) is viable; the URL is extractable by pattern match.
- Codex has non-interactive login paths: `codex login --with-api-key` and `--with-access-token` read from stdin. A future Codex integration may need no PTY at all.
- npm package is literally `t3` (bin `t3`; probed v0.0.31). `t3 serve` flags confirmed: `--host`, `--port`, `--base-dir`, `--no-browser`, `--auto-bootstrap-project-from-cwd`, `--mode web|desktop`. Note: the help says serve "prints headless pairing details" — pairing may be obtainable from serve output/logs, possibly simpler than a separate pairing command.
- Services API: `PUT /v1/sprites/{name}/services/{svc}` accepts `{cmd, args, http_port}` and streams NDJSON (`started` ... `complete` with log file paths). `GET .../services` returns `cmd`, `args`, `needs`, `http_port`, and `state {status, pid, started_at}` — command-match recognition is fully supported by the API shape. `DELETE .../services/{svc}` exists and works even though it is undocumented.
- Service logs land in a per-service log file surfaced by the create response.
- Destroy: permanently removes filesystem, services, checkpoints, and the URL (confirmed by CLI warning and by deletion).

## Verified in second probe (apptest-probe2, since destroyed)

- T3 on a Sprite requires a native-module build step: `node-pty` (and `msgpackr-extract`) ship no linux prebuilds, and npm blocks their install scripts by default (`allowScripts`). Without `npm install-scripts approve node-pty msgpackr-extract` + `npm rebuild`, `t3 serve` crash-loops on "Cannot find module pty.node". The T3 setup Flow must include approve+rebuild. Build tools (gcc, make, python3) are present in the base image.
- Crash-loop state is observable: service state shows `status: failed`, `error: exited with code 1`, `restart_count`, and `next_restart_at` (backoff). The supervisor restarts automatically.
- The documented `POST .../services/{name}/restart` endpoint returns 404 ("page not found") - it does not exist. Plan service restart as stop+start or definition re-PUT, and verify stop/start endpoints during ticket 6.
- t3 serve works through the public sprite URL: HTTP 200 from outside; the `/ws` WebSocket route answers 401 (auth-gated) through the proxy, proving upgrade requests route to t3. A full 101 handshake needs a genuinely paired client (ticket 10, with the real T3 Code app).
- Pairing: `t3 serve` prints `Connection string` + `Pairing URL: http://<local-ip>:3773/pair#token=...` + a QR to its log at every boot, but with the local IP. The right source for our app is `t3 auth pairing create --base-dir ... --base-url https://<sprite-url> --ttl ... --label ... --json`, which works while the service is running and emits `pairUrl` on the public host plus `expiresAt`. There is no `t3 auth session create`; sessions are minted by clients redeeming pairing tokens.
- Wake semantics: polling sprite metadata for 45s+ did not wake a warm sprite. A services-list GET also did not wake it (state answered from the frozen supervisor, sprite stayed warm) - services list appears shallow-safe, better than assumed; keep treating logs/exec as deep. A public URL request served 200 in ~200ms from warm (transparent warm wake; status field lags and is not a real-time activity indicator). Exec flips status to `running` immediately.
- Claude hooks fire headlessly: a `UserPromptSubmit` hook in user settings fired for `claude -p` even while logged out. Whether T3's invocation of the claude CLI loads user-level settings still needs the ticket-8 check with a real login.
- Checkpoint create streams NDJSON of `{type: "info"|"complete", data, time}` with human-readable strings; the checkpoint ID is buried in an info line ("  ID: v1") - parse accordingly. List returns `[{id, create_time, comment, is_auto}]` including a `Current` pseudo-entry. Restore streams info/complete and the sprite returns `running` with services back up. Quirk: checkpoint `create_time` did not match wall-clock creation time in this probe; do not trust it for ordering UI without re-verifying.

## Verified in third probe (apptest-probe3, since destroyed; live smoke suite)

Run via `SPRITES_LIVE_TOKEN=... SPRITES_LIVE_SPRITE=... swift test --filter LivePlatformSmokeTests` against the real client code.

- GET /v1/tasks answers `{"tasks": [...]}` (object wrapper), not the bare array the second probe's notes implied. POST body `{"name", "expire": "120s"}` confirmed; response echoes `{name, started_at, expires_at}`.
- Exec query encoding: URLQueryItem leaves `;` and `&` unencoded in values and the server splits on them - a `sh -c` script with `;` arrived truncated (`sh: -c requires an argument`). Values must be strictly percent-encoded.
- Framed non-TTY exec merges stderr into stdout frames (stream ID 2 documented, never observed), with nondeterministic interleaving. Exit codes exact. Output frames can trail the exit frame, so exit must be held until the server closes; and a fast command can close the socket before a stdin-EOF frame lands (send EOF best-effort).
- The exec PTY starts with TERM unset and size 0x0; `claude setup-token` waits forever without TERM. With `TERM=xterm-256color` (and rows/cols set) claude v2.1.220 renders immediately.
- Claude's sign-in URL appears in an OSC-8 hyperlink carrying an `id=` param (`ESC ]8;id=...;URL`), not empty params; the visible URL text is wrapped by the terminal and unusable. The CLI also emits `ESC ]9999;browser-open;URL` before the marker with the localhost-callback URL variant - anchoring extraction after the marker avoids it. The marker text "Browser didn't open? Use the url below to sign in (c to copy)" and the "Paste code here if prompted >" prompt are unchanged.
- The login Flow (FlowRun + ClaudeSetupTokenStep) reaches the code prompt against a live sprite in ~4s.
- Service stop/start endpoints (`POST .../stop`, `POST .../start`) work; logs endpoint returns text; delete works; upsert streams `started`/`log`/`complete`. Checkpoint create streams info/complete and the checkpoint lists with its comment.
- Wake decay: exec flips status to `running` transiently; an active task holds it `running`; with no tasks it settles back to `warm` within a couple of minutes. "Wake to inspect" therefore cannot rely on the status field staying `running`; user consent has to gate deep observation.
- Checkpoints list from a fresh sprite is a bare array containing the `Current` pseudo-entry with `is_auto: false` and no `comment`.

## Verified in fourth probe (apptest-probe4, since destroyed; full live flow validation)

Every Flow was driven end-to-end against a real sprite through the app's own
code paths (FlowRun + real client), with the OAuth browser side driven
separately and the code fed into the native prompt.

- `claude setup-token` persists nothing (documented: prints a CI token for
  CLAUDE_CODE_OAUTH_TOKEN). The login Flow uses `claude auth login --claudeai`
  instead: same PTY dialogue shape (different wording: "If your browser
  didn't open, visit: <bare url>"), and on success claude itself writes the
  documented store `~/.claude/.credentials.json` (Linux). `claude auth status
  --json` reports `loggedIn` and is used as the flow's verification.
- Ink swallows a trailing \r sent in the same chunk as the pasted code (it
  is treated as pasted text); Enter must be sent as its own keystroke after a
  short delay or the masked field never submits.
- Hand-written credentials (`{"claudeAiOauth":{accessToken,expiresAt,scopes,
  subscriptionType}}`) also log claude in, but are unnecessary with auth login.
- Tasks API semantics: POST /v1/tasks is create-only and answers 409 for an
  existing name; PUT /v1/tasks/{name} creates or refreshes (resets
  started_at, expires_at = now + expire). `expire` accepts both "120s" and
  "5m". sprite-env curl passes -f, so HTTP errors surface as exit 22. Both
  the Keep-alive and the heartbeat hooks must use PUT.
- Heartbeat hooks fire for headless `claude -p` while logged in: the task
  appears during the turn, an existing task's expiry is refreshed (PUT), and
  the Stop hook releases it after the turn.
- Full T3 setup Flow succeeded live in about a minute: npm install +
  install-scripts approve + rebuild, service on the installed binary,
  consent-gated public URL, pairing created while the service runs. Pairing
  JSON without --ttl carries no expiresAt. Pair-again issues a fresh code.
  Detail observation showed "T3 Code: service running (v0.0.31)", the
  open-in-t3-code action, recognition (not Custom), public root 200 and /ws
  401 through the proxy (re-confirming probe2).
- Checkpoint create streamed nine info events then complete; restore
  streamed info/complete; post-restore re-observation showed the login and
  service intact (same-state restore).
- `--base-dir` is T3's data directory (T3CODE_HOME, default `~/.t3`), where
  it keeps userdata/, caches/, and worktrees/ - not a workspace root.
  Passing `--base-dir /home/sprite` sprayed caches/ and worktrees/ into the
  home directory. The flow now omits --base-dir everywhere (data stays in
  the default `~/.t3`) and sets the service dir to the home dir (serve's
  cwd, inherited by provider sessions).
- The base image installs its npm agents user-globally: prefix `~/.local`
  (codex at `~/.local/lib/node_modules/@openai/codex` symlinked into
  `~/.local/bin`; gemini likewise; claude via its native installer under
  `~/.local/share/claude`). T3 follows the same convention:
  `npm install -g --prefix ~/.local --allow-scripts=node-pty,msgpackr-extract t3`
  builds node-pty's native module during install (npm blocks it by default;
  no separate approve/rebuild dance needed). msgpackr-extract's native part
  does not build but is optional acceleration; t3 serve boots fine.
  Re-validated on apptest-probe6: binary at `~/.local/bin/t3`, T3 data under
  `~/.t3`, home clean, full setup/pairing/checkpoint/keep-alive green.
- Task deletion can be visible with a short lag: one release read still
  showed the task; the next list was empty (deletion had landed).

## Still to verify (folded into tickets 8, 10)

- Full T3 pairing handshake and WS 101 with the official T3 Code iOS app through the public sprite URL (needs the shipping app plus a pairing code).
- Claude heartbeat hooks firing when T3 itself drives the `claude` CLI (hooks are user-level and fire for headless `claude -p`, so this is expected to hold; needs a paired client to confirm).
- Cold-wake (not warm-wake) latency and behavior through the URL and exec.

## Node runtime (apptest-probe7, since destroyed)

One node serves everything: nvm-managed v24.18.0 under
/.sprite/languages/node/nvm, first on PATH via /etc/profile.d (plus a
/.sprite/bin/node shim); no system node exists. codex, gemini, and the
installed t3 all use `#!/usr/bin/env node`, and a supervised service's
process was confirmed executing that same nvm node with the same PATH. So
node-pty is built by and run on the identical binary; the only ABI risk is
a base-image node bump across sprite upgrades, which would surface as a
crash-looping service and is fixed by re-running the setup Flow.
