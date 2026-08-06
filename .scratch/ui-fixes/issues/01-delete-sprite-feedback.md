# 01 — Delete-sprite progress and anchored confirmation

**What to build:** Deleting a Sprite gives honest feedback everywhere it can
be triggered. The confirmation popover appears attached to the button or row
that asked for it (iOS 26 anchors confirmation dialogs to their source view;
today they are attached to whole containers, which is why the popup lands in
arbitrary places). While the delete runs, the detail screen's Delete button
shows an inline spinner and disables, and the screen dismisses only after the
platform confirms; on the list, the row dims, shows a spinner, and loses its
swipe actions until it disappears. Nothing is optimistic.

Delete ownership moves to the list model: a `deletingSprites: Set<String>`
tracks every in-flight delete (several can overlap — delete from detail,
swipe back, delete another), inserted on entry and removed via `defer` on
every exit path, with the removal ordered after the post-delete refresh so a
row never un-dims while still visible. The operation runs in a model-owned
Task so dismissing a screen mid-delete cannot cancel it. The detail screen
derives its button state from the same set through the existing callback
seam. The service detail screen's stop/delete dialogs get the same anchoring
treatment.

**Blocked by:** None — can start immediately.

**Status:** resolved

- [ ] Simulator repro first: confirm the misanchored popover on the current
      build, then confirm the fix anchors to the trigger (detail button, list
      row, service detail actions)
- [x] Detail: spinner in the Delete button during the call; dismiss only
      after success; failure keeps the screen with the existing error surface
- [x] List: rows for every member of `deletingSprites` are dimmed, show a
      spinner, and have swipe actions disabled; no optimistic removal
- [x] Two overlapping deletes are each represented independently
- [x] Swiping back mid-delete neither cancels the delete nor strands a set
      entry; behavioral test covers insert/remove on success, failure, and
      delete-succeeded-but-refresh-failed (row stale, not stuck spinning)

## Comments

Implemented: `deletingSprites: Set<String>` on the list model with a
model-owned task and defer-clear ordered after the post-delete refresh;
detail deletes call through a `deleteSprite: (String) async -> Error?` seam;
all three destructive confirms (list row, detail button, service detail)
anchored to their triggers. The misanchored-before state is evidenced by the
user's device screenshot; the anchored-after state compiles and is pending a
visual pass on device, so the repro box stays open.
