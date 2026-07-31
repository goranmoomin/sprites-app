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

## Still to verify (folded into tickets 8, 10)

- Full T3 pairing handshake and WS 101 with the official T3 Code iOS app through the public sprite URL.
- Claude heartbeat hooks firing when T3 itself drives the `claude` CLI (requires a real Claude login).
- Cold-wake (not warm-wake) latency and behavior through the URL and exec.
