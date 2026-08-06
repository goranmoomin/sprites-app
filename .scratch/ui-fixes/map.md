# UI fixes — effort map

Five independent tracer-bullet tickets covering the self-contained UI fixes
from the backlog exploration. Decisions were grilled to shared understanding
on 2026-08-04; the supporting evidence lives in `findings.md` in this
directory. Related efforts split out of the same exploration:
`.scratch/claude-code-service/` (the heartbeat/service work, with its own
spec) and `.scratch/integrations/` (the future T3 Connect / Tailscale /
GitHub wave and its cross-cutting vocabulary decisions).

## Tickets

- 01 — Delete-sprite progress and anchored confirmation (no blockers)
- 02 — Unified app hold task + refresh on focus (no blockers)
- 03 — Checkpoint delete and honest progress (no blockers)
- 04 — Login token auto-fill and dashboard redirect (no blockers)
- 05 — Pairing screen rework (no blockers)

All five are unblocked. Sequencing notes (not blocking edges): 01 and 02
both touch the sprite detail and list screens; 04 and 05 both touch the
flow-run UI — land one before starting the other in each pair to avoid
churn.

## Key decisions (details in each ticket, evidence in findings.md)

- Destructive confirms use `.confirmationDialog` anchored to the trigger
  view — iOS 26 presents these as source-anchored popovers, and anchoring to
  a whole container is what caused the "random places" popup.
- One app-held platform task (`sprites-app-keep-alive`) covers both Wake to
  inspect (5m) and Keep active (1h). `hasWokenForInspection` is removed;
  deep observation gates purely on `status == running`. Focus refresh never
  wakes.
- Checkpoint deletion uses the undocumented DELETE endpoint (probed: 204;
  active checkpoint 409; unknown 404) with a live smoke test as tripwire.
- Login auto-fill reads the pasteboard on return (accepting the system paste
  alert), fills the field on a format match, never auto-submits. Sprite
  token format: `<org-slug>/<number>/<32 hex>/<64 hex>`.
- Pairing handoff: copy pairing URL + open `t3code://connections/new`; the
  official app has no pair route and no universal links (verified in
  source).

## Deferred (recorded, not ticketed here)

- Everything integration-shaped: see the cross-cutting list in
  `.scratch/integrations/findings.md` (Capability vocabulary, new FlowPrompt
  cases, `SpriteAction.Kind.copy`, structured IntegrationStatus, revoke
  flows, task recognition). The `FlowResponse` addition for ticket 05's
  "New code" is the only prompt-shape change in this wave.
