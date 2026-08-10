# Sharing one `claude setup-token` across Sprites

Verified 2026-08-10 with two throwaway sprites (`tokprobe1`, `tokprobe2`, both
destroyed), Claude Code 2.1.220 native install, two real `claude setup-token`
runs on a Max account, and code.claude.com/docs/en/authentication. Resolves the
third open Unknown in `.scratch/claude-credential-persistence/findings.md`
("Whether `CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token` is enough for the
Flows we care about"), and reuses that document's storage and precedence facts
without re-testing them.

Headline: sharing works, and it is strictly better than transplanting
`.credentials.json` for the coding-agent role. One setup-token, planted as
`CLAUDE_CODE_OAUTH_TOKEN` in the `env` block of `~/.claude/settings.json`, logs
Claude Code in on N Sprites at once for a year, with no refresh chain to manage
and no re-plant. The cost is that the grant is inference-only, so it cannot
serve the Claude Remote Control Integration, and the browser hop still has to
happen once with a paste step.

## What a setup-token actually grants

- The authorize URL requests exactly one scope: `scope=user:inference`. An
  interactive `claude auth login` is granted five (`user:file_upload`,
  `user:inference`, `user:mcp_servers`, `user:profile`,
  `user:sessions:claude_code`, per the prior findings). The limitation is
  enforced at the grant, not by client-side policy, so no app-side change can
  widen it.
- Same `client_id` as the interactive login,
  `9d1c250a-e61b-44d9-88ed-5944d1962f5e`.
- Token shape `sk-ant-oat01-<...>`, 108 chars, same prefix as the access token
  in an interactive login's `claudeAiOauth.accessToken`.
- Docs: one-year validity, requires Pro/Max/Team/Enterprise, precedence 5 of 6,
  not read in bare mode (`--bare` / `CLAUDE_CODE_SIMPLE=1`).

## Fan-out: VERIFIED, and there is no exclusivity problem

The decisive difference from the `.credentials.json` transplant. That document's
single-holder chain is a property of refresh rotation; a setup-token carries no
refresh token, so nothing can rotate and nothing gets invalidated.

- Same token planted on both sprites, `claude -p` run concurrently on both:
  both exit 0, both produced output.
- Re-running `claude -p` on sprite 1 after sprite 2 had used the token: exit 0.
- Consequence for the product: "Claude Code: logged in" can be shown truthfully
  on every Sprite at once from a single login. No re-plant-on-refresh machinery,
  no lazy-refresh discipline, no 8 h ceiling.

Tokens are also independent of each other. After minting a second token,
sprite 2 kept working on token 1 while sprite 1 worked on token 2. So re-issuing
is safe: it does not revoke outstanding tokens, and it does not disturb the
user's laptop login either.

## Planting mechanism: `settings.json` `env` block works

```json
{ "env": { "CLAUDE_CODE_OAUTH_TOKEN": "sk-ant-oat01-..." } }
```

Written into `/home/sprite/.claude/settings.json`, with the variable absent from
the shell environment (`env | grep -c CLAUDE_CODE_OAUTH_TOKEN` -> 0):

- `claude auth status --json` -> `{"loggedIn": true, "authMethod": "oauth_token",
  "apiProvider": "firstParty"}`
- `claude -p` works, exit 0
- `/status` in the TUI shows a row `Auth token: CLAUDE_CODE_OAUTH_TOKEN`
- No file is written: `~/.claude/.credentials.json` never appears, before or
  after inference

This is the same file `InstallHeartbeatHooksStep` already writes, so one Flow
can do both.

## The source Sprite keeps nothing

`claude setup-token` persists nothing, as documented. After a successful run on
`tokprobe1`: no `~/.claude/.credentials.json`, `~/.claude` unchanged, and
`claude auth status --json` still `{"loggedIn": false, "authMethod": "none"}`,
exit 1. The token exists only in PTY output. Missing it means re-running the
whole browser hop.

## The paste step is mandatory for us

Worth recording because the first probe was misleading. Run through
`sprite exec --tty`, `setup-token` completed on its own the moment the browser
approval happened, with no code pasted. That is not a server-side polling flow:
`sprite exec` auto-forwards ports the command opens, and the CLI had a localhost
callback server listening (`/tmp/xdg-open.log` records
`redirect_uri=http://localhost:41759/callback`), so the callback reached the
Sprite through the forward.

Re-run with `--no-port-forward`, the same browser approval left the CLI sitting
at `Paste code here if prompted >` indefinitely. It only completed once the code
was sent over the PTY.

The app's API-based exec sessions have no port forwarding, so the Flow needs the
same URL-then-paste dialogue `ClaudeAuthLoginStep` already implements. One
detail is easier here: `setup-token` emits the sign-in URL as an OSC-8
hyperlink, which `ClaudeOutputParser.extractSignInURL` handles directly, whereas
`auth login` prints it as terminal-wrapped bare text.

## Blockers and gotchas

- Inference-only kills Remote Control. `claude --remote-control <name>` started
  the normal REPL but `/status` showed no Remote Control row: the session
  silently failed to establish, with no error surfaced to the user. Matches the
  docs ("can't establish Remote Control sessions or fetch claude.ai
  connectors") and the bundle string quoted at `@139146722` in the prior
  findings. If the Claude Remote Control Integration is a target, both login
  paths must coexist and the coding-agent Flow must not present setup-token as
  the only option.
- Interactive `claude` still walks onboarding on a fresh Sprite even with a
  valid token: theme picker, then the login-method chooser ("Claude account with
  subscription / Anthropic Console account / 3rd-party platform"). The token is
  fine; the Sprite has simply never been onboarded. The base image's
  `~/.claude.json` ships without `hasCompletedOnboarding` or `theme`. Writing
  `hasCompletedOnboarding: true` and `theme: "dark"` fixed it: the next launch
  went trust-prompt -> bypass-permissions warning -> REPL, with
  `Auth token: CLAUDE_CODE_OAUTH_TOKEN` in `/status`. A plant Flow must seed
  both keys or the "one-click login" is not one click.
- `claude auth status` does not validate the token. Planting the literal string
  `sk-ant-oat01-FAKEFAKEFAKE` still produced
  `{"loggedIn": true, "authMethod": "oauth_token"}`. Any readiness signal built
  on it is trusting a string, not a credential.
- `ClaudeCodeIntegration.observeStatus` has the mirror-image problem: it checks
  `fileExists(/home/sprite/.claude/.credentials.json)`, which never exists in
  env-token mode, so it would report "not logged in" forever. Deep observation
  needs a real probe (an inference call, or an authenticated request to
  `https://api.anthropic.com/api/oauth/claude_cli/roles` with a plausible
  `User-Agent`).
- Checkpoint exposure is worse than with the credentials file. The token sits in
  plaintext in `settings.json` and is valid for a year, not 8 h, so a Checkpoint
  taken afterwards captures a long-lived credential. Restoring an old Checkpoint
  also silently reinstates a possibly-revoked token.
- Enterprise `forceLoginMethod` blocks `setup-token` (docs: every login path
  enforces `forceLoginMethod` on v2.1.212+). `forceLoginOrgUUID` is not enforced
  for `setup-token`, so a token can be minted in a different organization than
  the pin names.
- `/tmp/xdg-open.log` still leaks the full authorize URL (localhost-callback
  variant) on any Sprite where a login or setup-token was ever run. Unchanged
  from the prior findings; sweeping it applies to this Flow too.

## Unrelated bug found while probing

`InstallHeartbeatHooksStep` (`Sources/SpritesCore/Integrations/ClaudeCodeLoginFlow.swift`)
assigns `hooks["UserPromptSubmit"]` and `hooks["PostToolUse"]` outright. The
Sprite base image ships `~/.claude/settings.json` with its own hooks on both
events, running `"$HOME"/.sprite-shared/hooks/sprite-env-check.sh`. The heartbeat
install destroys them. It should append to the existing arrays, matching on its
own command string for idempotency.

## Comparison with the `.credentials.json` transplant

| | setup-token + env var | `.credentials.json` transplant |
| --- | --- | --- |
| Lifetime | 1 year | 8 h access, ~27.7 d refresh chain |
| Fan-out to N Sprites | Yes, independent | Only if `refreshToken` is stripped |
| Re-plant on refresh | Never needed | Required after every app-side refresh |
| App must own a refresh chain | No | Yes, and losing it is unrecoverable |
| Scopes | `user:inference` only | Five, full login |
| Remote Control | Broken | Works |
| claude.ai connectors | Broken | Works |
| On-Sprite artifact | `settings.json` env entry | `.credentials.json`, mode 0600 |
| Checkpoint blast radius | 1-year credential | 8 h credential |

Neither dominates. setup-token is the better coding-agent credential;
a full login chain is the only thing that can back the control-plane role.

## Proposed design

Two Flows on the Claude Code Integration, in CONTEXT.md vocabulary.

- Flow "Log in Claude Code (shareable)": drive `claude setup-token` in a
  headless PTY, extract the OSC-8 sign-in URL, run the existing
  `openURLAndEnterCode` prompt, submit the pasted code, then parse the printed
  `sk-ant-oat01-` token out of the PTY output. Show it to the user with a
  consent step: save to the app for reuse on other Sprites, or use here only.
  Plant it on this Sprite either way. Reuses `ClaudeAuthLoginStep`'s
  keep-alive-task, zombie-sweep, and reattach machinery verbatim; only the argv
  and the terminal parse differ.
- Flow "Reuse saved Claude login": no PTY, no keep-alive, no browser. Read the
  saved token from the iOS Keychain, merge it into `settings.json` `env`, seed
  `hasCompletedOnboarding` and `theme` into `~/.claude.json`, verify with a real
  inference probe. Eligible for the create-Sprite playlist, which is what makes
  provisioning one-click.
- The existing interactive `auth login` Flow stays, unchanged, as the only path
  that produces a full-scope Agent. It is what the Claude Remote Control
  Integration must require.
- App-side storage: the token string plus the mint date, in the iOS Keychain.
  There is nothing to rotate, so no atomic-persist discipline is needed. Offer a
  "forget saved login" action, and note in the UI that forgetting does not
  revoke.
- Observation: `ClaudeCodeIntegration.observeStatus` needs a third state.
  Distinguish "no credential" from "credential present but unverified" from
  "verified", where verification is a real probe, not `auth status`. The env
  entry and the credentials file are two different presence signals and both
  must be checked.
- Security riders the Flow should state once: the token is plaintext on the
  Sprite and captured by Checkpoints; it is valid for a year; the app cannot
  revoke it.

## Unknowns

- How many setup-tokens an account may hold at once, and whether old ones are
  evicted. Two coexisted; N is untested.
- Where a user revokes a setup-token, and whether revocation is observable from
  the CLI.
- Whether `claude -p` is the cheapest honest verification probe, or whether the
  `roles` endpoint can stand in without burning subscription usage.
- Whether the OAuth approval page can be made one-tap in the in-app browser when
  the user is already signed in to claude.com. Carried over unresolved from
  `.scratch/claude-credential-persistence/findings.md`.

## Sources

- Live probes on `tokprobe1` / `tokprobe2` (destroyed): two `claude setup-token`
  runs via `sprite exec --tty` and `sprite exec --tty --no-port-forward`,
  `settings.json` env planting, concurrent `claude -p` on both Sprites,
  cross-token independence check, fake-token probe, `~/.claude.json` onboarding
  patch, `claude --remote-control` plus `/status`, `/tmp/xdg-open.log` reads.
- `https://code.claude.com/docs/en/authentication`: "Generate a long-lived
  token", "Authentication precedence", "Credential management", "Restrict login
  to your organization".
- `.scratch/claude-credential-persistence/findings.md` for credential storage,
  refresh mechanics, scope list, and the `/tmp/xdg-open.log` leak. Not
  re-verified here.
