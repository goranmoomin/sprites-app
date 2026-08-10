# 02: Setup-token login replaces auth login

Spec: `.scratch/claude-setup-token/spec.md`

What to build: on a fresh Sprite, the "Log in Claude Code" Flow drives
`claude setup-token` in a headless PTY behind native UI: extract the sign-in
URL from the live socket, run the existing open-URL-and-enter-code prompt,
submit the pasted code, then parse the printed `sk-ant-oat01-` token out of
the live PTY output and show it to the user (copyable) before planting it
into the `env` block of `~/.claude/settings.json`. The dialogue reuses the
existing login machinery: keep-alive task, zombie sweep (now matching the
`claude setup-token` argv suffix), TERM/geometry setup, and
reattach-and-resubmit. Both the URL and the token must be captured on the
live socket: scrollback replay strips OSC-8 hyperlinks. Token parsing
anchors on known output wording and fails visibly if the CLI rewords. The
mint branch sweeps `/tmp/xdg-open.log` on success and failure paths.

The interactive `auth login` variant and its credentials-file verification
are ripped out (Remote Control is explicitly unsupported; git history keeps
the code). Status observation switches to running `claude auth status
--json` on the Sprite and mapping `loggedIn` to logged in / not logged in,
parsing the JSON rather than exit codes (the CLI exits 1 when logged out).
No saving or reuse in this ticket: the token screen's only choice is
continue.

Worth a comment at the plant site: T3 drives Claude through the agent SDK
with a pass-through environment by default, so the planted token works, but
a custom Claude homePath configured in T3 sets `CLAUDE_CONFIG_DIR` and would
bypass the planted login.

Blocked by: 01 (heartbeat hook append fix lands first as its own commit).

Status: done (2026-08-10)

- [x] Fresh Sprite: the Flow completes with one browser hop and a paste,
      plants the token merge-preservingly (other env keys and hooks
      survive), and the detail screen shows logged in
- [ ] `claude -p` succeeds on the Sprite after the Flow (live acceptance at
      the interactive-rig seam; rig updated, run pending)
- [x] The token and URL are parsed from live output only; a reworded CLI
      fails visibly, covered by parser tests against captured transcripts
- [x] Zombie setup-token sessions are swept by argv suffix; no terminal
      outcome leaks a live PTY
- [x] `/tmp/xdg-open.log` is gone after the Flow, on failure paths too
- [x] `auth login` Flow, argv variant, and credentials-file checks are
      removed; status observation runs `auth status --json` and its JSON
      mapping is covered at the fake-platform seam
