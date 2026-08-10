# 01: Heartbeat hook install appends instead of clobbering

Spec: `.scratch/claude-setup-token/spec.md`

What to build: the login Flow's heartbeat hook install assigns the
UserPromptSubmit and PostToolUse hook arrays outright, and the Sprite base
image ships `~/.claude/settings.json` with its own hooks on both events
(running its env-check script), so every login to date has silently
destroyed them. Change the step to append its entry to the existing
arrays, matching on its own command string for idempotency: re-running
the Flow must not stack duplicates, and a settings file that already
carries the entry comes out with its hooks unchanged. The Stop hook gets
the same treatment. All other keys in the file survive untouched, as
today.

This is an isolated bug fix and lands as its own commit before the
setup-token feature builds on it. It is also the same merge behavior the
claude-code-service spec mandates for its hook install; whichever effort
lands second finds the work done.

Blocked by: None: can start immediately.

Status: done (2026-08-10)

- [x] Base-image-style hooks on UserPromptSubmit and PostToolUse survive a
      login; the heartbeat entries are appended alongside them
- [x] Running the step twice produces no duplicate entries (idempotency by
      command-string match)
- [x] Behavioral tests at the fake-platform seam cover both: preexisting
      foreign hooks preserved, double-install stable
