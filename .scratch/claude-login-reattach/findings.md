# Exec-session semantics (spike-exec-sessions, since destroyed; ticket 01)

Verified 2026-08-05 with a raw URLSessionWebSocketTask rig mirroring the app's
wire code (strict percent-encoding, Bearer header, TTY raw frames), driving a
detached bash session through three abrupt socket drops (process exit, no WS
close frame), an idle decay to warm, reattach, and kill.

- TTY exec sessions survive client disconnect, as documented (default
  `max_run_after_disconnect` = forever for TTY). The same bash outlived every
  drop and answered stdin after each reattach. Corollary: every abandoned
  login to date has left a live `claude auth login` PTY behind.
- `session_info` arrives as the first text frame on create AND on every
  attach, verbatim: `{"type":"session_info","session_id":"20","command":
  "bash","created":1785904678,"cols":0,"rows":0,"is_owner":true,"tty":true}`.
  `session_id` is the process PID as a decimal string (kill events report the
  matching `pid`), so ids are small and recyclable: treat one as valid only
  within the flow that captured it. `cols`/`rows` report 0 even when the
  rows/cols query params were passed and honored (output wrapped at the
  requested width); do not trust session_info geometry.
- Attach (`WSS .../exec/{id}`): first data frame is the scrollback as a
  rendered snapshot, not raw byte history: ANSI is normalized and OSC-8
  hyperlinks are stripped to their visible text. The URL inside an OSC-8
  param is unrecoverable from a replay (only the terminal-wrapped visible
  text survives), so the sign-in URL must be captured on the live socket;
  no re-parsing it after the fact. stdin works immediately after attach.
- Exit delivery on an attached socket: `{"type":"exit","exit_code":0}` text
  frame, then the server drops the TCP connection without a WS close frame
  (the client sees a receive failure, "Socket is not connected"). Matches
  the existing hold-exit-until-close handling.
- A detached session does NOT hold the sprite running: it settled to `warm`
  within ~30s of the last output (faster than the couple-of-minutes decay
  seen in mvp probe 3) with the bash process alive. So zombie sessions don't
  burn money, and the login keep-alive task is genuinely needed. Attaching
  to the warm sprite woke it transparently (~300ms connect, replay
  immediately) into the same live process.
- List (`GET .../exec`): `{"count":N,"sessions":[{id, created, command,
  workdir, tty, bytes_per_second, is_active, last_activity}]}`. `command` is
  the RESOLVED absolute executable path plus args (`/usr/bin/sleep 654`, not
  the argv sent), so stale-login sweeps must match on the argv suffix
  (`claude auth login --claudeai`), never on argv[0]. `is_active` is
  unreliable (false for a live silent `sleep`, true for a detached
  recently-noisy bash); don't build logic on it. A naturally exited session
  disappears from the list immediately.
- Kill (`POST .../exec/{id}/kill`): streams NDJSON `signal` ("Signaling
  terminated to foreground process group ...") / `exited` / `signal` ("Closing
  PTY master") / `complete` with `exit_code` 143 for TERM; the session then
  vanishes from the list.
- Dead-session probes: HTTP GET `.../exec/{id}` answers 404 `session not
  found: {id}`; a WS attach to a dead id fails at the handshake (immediate
  receive failure, indistinguishable client-side from any bad response). The
  flow must treat attach-failure after a drop as "process ended while away".

## Still to verify

- Whether a detached exec session survives warm-to-cold decay (only warm
  survival verified; the login flow's 15m keep-alive sidesteps the question).
