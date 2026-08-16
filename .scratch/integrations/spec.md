# Integrations wave: GitHub, Tailscale, T3 Connect, and the Board

Status: ready-for-agent

Evidence: `findings/` in this directory (one document per integration plus
`cross-cutting.md`), all CONFIRMED against real accounts on 2026-08-11/12
unless labelled INFERRED. Decisions grilled to shared understanding
2026-08-16; the glossary (`CONTEXT.md`), ADR-0008 and the amended ADR-0007
were written in that session. Implementation issues: `issues/01`-`09`.

## Problem Statement

A fresh Sprite has exactly one Integration that logs in silently (Claude
Code) and one control plane (T3 Code over a public URL plus a Pairing).
Anything else the user's workflow needs is done by hand from a phone: a
GitHub login so the Agent can push (today every commit is authored
`Sprite <noreply@sprites.dev>` and `git push` fails outright), a Tailscale
node so the Sprite is reachable privately instead of through a public URL,
and T3 Connect so the Sprite simply appears in the T3 Code app without a
URL or Pairing at all. The create-sprite path is also a fixed ordered
playlist of two Flows, which cannot express "log in any of my coding
agents, then pick one of several ways to reach the Sprite".

## Solution

Three new integrations and one new surface. Log in to GitHub mints once and
plants many, exactly like Claude. Tailscale takes a reusable auth key
pasted once and plants it on every Sprite. T3 Connect authorizes each
Sprite through the CLI's own headless login and links it to the user's T3
account, so the Sprite shows up in the T3 Code app's list under its Sprite
name. T3 pairing can additionally be served over the tailnet's MagicDNS
name instead of a public URL. The playlist becomes the Board: every
Integration as one tile in Category rows, the same view on the create path
and on the detail screen, tap a tile to run its Flows and come back.

## User Stories

1. As a Sprite user, I want to log in to GitHub on a Sprite once, so that later Sprites are logged in without a browser.
2. As a Sprite user, I want the GitHub login to show me a short code and the GitHub URL with a copy button, so that I can type the code into Safari on my phone.
3. As a Sprite user, I want to be warned that GitHub will ask for a second factor, so that the extra prompt does not look like a failure.
4. As a Sprite user, I want the GitHub login to time out cleanly when I never finish, so that a forgotten login does not leave a stuck step.
5. As a Sprite user, I want to be asked whether to save the GitHub login in the app, so that I decide whether it fans out to other Sprites.
6. As a Sprite user, I want `git push` over HTTPS to work on a logged-in Sprite, so that the Agent can push without me configuring credential helpers.
7. As a Sprite user, I want commits from a Sprite authored as me (my GitHub name and noreply address), so that they count on my profile.
8. As a Sprite user, I want the app not to overwrite a git identity I set by hand on the Sprite, so that my own configuration survives the login.
9. As a Sprite user, I want a GitHub token to be requested with the `workflow` scope, so that pushing workflow files is not rejected.
10. As a Sprite user, I want the GitHub tile to show which account is logged in and its scopes, so that I can tell Sprites and accounts apart.
11. As a Sprite user, I want to be told when a Sprite is using a `GH_TOKEN` from the environment instead of the planted login, so that a masked login is not a mystery.
12. As a Sprite user, I want the GitHub verify step to be free and ungated, so that "logged in" is a real API round trip rather than a file's presence.
13. As a Sprite user, I want the GitHub consent copy to say the token stays valid on my other Sprites and laptop and can only be revoked at GitHub, so that I know what forgetting and deleting do not do.
14. As a Sprite user, I want to add a Tailscale auth key once by opening the admin keys page and pasting the key, so that every Sprite joins my tailnet without a browser hop.
15. As a Sprite user, I want the pasted key to never appear in a command line, so that it does not leak to process lists or the exec-session list.
16. As a Sprite user, I want a Sprite to join the tailnet under its own Sprite name, so that I recognize it in the admin console and in URLs.
17. As a Sprite user, I want a Sprite to stay on the tailnet across cold and wake, so that I do not re-authorize after every wake.
18. As a Sprite user, I want the app to forget an expired or revoked auth key and ask me for a new one, so that a dead key does not fail silently forever.
19. As a Sprite user, I want the Tailscale tile to show the MagicDNS name, tailnet and addresses, so that I can reach the Sprite from my other devices.
20. As a Sprite user, I want to long-press any status detail to copy it, so that a MagicDNS name or address gets into another app without retyping.
21. As a Sprite user, I want to be told not to checkpoint after joining the tailnet, so that a restore does not resurrect a stale node.
22. As a Sprite user, I want the app to fail with the CLI's own message when I changed Tailscale settings by hand, so that my configuration is not silently reset.
23. As a Sprite user, I want to set up T3 Code through T3 Connect, so that the Sprite appears in my T3 Code app's list without a public URL or a Pairing.
24. As a Sprite user, I want the T3 Connect login to open a URL and take the code the page shows me, so that I can authorize from my phone.
25. As a Sprite user, I want the T3 Connect flow to say up front that it costs a few taps on every Sprite, so that the per-Sprite cost is not a surprise.
26. As a Sprite user, I want the tunnel consent to say precisely what transits T3's relay and where TLS terminates, so that I know what I am agreeing to.
27. As a Sprite user, I want the app to wait for the link to be confirmed by the relay before calling the Sprite ready, so that "linked" is observed, not assumed.
28. As a Sprite user, I want the T3 tile to say whether the Sprite is linked and to which mode, so that a stale link is visible.
29. As a Sprite user, I want to still be able to pair T3 Code over a public URL when I prefer, so that Connect is a choice, not a replacement.
30. As a Sprite user, I want to pair T3 Code over my tailnet's HTTPS name, so that the Sprite never has to be public.
31. As a Sprite user, I want the tailnet pairing to tell me when MagicDNS, HTTPS certificates or Serve are not enabled on my tailnet and open the console page to fix it, so that I am not stuck on an unexplained failure.
32. As a Sprite user, I want the tailnet pairing to be blocked until Tailscale is ready on the Sprite, with the reason named, so that I run things in a workable order.
33. As a Sprite user, I want the T3 setup Flows blocked until one of the coding agents T3 Code actually supports is logged in, with the agents named, so that the block explains itself.
34. As a Sprite user, I want the create-sprite second page to be a Board of tiles by category, so that I pick which coding agents, control planes and other integrations to set up on this Sprite.
35. As a Sprite user, I want the detail screen's integrations section to be the same Board, so that setup and later inspection look and behave the same.
36. As a Sprite user, I want a tile that offers several Flows to expand into a chooser with the recommended one first, so that a product with three ways to set up stays one tile.
37. As a Sprite user, I want a tile's state to be what the Sprite currently reports, not what I did last, so that a restore or a hand change is reflected.
38. As a Sprite user, I want the Board to load all integration statuses at once, so that a Sprite with five integrations does not take five seconds to show.
39. As a Sprite user, I want the app-menu list of saved logins to show one row per integration that has one, with forget per row, so that I control what fans out.
40. As a Sprite user, I want no logout Flows anywhere, so that the app does not pretend to reverse logins it cannot revoke; deleting the Sprite is the reversal.
41. As a Sprite user, I want the T3 version out of the summary line and into details, so that the summary reads as a status.
42. As a maintainer, I want a new integration to declare only its category and its Flows' Requirements, so that adding one never means inventing a new capability.
43. As a maintainer, I want the Board built from the registry, so that there is no second hand-maintained list.
44. As a maintainer, I want tripwire tests on every undocumented vendor surface the wave depends on, so that a vendor change fails loudly.
45. As a maintainer, I want a live rig per integration, so that the fake's scripts are pinned to real behavior.

## Implementation Decisions

Ordered as the implementation issues will be. Glossary terms are from
`CONTEXT.md`.

### 1. Requirement and Category (ADR-0008)

- `Capability` and the `provides`/`requires` declarations on Integration are removed.
- Integration gains a display-only `category`: coding agent, control plane, other. It groups Board rows and nothing else.
- Flow gains `requires`, a list of Requirements. A Requirement is a set of Integration ids (`anyOf`); a Flow is runnable when every Requirement has at least one member observed ready. Integrations expose their Requirements as static members (T3 Code's supported coding agents, Tailscale).
- The check lives once, at the start of a `FlowRun`; a Flow that fails it ends blocked with a sentence naming the products ("needs Claude Code or Codex logged in on this sprite", "needs Tailscale"). The in-flow `RequireCodingAgentStep` and the playlist's separate pre-check go away.
- The registry's "ready provider" helper becomes "first ready among these ids".

### 2. The Board

- Replaces `CreateSpritePlaylist` and the detail screen's integrations list. One model, two placements: the create-sprite second page and the detail screen section.
- Rows are Categories in fixed order (coding agent, control plane, other); within a row, registry order. One tile per Integration, showing its observed `IntegrationStatus`.
- Tapping a tile launches its single offered Flow, or shows a chooser when it offers several; T3 Code's chooser lists Connect first, then pairing over public URL, then pairing over tailnet, and "Pair again" when a recognized Service exists.
- Tile state is re-observed after every Flow finishes and on every visit; nothing is ordered, remembered, or marked done app-side (ADR-0001). Blocking uses the Flow's Requirements at launch.
- Statuses of all integrations are observed concurrently, results placed in registry order. File probes preferred; no batching into one exec.

### 3. Store, status details, prompts, logout removal

- One central `SavedLoginStore`: at most one saved login per Integration id, persisted as opaque `Data` in one Keychain item per id under a shared name prefix; each Integration owns its `Codable` payload and its display line. Claude's `SavedClaudeLogin` migrates onto it; the in-memory variant serves tests. The app menu lists one row per integration with a saved login, with forget per row.
- Payloads: Claude `{token, mintedAt}`; GitHub `{token, login, name, id, scopes, mintedAt}`; Tailscale `{authKey, savedAt}`. T3 Connect has none.
- `IntegrationStatus` gains `details`, an ordered list of `(label, value)`. Every detail row is copyable by long-press. The deferred `copy` action kind is not added.
- Two new integration-neutral `FlowPrompt` cases: `.openURLAndShowCode(url, code, instructions)` (code prominent and copyable, acknowledged; the step keeps running underneath) and `.openURL(url, instructions)` (open, come back, acknowledged; used only for web-console preconditions). No secret-entry case; pasting reuses `.openURLAndEnterCode`.
- External web-console preconditions (MagicDNS, HTTPS certs, Serve enablement) are steps that detect, prompt `.openURL` with the console page, re-detect on acknowledge, and fail with the same prompt on retry.
- All logout Flows and steps are removed, including Claude's; nothing replaces them (ADR-0007 amended). Forget-saved-login in the app menu stays.

### 4. Log in to GitHub

- Category: other. `provides` nothing; no Flow requires it in this wave.
- Mint: plain non-TTY exec of `gh auth login --hostname github.com --git-protocol https --web --scopes workflow`, stdin at /dev/null, `GH_NO_UPDATE_NOTIFIER=1`, holding its own short keep-alive task and killable by session id, sweeping stale sessions by command suffix. Parse the code anchored on `one-time code: ` and the URL anchored on `Open this URL`, both from stderr; prompt `.openURLAndShowCode`; wait for exit. Exit 1 with `context deadline exceeded` is "you never finished". Never a PTY.
- Capture: `gh auth token` immediately after a successful mint, then `gh api user --jq` for `login`, `name`, `id`. Offer save-with-consent exactly as Claude does.
- Plant (silent, from the saved login): write `config.yml` (`version: "1"`) first, then `hosts.yml` (top-level `oauth_token`, `user`, `git_protocol`, plus the `users:` map), then `chmod 600` both, then `gh auth setup-git --hostname github.com`. Never via `GH_TOKEN`.
- Commit identity: set `user.name` and `user.email` (`<id>+<login>@users.noreply.github.com`) with `git config --global` only while the current email is still the base image's `noreply@sprites.dev`.
- Observe: read `hosts.yml` and require `oauth_token:` (existence alone is wrong: gh's own logout leaves `{}`); details show login and scopes from the file. Verify step: `gh api user --jq .login`, no consent gate, falling back to `gh auth status` verbatim, and surfacing a `(GH_TOKEN)` source as "using a token from the environment, not the planted login".
- Consent copy states the token stays valid on other Sprites and the laptop, is revocable only at GitHub, and that a Checkpoint restore can bring the login back.

### 5. Log in to Tailscale

- Category: other. Provides nothing; `t3-setup-tailscale` requires it by id.
- One login Flow. Install the pinned static tarball into `~/.local/bin` (version resolved from Tailscale's stable JSON at flow time); define `tailscaled` as a Service with no args, default socket, dir `/home/sprite`; then plant.
- Credential: a reusable, non-ephemeral auth key. First time: `.openURLAndEnterCode` on the admin keys page ("generate a reusable auth key and paste it"), then save-with-consent. Every time: write the key to a 600 file and run `tailscale up --json --auth-key=file:<path> --hostname=<sprite name> --timeout=60s` with the same fixed complete flag set every run and no `--reset`; the complete-set-of-flags error surfaces verbatim. Delete the key file after.
- On an expired or revoked key failure the flow forgets the saved key and re-prompts. The OAuth-client credential (`tskey-client-`, no expiry, tag-owned) is the recorded upgrade, gated on a live probe of `?ephemeral=false&preauthorized=true`; not in this wave.
- Observe: not set up / not running from the Service list alone; when the Service is running, one `tailscale status --json` (parse JSON, never the exit code) for readiness (`BackendState == Running`) and details: MagicDNS name (trailing dot stripped), tailnet, CGNAT-filtered addresses, Service state. `NeedsMachineAuth` reads as "waiting for device approval".
- Copy says do not checkpoint after joining. SSH stays out.

### 6. T3 Connect

- A second setup Flow, `t3-setup-connect`, on the existing T3 Code integration (same category, same Requirement); it takes the T3 tile's recommended slot. Managed link only; publish-only is not offered.
- Steps: the shared install and Service-definition steps reused from `t3-setup`; a consent naming the tunnel, the account authorization, what transits the relay (control plane only: no thread content, files, or terminal output; project and thread titles do transit and reach APNs; TLS terminates at Cloudflare's edge on T3's zone) and the per-Sprite cost of a few taps; `t3 connect login --headless` in a non-TTY exec with stdin held open, prompting `.openURLAndEnterCode` with the URL parsed from stdout and feeding the pasted code to stdin; `t3 connect link`; restart the Service; poll for the linked marker file. No public-URL consent and no Pairing prompt on this path.
- Observe: file presence probes for credential, desired link mode, and relay-confirmed link; details show linked state and mode alongside the version. Readiness for the Connect path is the relay-confirmed link file.
- The "Open in T3 Code" Action remains; on a linked Sprite the copy says the Sprite is in the T3 Code list under its name.
- T3's telemetry default is left alone. No unlink or logout.

### 7. T3 pairing over the tailnet

- A third setup Flow, `t3-setup-tailscale`, requiring the T3-supported coding agents and Tailscale.
- Shared prefix; then precondition steps for MagicDNS (from `CurrentTailnet.MagicDNSEnabled`), and Serve enablement (run `tailscale serve --bg --https=443 http://127.0.0.1:<port>` bounded by a timeout, parse the "Serve is not enabled ... visit <url>" wording), each using `.openURL`; then create the Pairing with host `https://<MagicDNS name>/`, no public-URL consent.
- Blocked on enabling Serve on the user's tailnet once to measure certificate provisioning; the retry budget is set from that measurement.

### Cross-cutting

- Secrets never in argv: stdin or `file:` indirection, always followed by `chmod 600` where the app writes them (`writeFile` has no mode).
- Every integration prints the URL the user needs on its own stdout/stderr; parse that. No shared browser-open observer (dead end recorded in findings).
- Board rows and glossary use "T3 Connect" as a proper noun; "connect" as a common noun stays avoided.

## Testing Decisions

- A good test drives a whole Flow or model through the fake platform and asserts on what the Sprite ends up with (files, services, tasks) and what the user was shown (prompts, status lines, details), never on step internals.
- Seams, unchanged in kind: `FakeSpritesPlatform` (scripted execs, files, services, clock, held wakes) under `FlowRun`, `SpriteDetailModel`, `CreateSpriteModel`; the in-memory saved-login store; `SPRITES_INTERACTIVE=1` live rigs; parsers as pure functions.
- Seams that change shape: the Board model replaces `CreateSpritePlaylist` in the create-path and tile tests; the in-memory `SavedLoginStore` replaces the Claude-only one.
- Per new integration, the same four suites Claude and T3 have (recognition, flow offering, flow scripting with happy, declined, timeout and dead-credential paths, cold-deep-call tripwire), a setup-idempotence test, one live rig, and a findings entry.
- Requirement tests: blocked sentence names products; any-of satisfaction; all-of across Requirements; T3 tailnet pairing blocked without Tailscale ready.
- Board tests: rows by category, tile per integration, chooser ordering, state re-observed after a Flow, concurrent observation completes even when one integration throws.
- Store tests: per-integration payload round trip, migration of the existing Claude item, forget one leaves the others.
- Tripwires as pure functions: gh's two stderr lines and the deadline message; `tailscale status --json` fields used (`BackendState`, `AuthURL`, `Self.DNSName`, `TailscaleIPs`, `CurrentTailnet.MagicDNSEnabled`); the Serve-not-enabled wording; T3's headless-login URL line and the on-disk credential and marker file names.
- Prior art: `ClaudeLoginReuseTests` (save then silent plant), `ClaudeCodeLoginFlowTests` (scripted dialogue, keep-alive, sweep), `T3SetupFlowTests` and `CreateSpritePlaylistTests` (multi-step flows with auto-respond), `FlowOfferingTests`, `IntegrationRecognitionTests`, `ColdDeepCallTripwireTests`, `InteractiveLoginTests` and `InteractiveT3Tests` (live rigs).

## Out of Scope

- Prepopulate files and run commands (findings recorded; not an Integration; no persistence surface).
- T3 Connect publish-only mode; T3 unlink, including on delete.
- Any logout or revoke Flow, for any integration.
- The app-driven T3 authorization and the token-broker design (recorded in findings; need T3's agreement or a security objection).
- Tailscale via OAuth client, interactive per-Sprite Tailscale login, Tailscale SSH, `--advertise-tags`, any ACL edits.
- New Capability cases, or grouping by anything but the declared category.
- Remembering Board selections across creates; ordering the Board.
- Batching status probes into one exec.
- The `copy` action kind (superseded by long-press on details).
- Codex or other new coding agents (the Requirement list on T3 Code is where they will be added).
- The grant-cap probe against Clerk (user decision: not needed).

## Further Notes

- Facts still to pin in the live rigs, not decisions: gh's `config.yml`-present-`hosts.yml`-absent state (so unplanting, if ever needed, deletes both); the exact failure wording of an expired or revoked Tailscale auth key; Serve certificate provisioning time on the user's tailnet.
- The message to the T3 team drafted in `findings/t3-connect.md` (API-key credential, token-file injection, a client id for provisioners, an authenticated status check, the Claude-derived telemetry identity) should be sent independently of this wave.
- Sprite names become semi-public through T3 Connect (they are the label in the T3 Code list) and through Tailscale (the node hostname).
