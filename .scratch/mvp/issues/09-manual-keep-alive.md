# 09 — Manual Keep-alive

**What to build:** A Keep-alive control on the detail screen: keep active (creates the app's named platform task via exec against the management socket, max 1h), extend (refresh expiry), release (delete). The Tasks section shows it alongside any other live tasks (e.g. the Claude heartbeat) with expiry times, platform naming intact — a Keep-alive is visibly just a task the app holds.

**Blocked by:** 04 — Sprite detail with deep observation.

**Status:** resolved

- [ ] Keep active creates the named task; the Tasks list shows it with its expiry
- [ ] Extend refreshes the expiry; release deletes the task
- [ ] Expiry behavior is tested against the injected clock in the fake
- [ ] Creating a Keep-alive on a cold sprite wakes it knowingly (explicit user action, "waking..." state)
- [ ] No auto-lease is created by any other feature

## Comments

Live validation (findings.md, fourth probe): the tasks API's POST is
create-only and 409s on an existing name, so create/extend both go through
PUT /v1/tasks/{name} (upsertTask on the seam). Create, extend (expiry
moved), and release were verified through SpriteDetailModel against a real
sprite.
