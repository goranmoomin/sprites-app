# 03 — Checkpoint delete and honest progress

**What to build:** Manual checkpoints can be deleted, and checkpoint
operations report progress like the CLI log they are, not like a table.

Delete: the platform seam gains a delete-checkpoint operation backed by the
undocumented endpoint (probed live: 204 on success, 409 "cannot delete active
checkpoint" for the current one, 404 for unknown IDs). Because it is
undocumented, a live smoke test pins the 204/409 behavior as a tripwire. In
the UI, a red Delete joins Restore in the trailing swipe group with a
confirmation anchored to the row (per ticket 01's pattern). Only manual
checkpoints are deletable: the Current entry shows no delete (and the 409
copy is surfaced if it ever races), and automatic checkpoints stay visible in
their separate section, restore-only — the platform creates and prunes those
itself. Delete is not offered while a restore is in flight.

Progress: the streamed NDJSON events render as one monospaced,
text-selectable block (the exec-output idiom) under a status line — "Creating
checkpoint…" / "Restoring v2…" with a spinner. The create sheet shows the
pair; restore shows the same pair inline in the Checkpoints section, which
today has no feedback at all. On completion the status line resolves
("Checkpoint v2 restored" / failure with the log intact as evidence) and the
log *stays* until the user dismisses it via an explicit control, a new
checkpoint operation starts, or the screen is left. The permanent, unlabeled
"Checkpoint progress" section is gone. Checkpoints sort by their version
ordinal, not `create_time` (probed untrustworthy).

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] Platform seam + fake support checkpoint deletion; live smoke test pins
      204 on delete, 409 on the active checkpoint
- [ ] Manual checkpoints: swipe Delete with anchored confirm; Current
      undeletable; automatic checkpoints visible but restore-only
- [ ] Create and restore both show status line + monospaced streaming log;
      restore progress appears inline in the Checkpoints section
- [ ] Completed log persists with a resolved status line and an explicit
      dismiss; starting a new operation or leaving the screen clears it
- [ ] The permanent checkpoint-progress section no longer exists
- [ ] List ordering uses the version ordinal
