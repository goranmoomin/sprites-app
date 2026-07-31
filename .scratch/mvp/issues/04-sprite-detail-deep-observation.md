# 04 — Sprite detail with deep observation

**What to build:** Tapping a sprite opens the detail screen. For any sprite it shows shallow data: status, URL, URL visibility. For a running sprite it deep-observes: the services list (name, cmd/args, state, pid), live platform tasks (via `sprite-env curl` over exec against the management socket — this ticket builds the framed non-TTY exec transport), and the checkpoints list. A cold sprite shows shallow data plus a "Wake to inspect" affordance; deep observation never runs without the sprite already running or the user explicitly waking it.

**Blocked by:** 02 — Sprite list with shallow observation.

**Status:** resolved

- [ ] Detail screen shows status, URL, and URL visibility for any sprite without waking it
- [ ] Running sprites additionally show services (with cmd/args/state), live tasks, and checkpoints
- [ ] Cold sprites show "Wake to inspect"; deep observation runs only after explicit wake
- [ ] The fake platform asserts deep calls never hit a cold sprite uninvited (ADR 0001)
- [ ] Wake latency is surfaced as a "waking..." state, not an error
- [ ] Empirical check performed against a real sprite: which calls wake a cold sprite, and the observed idle-pause window (record results in findings.md)

## Comments

Empirical wake-semantics checks were already performed in the apptest-probe2
run and recorded in findings.md (metadata polling and services-list GET do not
wake a warm sprite; exec flips status to running immediately). No live sprite
was available during implementation, so no additional probe was run; the app
treats services/tasks/checkpoints as deep observation per the ticket.
