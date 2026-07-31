# 11 — Checkpoints

**What to build:** Checkpoint management on the detail screen: create with a comment (streamed NDJSON progress), list (manual `v*` checkpoints; automatic `auto-*` hidden or clearly separated), and restore with a destructive warning stating that it rolls back agent logins, services, and Pairing made after the checkpoint. After restore the screen simply re-observes — no special-case state repair.

**Blocked by:** 04 — Sprite detail with deep observation.

**Status:** ready-for-agent

- [ ] Create with comment shows streamed progress and the resulting checkpoint appears in the list
- [ ] Restore warns destructively and shows progress; active sessions dropping is tolerated
- [ ] Post-restore, the detail screen reflects rolled-back reality purely via re-observation (fake test: agent login and service vanish from observation after restore to an earlier state)
- [ ] Automatic checkpoints do not clutter the primary list
- [ ] Empirical check performed: checkpoint create/restore NDJSON shapes (record in findings.md)
