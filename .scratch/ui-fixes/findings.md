# UI fixes — exploration findings

Split from the 2026-08-04 backlog exploration (code deep-dives at `d820891`,
live probes via the authenticated `sprite` CLI against a throwaway sprite,
t3code source sweep of the clone at `~/Developer/Personal/t3code`). This file
is the evidence backing the tickets in `issues/`; where a finding poses an
open question, the ticket's decided behavior supersedes it. Integration-wave
evidence lives in `.scratch/integrations/findings.md`; the heartbeat/service
evidence moved to `.scratch/claude-code-service/findings.md`.

## Probe results relevant to this wave

| Probe | Result |
|---|---|
| Checkpoint DELETE | **Exists (undocumented).** `DELETE /v1/sprites/{s}/checkpoints/{id}` → 204, gone from list. `Current` → 409 `cannot delete active checkpoint`. Unknown id → `404 page not found`. The installed CLI build has no `checkpoint delete` subcommand; the API works regardless. Tripwire smoke test required. |
| Auto checkpoints (platform docs) | Platform-created "as you work"; `auto-` IDs, no comment; hidden by default in the CLI (`--include-auto`); pruned over time by the platform; restorable by ID like any checkpoint. Only documented deletion rule: "you can't delete the checkpoint you're currently on". |
| Max task `expire` | **3600s hard ceiling** (400 above it). PUT is create-or-refresh. Relevant here: the unified hold task's 1h TTL is the platform max. |
| Fly sprite token format | `<org-slug>/<number>/<32 hex>/<64 hex>` (captured live, e.g. `sungbin-jo/35742/…`). No whitespace. Verify slug charset against a second org before hardcoding a matcher. |
| Claude paste-code format | Still uncaptured — one `SPRITES_INTERACTIVE=1` run of the interactive login rig should log its shape (ticket 04 task). |
| T3 Code mobile app (source-verified) | Expo app; schemes `t3code://` (prod, `com.t3tools.t3code`), `t3code-preview://`, `t3code-dev://`. Associated domains **Clerk-only** — no `applinks:app.t3.codes`, no backend hosts; `apps/web` (which is app.t3.codes) serves **no AASA file**. **No `/pair` route** — `t3code://pair?...` from another app lands on the NotFound wildcard (verified in `Stack.tsx`: full linking table, `"*"` → NotFoundScreen). Pairing surfaces: Add Environment (`t3code://connections/new`, Host + Pairing-code fields) and its QR scanner (`?mode=scan_qr`; accepts raw pairing URLs or a `t3code://pair?pairingUrl=<encoded>` QR-payload dialect). |
| Full-URL-into-Host (source-verified) | The on-change re-parse keys on the QR-scan-provided value, not the Host field — but pasting a full pairing URL into Host with an empty Code field works anyway: `buildPairingUrl` returns the Host string unchanged when code is empty, and the submit path extracts `#token=` and derives base URLs from it. Schemeless hostname ⇒ `https://`, schemeless IP ⇒ `http://`. |
| `/pair` web page | Auto-redeems the single-use credential on mount, unconditionally, both direct and hosted variants — no interstitial, no confirm param. Default pairing TTL 5 minutes; consumption atomic; redeemed bearer sessions live 30 days. This is the token-burning bug: any browser open of the URL consumes it. |
| Pairing credential JSON | `t3 auth pairing create --json` emits `id`, `credential`, `label?`, `scopes`, `expiresAt`, `pairUrl?` (only with `--base-url`) — **no `token`/`code` field**; our parser's fragment fallback is what currently saves it (ticket 05: read `credential`). `t3 pair` mints fresh tokens against a running server (`--ttl`, default 5m). |

## Delete-sprite bug

- **No in-flight state exists.** Neither model sets a flag during delete;
  the list model's delete does a delete + full refresh round-trip with no
  observable state; the detail screen dismisses the instant the await
  resolves. Even with a flag, row-local state would die with the swiped row.
- **Popup position, diagnosed on-device (iOS 26 screenshot):** iOS 26
  presents `confirmationDialog` as a *source-anchored popover* on iPhone
  (previously a bottom action sheet). The dialogs are attached to whole
  containers (the detail `List`, the list `Group`), so the anchor is the
  container's frame — the arrow in the screenshot points at the middle of
  the List, nowhere near the Delete button. "Random places" = wherever the
  container's anchor rect lands. The earlier popover/size-class and
  swipe-row-teardown hypotheses were secondary; the anchoring is primary.
- The service detail screen stacks the identical shape.
- Decided behavior in ticket 01 (anchored-to-trigger dialogs, model-owned
  `deletingSprites: Set<String>`, defer-cleared after refresh, no optimism).

## Refresh on focus

- Today: `.task` + `.refreshable` only; `.refreshable` missing from the
  list's error/empty branches; no `scenePhase` observation, no polling;
  popping back never refreshes (only the delete callback does).
- Deep observation *is* waking: there is no wake endpoint — `wake()` execs
  `true`; any exec/deep call is activity. Shallow metadata polling is free
  (probed: does not wake a warm sprite).
- `hasWokenForInspection` existed because exec-woken sprites settle back to
  warm within minutes, so status alone made consent flicker. The unified 5m
  hold task (ticket 02) makes `running` stable and the flag deletable.
- Re-entrancy: no guard on either model; four trigger sources can stack.
  Sheet completion handlers already refresh → debounce needed.
- Foreground refresh with a revoked token bounces to login via the session
  handler — desirable, keep.

## Checkpoints

- `checkpointProgress` is a transcript of NDJSON events (`info`/`complete`,
  human-readable strings, ~nine per create, no percent, no stage enum) — a
  CLI log echoed as a `List`. Two renderings: create sheet (acceptable) and
  a permanent detail-screen section that lingers until the next operation.
  Restore has no feedback at all beyond that lingering section.
- The user's complaint is the rendering (row per line) and the lingering —
  the log itself is wanted, including after completion (outcome + failure
  evidence). Ticket 03: monospaced text block, status line, terminal state,
  explicit dismiss.
- `create_time` did not match wall-clock in the mvp probe — sort by the
  version ordinal.

## Login

- Current flow opens `/dashboard/personal/tokens` (not `/sprites`) in
  SFSafariViewController; "Use copied token" reads the pasteboard on tap
  (system paste prompt); only validation is length ≥ 20 and no whitespace —
  which does accept the real captured token format.
- iOS pasteboard facts that shaped ticket 04: *checking* the pasteboard
  against a format requires reading it, and any content read is the
  privileged act (the system alert). `detectPatterns` is prompt-free but
  fixed-pattern only (no custom regex). `PasteButton` is prompt-free but
  system-labeled and requires its own tap. `changeCount` is the entire
  prompt-free signal budget: "something new was copied". Decision: accept
  the one-time system alert on return-from-browser (b-variant), fill, never
  auto-submit.
- Claude flow: sign-in `Link` opens system Safari (leaves the app), code
  pasted into a bare TextField feeding a live PTY; Enter must be sent as a
  separate later keystroke (Ink swallows same-chunk `\r`). No `scenePhase`
  plumbing exists yet anywhere in the app.
- Docs describing the old paste-prompt design as resolved: mvp spec, mvp
  issue 01, CONTEXT.md Sprite-token entry.

## Pairing screen

- "Open T3 Code" currently opens `pairing.pairURL` (an https URL) via
  `openURL` — the browser gets it and the `/pair` page burns the token. The
  `t3code://` app-URL constant exists but is only wired to the detail-screen
  Action, and was until now unverified.
- The pairing screen's prompt response is ignored entirely — the "New code"
  button (ticket 05) needs the pairing prompt to accept a re-issue response;
  this is the only Flow-prompt shape change in this wave.
- No copy affordances exist anywhere except two plain pasteboard-write
  buttons on this screen; no `contextMenu`, no haptic feedback, QR has no
  accessibility label. House idiom for the fix: one shared copyable row
  (tap → Menu with Copy), `.sensoryFeedback`, contextMenu on the QR.
- Same-device constraint: sprites-app and T3 Code run on the same phone, so
  the QR cannot carry the local handoff — it stays for pairing *other*
  devices. Handoff = copy URL + open Add Environment + paste into Host.
