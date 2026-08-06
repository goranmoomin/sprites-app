# 02 — Unified app hold task + refresh on focus

**What to build:** The app holds a Sprite running through exactly one named
platform task, `sprites-app-keep-alive`, and screens refresh themselves when
the user comes back to them — without ever waking a Sprite as a side effect.

The hold: "Wake to inspect" upserts the task with a 5-minute expiry (the
Tasks API is in-sprite, so the upsert itself is the waking activity — one
exec, same cost as today's no-op). "Keep active for an hour" and "Extend"
upsert the same task with 1 hour; "Release" deletes it. The detail screen
shows one hold with its remaining time. There is no collision between the
two TTLs: a Sprite offering "Wake to inspect" is not running, and a
not-running Sprite cannot have a live hold. `hasWokenForInspection` is
deleted; deep observation gates purely on `status == running`, which the 5m
hold makes stable (the old flag existed only because exec-woken Sprites
settled back to warm within minutes). Once the hold expires, the screen
honestly degrades to "Wake to inspect" again — pull-to-refresh after expiry
shows the button instead of silently re-waking.

Refresh on focus: the list and detail screens refresh when the scene becomes
active, and the list also refreshes when navigation returns to it. Focus
refreshes are silent (no spinner), always shallow first, deep only if the
fresh metadata says running. Both models get a coalescing in-flight guard,
and focus refreshes skip if a refresh finished within the last ~5 seconds
(absorbs the sheet-dismiss double-fetch). The list's error and empty branches
become pull-to-refreshable like the populated branch.

Update the Keep-alive entry in CONTEXT.md: it is now *the* task the app holds
on the user's behalf, TTL varying by gesture (5m inspect, 1h keep-active),
max 1h per platform rules. Note the deferred future feature in the effort
map: integrations recognizing tasks (this hold, the Claude heartbeat) the way
they recognize Services.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] Wake to inspect creates the hold task with 5m expiry, visible in the
      Tasks section, and the Sprite stays running for the window
- [ ] Keep active / Extend set the same task to 1h; Release deletes it; the
      UI presents a single hold, never two concepts
- [ ] `hasWokenForInspection` is gone; deep observation happens iff metadata
      reports running; after hold expiry, refresh degrades to "Wake to
      inspect" without waking
- [ ] Foregrounding the app or navigating back never wakes a cold or warm
      Sprite — pinned by a cold-deep-call tripwire test
- [ ] Concurrent triggers (task, refreshable, scene-active, navigate-back)
      coalesce; no spinner on focus refreshes
- [ ] Keep-alive behavioral tests updated: wake now creates the hold task by
      design; error/empty list branches are refreshable
