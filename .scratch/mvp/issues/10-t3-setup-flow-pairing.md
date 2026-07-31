# 10 — T3 Code setup Flow and Pairing

**What to build:** The T3 Code integration's setup Flow: install T3 once (npm package `t3`, resolving the then-current release into a fixed runtime directory; then `npm install-scripts approve node-pty msgpackr-extract` and `npm rebuild` - linux prebuilds are missing and npm blocks their build scripts by default, without which t3 crash-loops), define the `t3 serve` service (installed binary as cmd, host 0.0.0.0, port, `--base-dir`, `--no-browser`; never `npx` in the service command), gate the URL-visibility change to public behind an explicit consent step, obtain the Pairing credential via `t3 auth pairing create --base-url https://<sprite-url> --json` (verified: works while the service runs and emits `pairUrl` on the public host; serve's own log prints a local-IP pairing URL, which is the wrong host for us), and render the Pairing screen: hostname, one-time code, QR, copy buttons, "Open T3 Code" handoff. "Pair again" is a standalone Flow on the detail screen. The installed T3 version is observable.

**Blocked by:** 06 — Generic service management; 07 — Integration recognition and Actions; 08 — Claude Code login Flow.

**Status:** resolved

- [ ] Flow requires at least one logged-in coding agent before proceeding
- [ ] T3 installs once; the service runs the installed binary; cold-start boot needs no network resolve
- [ ] Public URL change happens only after explicit consent; visibility updates on the detail screen
- [ ] Pairing screen shows hostname, one-time code, QR, copy actions, and opens the T3 Code app
- [ ] "Pair again" works standalone after restore or expiry
- [ ] "Open in T3 Code" Action appears via recognition once the service runs
- [ ] Empirical check performed: full pairing handshake and WS 101 with the official T3 Code iOS app through the public sprite URL (HTTP 200 and auth-gated /ws routing already verified; record in findings.md)

## Comments

The full pairing handshake with the official T3 Code iOS app (WS 101
through the public sprite URL) still needs a live run with a real sprite
and the shipping app; HTTP 200 and auth-gated /ws routing were already
verified in apptest-probe2 (findings.md). The T3 Code app URL scheme used
for the handoff (t3code://) is a placeholder pending that check.
