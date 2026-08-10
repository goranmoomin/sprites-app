# One-Click Claude Code Login

Evidence: `findings.md` in this directory, plus
`.scratch/claude-login-reattach/findings.md` and
`.scratch/claude-credential-persistence/findings.md`. Decisions grilled to
shared understanding 2026-08-10. Implementation tickets: `issues/01`-`06`.

## Problem Statement

Logging Claude Code in today means running the interactive `auth login`
browser dialogue on every new Sprite: a browser hop, a paste step, per
Sprite, every time. The credentials it produces are refresh-chained and
single-holder, so they cannot be shared across Sprites, and the app would
have to own a refresh chain to keep even one Sprite logged in past 8 hours.
Anyone who provisions Sprites regularly repeats the same login ceremony on
each one.

## Solution

Replace `auth login` with a `claude setup-token` based login. The token a
setup-token run prints is inference-only, valid for a year, carries no
refresh chain, and fans out to any number of Sprites at once (verified
live). The app runs the browser dialogue once, shows the minted token, and
with the user's consent saves it (token plus mint date) in the iOS
Keychain. Every subsequent Sprite is logged in by planting the token into
the `env` block of `~/.claude/settings.json`: no browser, no paste, one
click. Verification is a real inference probe, offered but never forced.
The interactive `auth login` Flow is removed.

## User Stories

1. As a Sprite user on my first Sprite, I want the login Flow to walk me
   through the browser sign-in once, show me the minted token, and offer
   to save it, so that later Sprites need no browser at all.
2. As a Sprite user on a later Sprite, I want the same Flow to notice my
   saved login and plant it silently, so that logging in is one click.
3. As a privacy-conscious user, I want a "use on this Sprite only" choice
   at mint time, so that saving a year-long credential is my decision.
4. As a Sprite user, I want an optional verify step that runs a real
   `claude -p` probe and shows the result, so that I can prove the login
   works without paying for a probe on every provision.
5. As a Sprite user whose saved token has died, I want the plant branch's
   verify failure to tell me the saved login no longer works, forget it,
   and fall through to a fresh mint in place, so that recovery never
   leaves the screen.
6. As a Sprite user, I want the sprite list's app menu to show my saved
   login's mint date and offer to forget it, with a reminder that
   forgetting does not revoke, so that I can stop using a saved login.
7. As a Sprite user, I want a "Log out Claude Code" action on the sprite
   detail screen that removes the planted token from that Sprite, so that
   I can de-authorize a Sprite without destroying it: including one whose
   token a Checkpoint restore resurrected.
8. As a Sprite user, I want the detail screen's logged-in/not-logged-in
   status to be the claude CLI's own answer, so that the app never
   re-implements auth precedence.
9. As a user reading the consent screen, I want the security facts stated
   where they matter: the token lives a year, sits in plaintext on each
   Sprite, is captured by Checkpoints, and the app cannot revoke it.
10. As a Sprite user with the base image's own hooks configured, I want
    the heartbeat hook install to append rather than overwrite, so that
    `sprite-env-check.sh` survives login.

## Implementation Decisions

- One branching Flow, "Log in Claude Code", replaces the `auth login`
  Flow outright. First step checks the saved login: present plants
  silently, absent runs the setup-token dialogue. `ClaudeAuthLoginStep`'s
  machinery (keep-alive task, zombie sweep, TERM/geometry setup,
  reattach-and-resubmit) is generalized and reused by the mint step; the
  `auth login` argv variant and its `.credentials.json` verification are
  deleted. Remote Control is explicitly unsupported until further notice.
- The zombie sweep matches the new argv suffix (`claude setup-token`).
  The plant branch needs no keep-alive task: it is a handful of exec
  calls, which are activity in themselves.
- The sign-in URL and the printed token must both be parsed from the live
  PTY socket: scrollback replay strips OSC-8 hyperlinks (verified live),
  so a drop before capture means starting over. Token parsing anchors on
  known output wording like `extractSignInURL` does, failing visibly if
  the CLI rewords.
- Mint outcome: the token is shown (copyable) with a consent choice, save
  to the app or use on this Sprite only. Planted on the current Sprite
  either way. Declining save just means the next Sprite mints again.
- Storage is a second Keychain generic-password item in the
  `KeychainTokenStore` idiom: token plus mint date, local-only, no iCloud
  sync, one slot. Sync and multi-account are cheap migrations if ever
  wanted. The mint date is display-only: no expiry timers.
- Planting merges `CLAUDE_CODE_OAUTH_TOKEN` into the `env` block of
  `~/.claude/settings.json`, preserving all other keys: the same
  read-merge-write discipline as the hooks install, which writes the same
  file. `~/.claude.json` is not touched: no onboarding seeding.
  Interactive attach may hit the onboarding wizard; accepted.
- Verification is never automatic. The Flow ends with a skippable verify
  step running a `claude -p` probe under a timeout and showing the
  result. In the plant branch, a failed probe reports "your saved login
  no longer works", clears the Keychain slot, and falls through to mint.
- `observeStatus` runs `claude auth status --json` and maps `loggedIn`
  straight to logged in / not logged in. It parses the JSON, never exit
  codes (`auth status` exits 1 when logged out). Known and accepted: it
  validates nothing (a fake token reports logged in); truth on demand is
  the verify step.
- "Log out Claude Code" appears in `actions()` when logged in: deletes
  the `env.CLAUDE_CODE_OAUTH_TOKEN` key merge-preservingly, best-effort
  removes `.credentials.json` to cover legacy logins, and states that the
  token itself stays valid and stays saved in the app if saved.
- "Forget saved login" lives in a new sprite-list toolbar menu, the app's
  first app-level surface: shows the mint date, confirmation states that
  forgetting does not revoke and does not unplant existing Sprites.
- Security copy appears at exactly two moments: save-time (year-long,
  plaintext on Sprites, captured by Checkpoints, unrevocable from the
  app) and forget-time (does not revoke).
- The mint branch sweeps `/tmp/xdg-open.log` (best-effort `rm -f`) on
  success and failure paths: the CLI leaves the full authorize URL there.
- The heartbeat hooks clobber fix lands first as its own commit: the
  install step appends to existing hook arrays, matching its own command
  string for idempotency, so the base image's `sprite-env-check.sh` hooks
  survive. This is the same merge behavior the claude-code-service spec
  mandates; landing it here first does not conflict.
- T3 constraint, worth a comment at the plant site: T3 drives Claude via
  the agent SDK with a pass-through environment by default, so the
  planted token works; configuring a custom Claude `homePath` in T3 sets
  `CLAUDE_CONFIG_DIR` isolation and would bypass
  `~/.claude/settings.json`, making the login invisible to T3-driven
  Claude.

## Testing Decisions

- Swift side, at the existing fake-platform seam, in the style of the
  current login-flow behavioral suite: the branching step (plants when a
  token is saved, mints when not), the plant step's merge (other env keys
  and hooks survive), the mint dialogue against scripted PTY output
  (URL extraction, token extraction, consent outcomes, zombie sweep by
  new suffix, xdg-open sweep), the verify step (skip, pass, and the
  plant-branch fail path forgetting the token and falling through),
  `observeStatus` mapping `auth status` JSON, the logout action's merge
  and legacy cleanup, and the hooks append fix.
- Parser unit tests for the token extraction against transcripts captured
  live (OSC-8 and wrapped-text variants), alongside the existing
  `extractSignInURL` tests.
- Keychain store: same coverage as the existing `KeychainTokenStore`
  usage, plus mint-date round-trip.
- Live acceptance at the interactive-rig seam (`SPRITES_INTERACTIVE=1`):
  one real mint on a throwaway Sprite, plant on a second Sprite from the
  saved token, both running `claude -p` concurrently. The fan-out claim
  is the product; it is not sign-off-able from unit tests.

## Out of Scope

- Remote Control and claude.ai connectors: the setup-token grant is
  inference-only; the deleted `auth login` path is resurrectable from git
  history when a Remote Control integration actually lands.
- The `roles` endpoint as a cheaper verify probe (unverified unknown; the
  verify seam accommodates swapping it in later).
- App-native OAuth minting without a Sprite (would move minting to app
  settings; the dialogue machinery is kept reusable for it).
- iCloud Keychain sync, multiple saved logins, onboarding seeding, expiry
  warnings.
- The claude-code-service resident Service (separate spec); only the
  hooks append fix overlaps, deliberately.

## Further Notes

- Facts this design rests on, verified in the findings: one token logs in
  N Sprites concurrently with no exclusivity or rotation; re-minting does
  not revoke outstanding tokens; the paste step is mandatory without port
  forwarding; the source Sprite retains nothing after `setup-token`; the
  `settings.json` env plant authenticates both `claude -p` and
  SDK-driven (T3) invocations; `auth status` trusts any planted string.
- Open unknowns carried from the findings: how many setup-tokens an
  account may hold, where revocation happens and whether it is
  observable, whether the OAuth approval page can be one-tap in an in-app
  browser.
- Enterprise `forceLoginMethod` can block `setup-token` entirely; not
  handled, surfaces as a visible mint failure.
