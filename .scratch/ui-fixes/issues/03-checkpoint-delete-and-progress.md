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

**Status:** resolved

- [x] Platform seam + fake support checkpoint deletion; live smoke test pins
      204 on delete, 409 on the active checkpoint
- [x] Manual checkpoints: swipe Delete with anchored confirm; Current
      undeletable; automatic checkpoints visible but restore-only
- [x] Create and restore both show status line + monospaced streaming log;
      restore progress appears inline in the Checkpoints section
- [x] Completed log persists with a resolved status line and an explicit
      dismiss; starting a new operation or leaving the screen clears it
- [x] The permanent checkpoint-progress section no longer exists
- [x] List ordering uses the version ordinal

## Comments

Implemented. `deleteCheckpoint` on the platform seam (HTTP DELETE, fake with
Current/notFound refusals) plus a live smoke test pinning the undocumented
endpoint. `checkpointProgress` replaced by `CheckpointActivity` (title,
phase, accumulated log) rendered by one `CheckpointActivityView` used both
inline in the Checkpoints section and in the create sheet. Restore/delete
confirms are per-row anchored dialogs; swipe actions hide while an operation
runs. The live smoke case still needs one run against a real sprite
(`SPRITES_LIVE_TOKEN`/`SPRITES_LIVE_SPRITE`) to check the pin.
