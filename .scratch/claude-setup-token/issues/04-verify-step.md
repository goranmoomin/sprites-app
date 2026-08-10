# 04: Skippable verify step and dead-token recovery

Spec: `.scratch/claude-setup-token/spec.md`

What to build: the "Log in Claude Code" Flow ends with an optional verify
step: it offers to run a real `claude -p` probe under a timeout and shows
the result, and skipping it still completes the Flow successfully.
Verification is never automatic anywhere else; `auth status` reports
logged in for any planted string, so this probe is the only honest signal.

In the plant branch, a failed probe means the saved token is dead (revoked
or expired): the Flow reports that the saved login no longer works, forgets
it from the Keychain, and falls through to a fresh mint in place, so
recovery never leaves the screen.

Blocked by: 03 (save and one-click reuse).

Status: done (2026-08-10)

- [x] Verify offered at the end of both branches; skipping completes the
      Flow; running it shows the probe result
- [x] The probe runs under a timeout; a hung CLI fails the step, not the
      Flow's completed planting
- [x] Plant branch with a dead saved token: the Flow reports it, clears the
      saved login, and continues into the mint dialogue (fake-platform
      coverage for report, forget, and fall-through)
- [x] Mint branch verify failure reports without forgetting anything
