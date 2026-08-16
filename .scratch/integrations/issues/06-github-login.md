# 06 - Log in to GitHub

**What to build:** A GitHub tile in the "other" row. First Sprite: the login Flow runs gh's device flow, shows the one-time code (prominent, copyable) and the GitHub URL, warns that GitHub will ask for a second factor, and waits up to the device-flow deadline; on success it captures the token and account, sets up git's credential helper, sets the commit identity to the user's name and noreply address only while the base image's identity is still in place, verifies with a free API round trip, and offers to save the login. Later Sprites: the saved login is planted silently (`config.yml`, `hosts.yml`, mode 600, credential helper, identity). The tile shows the account and scopes and calls out a `GH_TOKEN` from the environment masking the planted login. Consent copy says the token stays valid on other Sprites and the laptop, is revocable only at GitHub, and that a restore can bring it back.

**Blocked by:** 02 (Requirement and Category), 03 (Status details), 04 (SavedLoginStore).

**Status:** resolved

- [x] `GitHubIntegration` registered, category other, offering the login Flow when not logged in; observation reads `hosts.yml` and requires an `oauth_token:` line (a bare `{}` is logged out); details show login and scopes
- [x] New integration-neutral prompt `.openURLAndShowCode(url, code, instructions)`; the code is copyable; the step keeps running underneath
- [x] Mint is a non-TTY exec with the default scopes plus `workflow`, update notifier disabled, own short keep-alive task, killable by session id, stale sessions swept by command suffix; code and URL parsed from stderr by anchor; the deadline exit reads as "you never finished"
- [x] Capture via `gh auth token` and `gh api user` immediately after the mint; save-with-consent as `SavedGitHubLogin {token, login, name, id, scopes, mintedAt}`
- [x] Plant writes `config.yml` first, then `hosts.yml` with the load-bearing keys, chmods both to 600, runs `gh auth setup-git`, sets `user.name`/`user.email` only when the current email is the base image's
- [x] Verify step runs `gh api user --jq .login` without a consent gate, falling back to `gh auth status` verbatim, and surfaces a `(GH_TOKEN)` source
- [x] Never a PTY, never `GH_TOKEN`, token never in argv
- [x] Tests against the fake: recognition (none), flow offering, mint happy/declined/deadline, save then silent plant, identity guard, `{}` is logged out, cold-deep-call tripwire, stderr-line tripwire; a `SPRITES_INTERACTIVE=1` live rig; a findings entry

## Answer

Done in fae8701. `GitHubIntegration`/`GitHubLoginFlow`, `.openURLAndShowCode`, `SavedGitHubLogin`, plant order and chmod, `setup-git`, guarded identity, ungated verify with dead-token fall-through, `hosts.yml` `oauth_token:` observation with the account as a detail (scopes are not on the Sprite and are not shown), tripwires, live rig `InteractiveGitHubTests`, findings note.

## Comments

2026-08-16: The mint as shipped did not complete on device. The non-TTY exec died with the WebSocket when Safari suspended the app (only TTY sessions outlive their socket; see ADR 0005), so gh was killed mid-poll and `gh auth token` found nothing. The mint now runs in a headless PTY with `GH_PROMPT_DISABLED=1 NO_COLOR=1 TERM=xterm-256color`, the step answers gh's terminal probe (OSC 11 and cursor position) itself, and the existing reattach-by-identity path carries the hop. "Never a PTY" above is superseded; the rest of the checklist stands. Findings entry updated under "The mint".
