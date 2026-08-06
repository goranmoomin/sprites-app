# 05 — Pairing screen rework

**What to build:** The Pairing screen hands off to the official T3 Code app
without burning the one-time credential, and every value on it is copyable.

Open T3 Code: the button copies the full pairing URL to the pasteboard and
opens `t3code://connections/new` — the app's Add Environment screen. Pasting
the URL into its Host field and tapping Connect completes pairing (verified
in T3 Code source: with an empty code field the pasted URL passes through
whole and the token is extracted from its fragment). If the open is not
accepted (app not installed), the screen says so and notes the link is
already copied — it never falls back to a browser, because the T3 web app's
/pair page auto-redeems the single-use token on mount (verified in source;
the app also has no universal links and no pair route, so an https URL can
never launch it).

Copyability: Host and Code become copyable rows (tap reveals Copy), the
Sprite URL row on the detail screen gets the same treatment via one shared
copyable-row view, and the QR image gets a context menu (copy pairing URL /
copy code) plus an accessibility label. Every copy gives haptic feedback.
The standalone "Copy pairing URL" button is removed — its payload remains
reachable via the rows, the QR menu, and the handoff button. The QR stays,
encoding the raw https pairing URL (scannable by the official app's built-in
QR scanner from another device); the code stays unmasked.

New code: a button on the pairing screen mints a fresh pairing against the
running Service (the pairing credential is single-use with a 5-minute TTL, so
a mistap currently dead-ends the flow). This requires the pairing prompt to
accept a "re-issue" response — the only Flow-prompt shape change in this
wave. While in the parsing code: read the `credential` field the CLI actually
emits instead of relying on the URL-fragment fallback.

**Blocked by:** None — can start immediately.

**Status:** resolved

- [x] Open T3 Code copies the pairing URL and opens the Add Environment
      screen; not-installed case messages clearly; no browser path exists
- [x] Host, Code, and the detail screen's Sprite URL use one shared copyable
      row with haptic feedback; QR has context menu and accessibility label
- [x] "Copy pairing URL" button is gone; the URL is still copyable
- [x] New code mints a fresh pairing in place without restarting the flow
- [x] Pairing parse reads the `credential` JSON field; fragment fallback
      covered by test
- [ ] End-to-end: pair the official app on a real device via the new handoff

## Comments

Implemented. `CopyableValueRow` (Menu-on-tap + sensory feedback) shared by
Host, Code, and the sprite URL; QR gains a context menu and accessibility
label; "Open T3 Code" copies the pairing link then opens
`t3code://connections/new` with a not-installed fallback message and no
browser path anywhere; `FlowResponse.reissue` + a prompt loop in the pairing
step powers "New code"; the parser reads `credential` first. The real-device
end-to-end handoff remains for a manual pass.
