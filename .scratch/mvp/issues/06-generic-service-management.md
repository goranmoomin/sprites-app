# 06 — Generic service management

**What to build:** The general create-service Flow: name, executable, arguments as an array (never a shell string), working directory, environment, optional HTTP port. Service upsert consumes the platform's streamed NDJSON progress. Existing services get start/stop/restart controls and a recent-logs view. Custom services (unrecognized) get exactly these generic controls and nothing more.

**Blocked by:** 04 — Sprite detail with deep observation.

**Status:** resolved

- [ ] Create-service form maps 1:1 to the platform service definition (cmd, args, http_port, env, dir, needs)
- [ ] Upsert progress (started/complete/error events) is shown live
- [ ] Start, stop, restart work and re-observe service state (empirical: the documented restart endpoint returns 404 - implement restart as stop+start or definition re-PUT, and verify stop/start endpoints)
- [ ] Crash-looping services surface `failed`, `error`, `restart_count`, and `next_restart_at` from observed state
- [ ] Recent logs are viewable as text
- [ ] Service deletion works (endpoint verified empirically; undocumented but functional)
- [ ] No shell-string command input anywhere

## Comments

Restart is implemented as stop+start (the documented restart endpoint
returned 404 in the apptest-probe2 run; see findings.md). Stop/start
endpoint shapes are taken from the official JS SDK; live verification of
stop/start against a real sprite is still pending.

Stop/start endpoints verified live in the smoke suite (service stopped,
restarted, logs fetched, deleted against a real sprite).
