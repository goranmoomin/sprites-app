# Claude Code credential persistence and replant

Verified 2026-08-05 with three throwaway sprites (`authprobe1`, `authprobe2`,
`authprobe3`, all destroyed), Claude Code 2.1.220 native install
(`~/.local/share/claude/versions/2.1.220`, GIT_SHA
`4073f59596e272f39393db4f96abc5f4b10eff21`, BUILD_TIME `2026-07-24T22:17:45Z`),
a real `claude auth login --claudeai` on a Max account, byte-offset reads of the
CLI bundle, direct calls to the Anthropic OAuth token endpoint, and
docs.claude.com. Builds on `.scratch/mvp/findings.md` (probe 4 already showed
that hand-written credentials log claude in) and
`.scratch/claude-login-reattach/findings.md` (exec-session and OSC-8 semantics,
not re-tested here).

Headline: one-click replant works. Copying exactly one file,
`~/.claude/.credentials.json`, into a brand-new Sprite makes it fully logged in
with zero OAuth. The catch is that a claude.ai login is a single-holder chain:
any refresh, anywhere, invalidates every other copy of both tokens.

Amended 2026-08-05 23:53 KST, after the probe: independent chains DO coexist.
The operator's pre-existing Mac login (macOS Keychain item
`Claude Code-credentials`, same Max account) was never read or copied by the
probe, and after the whole probe had run its access token still answered HTTP
200 from `https://api.anthropic.com/api/oauth/claude_cli/roles`. So the sprite's
fresh `claude auth login` minted a second, parallel chain and did not supersede
the laptop's. Single-holder applies per chain, not per account. This resolves
the first item under "Unknowns" below, and means the app can safely own a chain
of its own without logging the user out of their laptop. Not established: how
many chains an account may hold at once, or whether old chains are evicted past
some cap.

## Credential storage on Linux

- Store selection is a two-branch function: `zs()` returns the keychain store if
  one was installed, else the `plaintext` store. On Linux nothing installs a
  keychain store, so `.credentials.json` is always the backend. Bundle
  `@249487690` (`function XXn(){...}`, `Q5i={name:"plaintext",...}`,
  `function zs(){if(kFc)return kFc;return Q5i}`).
- Path resolution, bundle `@249484864` and `@247214198`:
  - `fY()` (secure-storage dir) = `process.env.CLAUDE_SECURESTORAGE_CONFIG_DIR`
    if defined (empty string means `~/.claude`), else `fn()`.
  - `fn()` (config dir) = `process.env.CLAUDE_CONFIG_DIR ?? path.join(os.homedir(), ".claude")`, NFC-normalized.
  - credentials file = `path.join(fY(), ".credentials.json")`.
- Write path: `writeFile(path, json, 384)` then `chmod(path, 384)`, i.e. `0600`,
  and the update returns `warning: "Warning: Storing credentials in plaintext."`.
  Docs agree: "On Linux, credentials are stored in `~/.claude/.credentials.json`
  with file mode `0600`" and "If you've set the `CLAUDE_CONFIG_DIR` environment
  variable on Linux or Windows, the `.credentials.json` file lives under that
  directory instead."
- macOS branch, for contrast: `security find-generic-password -a <USER> -w -s
  <service>`, service name from `X6e()` = `` `Claude Code${OAUTH_FILE_SUFFIX}${suffix}${-sha256(configDir).slice(0,8)}` ``
  with the `-credentials` suffix. Irrelevant on a Sprite, but it is why any
  macOS-derived instructions do not transfer.
- Observed file on the Sprite after a real login:
  `-rw------- 1 sprite sprite 509 /home/sprite/.claude/.credentials.json`.
- Exact shape (secrets redacted; both tokens were exactly 108 chars):

```json
{
  "claudeAiOauth": {
    "accessToken": "sk-ant-oat01-<94 more chars>",
    "refreshToken": "sk-ant-ort01-<94 more chars>",
    "expiresAt": 1785956423181,
    "refreshTokenExpiresAt": 1788322307181,
    "scopes": ["user:file_upload", "user:inference", "user:mcp_servers", "user:profile", "user:sessions:claude_code"],
    "subscriptionType": "max",
    "rateLimitTier": "default_claude_max_20x"
  }
}
```

- The writer (`Ver`, bundle `@250365892`) persists exactly
  `{accessToken, refreshToken, expiresAt, refreshTokenExpiresAt, scopes,
  subscriptionType, rateLimitTier, clientId}`. `clientId` is written only for a
  non-default OAuth client and was absent in every file observed here.
- The same file is a multi-credential envelope: the enterprise-gateway path
  writes a sibling top-level key `enterpriseGateway`
  `{url, jwt, expiresAt, idpRefreshToken, tokenEndpoint?}` (bundle `@249489882`).
  Not present on a subscription login.
- `.claude.json` (config, not credentials) resolves as: `<configDir>/.config.json`
  if that file exists, else `${CLAUDE_CONFIG_DIR || os.homedir()}/.claude<oauth-suffix>.json`
  (bundle `@247556099`). On the Sprite it is `/home/sprite/.claude.json`, mode `0600`.
- Sprite base image ships `.claude.json` pre-seeded with `installMethod: "native"`,
  `autoUpdates: false`, `firstStartTime`, `machineID`, `userID`,
  `migrationVersion: 13`. `machineID` and `userID` were byte-identical on two
  independently created sprites, so they are baked into the image and are not a
  per-machine identity.
- No `~/.config/claude*` exists. Claude uses `~/.claude`, `~/.cache/claude`
  (empty `staging/`), `~/.local/state/claude/locks` (refresh lockfiles, nothing
  persisted), `~/.local/share/claude/versions/<v>` (the binary).

## Logged-out vs logged-in diff

Exhaustive recursive listing of `/home/sprite` before and after a single
`claude auth login --claudeai`. Only two files appear:

- `+ -rw------- 509 /home/sprite/.claude/.credentials.json` (new)
- `+ -rw------- 483 /home/sprite/.claude/backups/.claude.json.backup.<epoch-ms>`
  (a pre-write copy of `.claude.json`; the image already shipped one such backup)

No other file, directory, mode, or environment variable changed. In particular:
no new dotfile, no shell profile edit, no keyring, no systemd unit, nothing under
`/etc`.

`.claude.json` gained these top-level keys (previous keys all unchanged,
including `machineID` and `userID`):

- `oauthAccount`: `{accountUuid, emailAddress, organizationUuid,
  hasExtraUsageEnabled, billingType: "stripe_subscription", accountCreatedAt,
  subscriptionCreatedAt, ccOnboardingFlags, claudeCodeTrialEndsAt,
  claudeCodeTrialDurationDays, seatTier, displayName, profileFetchedAt,
  organizationRole: "admin", workspaceRole, organizationName,
  organizationType: "claude_max", organizationRateLimitTier:
  "default_claude_max_20x", userRateLimitTier}`
- `claudeCodeFirstTokenDate`
- `clientDataCacheSlots`, `additionalModelOptionsCache`,
  `additionalModelCostsCache`, `modelAccessCache`, `orgModelDefaultCache`,
  `autoCompactWindowsCache`

After the first inference turn it also grew `cachedGrowthBookFeatures`,
`cachedGrowthBookFeaturesAt`, `cachedExperimentFeatures`, `cachedExperimentData`,
`cachedExtraUsageDisabledReason`, `groveConfigCache`, `passesEligibilityCache`,
and `~/.claude/projects/-home-sprite/<uuid>.jsonl` transcripts plus an empty
`~/.claude/sessions/`. None of that is login state.

## Minimal transferable set: VERIFIED

The minimum is one file: `~/.claude/.credentials.json`. Nothing else.

Exact procedure that worked, source `authprobe1` (logged in interactively),
destination `authprobe2` (created fresh, never logged in, different hostname):

```
sprite file pull -s authprobe1 /home/sprite/.claude/.credentials.json $TMP/creds.json
sprite file push -s authprobe2 $TMP/creds.json /home/sprite/.claude/.credentials.json
```

Result on `authprobe2`, immediately, with no restart and no env var:

- `claude auth status --json` -> `{"loggedIn": true, "authMethod": "claude.ai",
  "apiProvider": "firstParty", "email": null, "orgId": null, "orgName": null,
  "subscriptionType": "max"}`
- `claude -p "say hi in exactly two words"` -> `Hi there`, exit 0.

Notes on the transplant:

- `.claude.json` is not needed and must not be copied. Right after the
  transplant `email`/`orgId`/`orgName` read null because they come from
  `oauthAccount`; the first `claude -p` fetched the profile with the transplanted
  access token and wrote the full `oauthAccount` block itself. A later
  `claude auth status --json` returned the correct email, orgId, orgName.
- Hostnames differed (`authprobe1` vs `authprobe2`) and did not matter. There is
  no machine binding: the token also worked from a Mac via plain curl.
- File mode is not enforced. With the file at `0644`, `claude auth status` still
  reported logged in and `claude -p` still ran. Write `0600` anyway; that is what
  claude itself writes and what the docs promise.
- Minimal hand-written blob, probed field by field with a valid access token:
  - `{accessToken}` alone -> `loggedIn: false`
  - `{accessToken, expiresAt}` -> `loggedIn: false`, `Not logged in - Please run /login`
  - `{accessToken, expiresAt, scopes: ["user:inference"]}` -> `loggedIn: true`,
    inference OK, `subscriptionType: null`
  - `{accessToken, expiresAt, scopes, subscriptionType}` -> `loggedIn: true`,
    full status
  So the required trio is `accessToken` + `expiresAt` + a non-empty `scopes`
  array. `refreshToken`, `refreshTokenExpiresAt`, `subscriptionType`,
  `rateLimitTier`, `clientId` are all optional for logging in. Confirms and
  narrows the probe-4 note in `.scratch/mvp/findings.md`.
- Omitting `refreshToken` yields a login that works until `expiresAt` and then
  dies with no renewal attempt. That is the deliberate choice if the app wants to
  stay the sole owner of the chain (see below).

## Expiry and refresh

- Access token TTL: 28800 s (8 h). Observed both as
  `expiresAt - now` on a fresh login and as `expires_in: 28800` from the token
  endpoint.
- Refresh token TTL: `refresh_token_expires_in: 2394082` s (about 27.7 days),
  stored as absolute `refreshTokenExpiresAt`.
- The CLI treats a token as expired 5 minutes early:
  `function _xe(e){if(e===null)return!1;let t=300000;return Date.now()+t>=e}`
  (bundle `@250330999`).
- Refresh call (bundle `@250327279`, `async function k$e`):
  `POST https://platform.claude.com/v1/oauth/token`,
  `Content-Type: application/json`, timeout 30000 ms, body
  `{grant_type: "refresh_token", refresh_token, client_id, scope: "<space separated>"}`.
  `client_id` defaults to `9d1c250a-e61b-44d9-88ed-5944d1962f5e` (same id seen in
  the live sign-in URL).
- Verified by hand from a Mac. Full response body keys:
  `{token_type: "Bearer", access_token, expires_in: 28800, refresh_token, scope,
  token_uuid, refresh_token_expires_in: 2394082, organization: {uuid, name},
  account: {uuid, email_address}}`.
- Gotcha: with curl's default User-Agent the endpoint answers HTTP 200 with
  `{"error":{"type":"rate_limit_error","message":"Rate limited. Please try again later."}}`
  on the very first call, twice in a row, a minute apart. The identical request
  with `User-Agent: claude-cli/2.1.220 (external, cli)` succeeded immediately.
  Treat a plausible User-Agent as mandatory, and do not read `rate_limit_error`
  from this endpoint as a real rate limit.
- Refresh from a transplanted file works. Forcing `expiresAt` into the past on
  `authprobe2` and running `claude -p` rotated the file in place: new
  `accessToken`, new `refreshToken`, `expiresAt` pushed 8 h out,
  `refreshTokenExpiresAt` reset. Same 509-byte shape.
- Single-holder chain, the decisive finding. Refresh rotates BOTH tokens and
  invalidates the previous pair immediately. Two independent observations:
  - After `authprobe2` refreshed, `authprobe1` still held the original pair.
    Forcing expiry there produced
    `Failed to authenticate: OAuth session expired and could not be refreshed`,
    and claude then blanked its own file to
    `{"accessToken": "", "refreshToken": "", "expiresAt": 0, ...}` and reported
    `loggedIn: false`.
  - After an app-side (curl) refresh, the previously issued and not-yet-expired
    access token returned HTTP 401 from
    `https://api.anthropic.com/api/oauth/claude_cli/roles`, and reusing the
    consumed refresh token returned
    `{"error": "invalid_grant", "error_description": "Refresh token not found or invalid"}`.
  Consequence: one `claude auth login` chain cannot keep N Sprites logged in.
  Whoever refreshes last wins, everyone else is logged out.
- Failure is destructive: on a failed refresh claude overwrites
  `.credentials.json` with empty strings. There is no "leave the old file alone"
  fallback, so the authoritative copy must never live only on a Sprite.
- Detection surface: `claude auth status --json` prints
  `{loggedIn, authMethod, apiProvider, email, orgId, orgName, subscriptionType}`
  and exits 1 when logged out, 0 when logged in. Observed `authMethod` values:
  `none`, `claude.ai` (file or transplant), `oauth_token` (env var).
- Docs on the same state machine: a warning appears within 3 days of expiry
  (v2.1.203+), `/status` shows a `Login` row reading `Expired - log in again`
  (v2.1.210+), and requests then fail with `Login expired - Please run /login`
  (v2.1.206+).

## Alternatives to file copying

1. `claude setup-token` (docs: authentication.md "Generate a long-lived token").
   One-year OAuth token, printed to the terminal, "It does not save the token
   anywhere". Still requires the same browser authorization hop, so it does not
   remove the manual step: it only makes the resulting token last a year.
   Explicitly inference-only: "It can only make model requests, so it can't
   establish Remote Control sessions or fetch claude.ai connectors." The bundle
   says the same in its own words `@139146722`: "Remote Control requires a
   full-scope login token. Long-lived tokens (from `claude setup-token` or
   CLAUDE_CODE_OAUTH_TOKEN) are limited to inference-only for security reasons."
   Requires Pro/Max/Team/Enterprise.
2. `CLAUDE_CODE_OAUTH_TOKEN`. Verified: exporting the `sk-ant-oat01-` access
   token taken from an interactive login, with no credentials file present, gave
   `{"loggedIn": true, "authMethod": "oauth_token"}` and a working `claude -p`,
   and wrote no file anywhere. Precedence 5 of 6 (docs: "Authentication
   precedence"). Not read in bare mode / `CLAUDE_CODE_SIMPLE=1`. This is the
   cleanest file-free replant: nothing lands on disk, but there is no refresh, so
   it dies at the 8 h mark for a login token (or after a year for a setup-token).
3. `ANTHROPIC_API_KEY`. Precedence 3, sent as `X-Api-Key`. Console billing, not
   the subscription. Docs warn it silently outranks a subscription login once
   approved, and "In non-interactive mode (`-p`), the key is always used when
   present". Wrong tradeoff for our users: they are paying for Max already.
4. `apiKeyHelper` setting. A shell command whose stdout is sent as both
   `X-Api-Key` and `Authorization: Bearer`; re-invoked after 5 minutes or on a
   401; TTL configurable with `CLAUDE_CODE_API_KEY_HELPER_TTL_MS`; failures
   surface as `Your apiKeyHelper script is failing` within three attempts; a
   warning shows if it takes more than 10 s. This is the only documented hook by
   which a Sprite-side script could pull a rotating credential from a service we
   run. It carries an API key, not a subscription OAuth token, so it inherits
   the same billing tradeoff as `ANTHROPIC_API_KEY`.
5. There is no credential helper for the claude.ai OAuth chain. The full helper
   list in the settings schema is `apiKeyHelper`, `awsAuthRefresh`,
   `awsCredentialExport`, `fileSuggestion`, `gcpAuthRefresh`, `otelHeadersHelper`,
   `processWrapper`, `proxyAuthHelper`, `statusLine`, `subagentStatusLine`
   (bundle `@248159733`). `sandbox.credentials.*` in settings is about masking
   credential files inside the sandbox, not about supplying them.
6. `CLAUDE_CONFIG_DIR` / `CLAUDE_SECURESTORAGE_CONFIG_DIR` relocate the store but
   do not change its format. Useful only if we ever want two Agents side by side
   on one Sprite.

Ranking for our use: transplanting `.credentials.json` (with `refreshToken`
stripped) or setting `CLAUDE_CODE_OAUTH_TOKEN` are the two viable one-click
paths, and they carry the same 8 h ceiling. Everything else either needs the
browser hop anyway or switches the user off their subscription.

## Risks and gotchas

- Chain exclusivity is the design constraint, not a detail. Replanting the same
  chain onto a second Sprite works, but the first Sprite dies the moment either
  side refreshes. Any product that shows "Claude Code: logged in" on more than
  one Sprite at once from one login is lying unless each Sprite got its own chain.
- The token blob lands in plaintext on the Sprite filesystem and is therefore
  captured by any Checkpoint taken afterwards. Restoring an old Checkpoint
  restores a stale, probably-invalidated credential.
- `sprite file pull` writes the token to local disk. The app must move these
  bytes in memory (exec + stdin, or the file API streamed), never via a temp
  file, and never into logs.
- Do not transplant `.claude.json`. It carries `machineID`, `userID`,
  `oauthAccount`, GrowthBook/experiment caches, model caches, and on a real
  workstation also per-project history, allowed-tool decisions, `mcpServers`, and
  onboarding flags. Everything login-related in it is self-healed from the token.
- Losing a rotated refresh token is unrecoverable. It happened during this probe:
  one app-side refresh response was not persisted and the entire chain was dead
  within seconds, on every sprite holding it.
- Enterprise `forceLoginMethod` / `forceLoginOrgUUID` managed settings block
  environment credentials outright ("The keys also block sessions authenticated
  by `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, or `apiKeyHelper`"), so an
  env-var strategy is not universal.
- New, useful: the base image sets `BROWSER=/.sprite/bin/sprite-browser`, which
  appends the full OAuth authorize URL to a world-readable `/tmp/xdg-open.log`
  (`START:`, `FOUND_URL:`, `ESCAPE_SENT:` lines with PID/PPID). That is an
  out-of-band way to capture the sign-in URL without OSC-8 parsing. Two caveats:
  the logged URL is the localhost-callback variant
  (`redirect_uri=http://localhost:<port>/callback`), not the paste-code variant
  the PTY prints (`redirect_uri=https://platform.claude.com/oauth/code/callback`),
  and it is a standing leak surface on any Sprite where a login was ever run.
- `claude auth login --claudeai` prints the sign-in URL as bare text wrapped at
  the terminal width, not as an OSC-8 hyperlink (`claude setup-token` is the one
  that uses OSC-8). Re-confirms probe 4 in `.scratch/mvp/findings.md`.
- The requested scope set in the authorize URL includes `org:create_api_key`, but
  the granted `scopes` array came back without it. Do not assume a login can mint
  API keys.

## Unknowns a future ticket must still resolve

- RESOLVED, see the amendment in the header: two independent chains for the same
  account do coexist. Verified read-only against the operator's untouched Mac
  login after the probe (HTTP 200 from
  `https://api.anthropic.com/api/oauth/claude_cli/roles` with its access token,
  `User-Agent: claude-cli/2.1.220 (external, cli)`). Still unknown: the maximum
  number of concurrent chains per account, and whether the oldest is evicted.
  This matters because the app holding its own chain is only safe if it does not
  silently evict the user's laptop login.
- Whether a refreshToken-less blob logs in on a genuinely fresh Sprite. Verified
  on a Sprite that already had an `oauthAccount` cache; the fresh-Sprite
  self-heal was verified separately with a full blob, so the combination is very
  likely fine but is technically untested.
- Whether `CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token` is enough for the
  Flows we care about. Docs say inference-only: no Remote Control, no claude.ai
  connectors. If the Claude Remote Control Integration matters, setup-token is
  disqualified and only a full login chain works.
- Whether `POST https://api.anthropic.com/api/oauth/claude_cli/create_api_key`
  can be used with a login that was granted `org:create_api_key`, which would let
  the app mint a per-Sprite credential instead of sharing one chain. Endpoint
  exists in the bundle; the grant did not include the scope.
- Whether the OAuth authorize step can be made one-tap in the in-app browser when
  the user is already signed in to claude.com (the approval page may still
  require a click).
- Whether the token endpoint's User-Agent gate is stable, and what the real rate
  limit on `/v1/oauth/token` is.

## Sources

- Claude Code CLI bundle, `/home/sprite/.local/share/claude/versions/2.1.220`
  (native, 275012592 bytes). Byte offsets cited above are into that file, read
  with a small python context-window script; they are stable for this exact
  build (GIT_SHA `4073f59596e272f39393db4f96abc5f4b10eff21`).
  - `@249484864` `fY()`, `X6e()` config-dir and keychain-service resolution
  - `@249487690` `XXn()`, plaintext store `Q5i` (read/readAsync/mutate/update/delete), `zs()` store selection
  - `@247214198` `fn = Vr(() => (CLAUDE_CONFIG_DIR ?? join(homedir(), ".claude")).normalize("NFC"))`
  - `@247556099` `.claude.json` / `.config.json` resolution
  - `@250365892` `Ver()`, the persisted `claudeAiOauth` field list
  - `@250327279` `k$e()`, the refresh request and response handling
  - `@250330999` `_xe()`, the 300000 ms expiry skew
  - `@250370500..250374200` refresh lock, CAS-on-sibling-refresh, blanking behavior
  - `@249489882` `enterpriseGateway` refresh (separate credential kind)
  - `@248159733` helper-setting list
  - `@139146722` inference-only limitation of setup-token / CLAUDE_CODE_OAUTH_TOKEN
  - `@179001691` OAuth endpoint and client-id constants
- Live observation on `authprobe1` / `authprobe2` / `authprobe3` (destroyed):
  pre/post-login recursive home snapshots, `claude auth status --json`,
  `claude -p`, field-by-field credential blob probes, forced-expiry refresh,
  cross-sprite invalidation, `0644` mode probe, `/tmp/xdg-open.log`.
- `https://platform.claude.com/v1/oauth/token` called directly with curl
  (refresh grant, response shape, User-Agent gate, `invalid_grant` on a consumed
  refresh token).
- `https://api.anthropic.com/api/oauth/claude_cli/roles` called directly with
  curl (401 for a superseded access token).
- Docs, fetched as raw Markdown (`<page>.md` on docs.claude.com):
  - `https://docs.claude.com/en/docs/claude-code/authentication.md`
    lines 133-141 credential management and storage location; 150-160 renewal and
    expiry states; 166-176 authentication precedence; 181-197 `claude setup-token`.
  - `https://docs.claude.com/en/docs/claude-code/settings.md`
    line 231 `apiKeyHelper`; 423-430 `sandbox.credentials.*`; 285-289
    `forceLoginMethod` / `forceLoginOrgUUID`; 823 keychain vs
    `~/.claude/.credentials.json` for plugin secrets.
  - `https://docs.claude.com/en/docs/claude-code/env-vars.md`
    line 292 `CLAUDE_CODE_OAUTH_TOKEN`; 325 `CLAUDE_CODE_SIMPLE`; 356
    `CLAUDE_CONFIG_DIR`.
  - `https://docs.claude.com/en/docs/claude-code/security.md` line 67.
- Prior repo findings reused, not re-verified: `.scratch/mvp/findings.md`
  (probe 4: `claude auth login --claudeai` writes `~/.claude/.credentials.json`,
  hand-written credentials log claude in, `claude setup-token` persists nothing),
  `.scratch/claude-login-reattach/findings.md` (detached exec sessions, OSC-8
  scrollback loss).

## Proposed ticket sketch

Not a spec, just what a future spec/issue would have to cover, in CONTEXT.md
vocabulary.

Feature: replant a Claude Code Agent onto a new Sprite without the OAuth hop.

- Scope: the Claude Code Integration (coding-agent category) gains a second way
  to produce an Agent on a Sprite. The existing interactive login Flow stays as
  the fallback and as the only way to seed the credential in the first place.
- New Flow: "Reuse existing Claude login". Steps: read the credential the app
  holds, refresh it if within the 5-minute skew, write
  `~/.claude/.credentials.json` (mode `0600`) on the target Sprite, verify with
  `claude auth status --json`. Non-interactive throughout, so no PTY, no
  keep-alive task, no reattach logic. Launchable from the detail screen and
  eligible for the create-Sprite playlist, which is what makes provisioning feel
  one-click.
- What the app stores in the iOS Keychain: the whole `claudeAiOauth` blob
  (`accessToken`, `refreshToken`, `expiresAt`, `refreshTokenExpiresAt`, `scopes`,
  `subscriptionType`, `rateLimitTier`), plus the account email and org name for
  display. The app is the sole owner of the refresh chain. It must persist the
  rotated pair atomically before it uses the new access token anywhere: losing a
  rotated refresh token kills the chain permanently.
- What the app writes on the Sprite: only the trio the CLI needs
  (`accessToken`, `expiresAt`, non-empty `scopes`), with `refreshToken` and
  `refreshTokenExpiresAt` deliberately omitted so the Sprite can never rotate the
  chain out from under the app. Optionally `subscriptionType` and `rateLimitTier`
  for a complete `claude auth status`. Bytes must be streamed, never staged in a
  file on the phone.
- Refresh mechanics for the app: `POST https://platform.claude.com/v1/oauth/token`,
  JSON `{grant_type, refresh_token, client_id, scope}`, with a non-default
  `User-Agent`. Handle `invalid_grant` as "the Integration is signed out, run the
  interactive login Flow again".
- Expiry: a planted credential lives until `expiresAt` OR until the app next
  refreshes the chain, whichever comes first, and 8 h is only the ceiling. A
  refresh revokes the sibling access token immediately, so every app-side
  refresh silently 401s every Sprite planted from the pre-refresh token. Two
  consequences for the design: the app must refresh lazily, at real expiry only,
  never eagerly on launch or on a timer, and every refresh must be followed by a
  re-plant on each live Sprite. The Sprite cannot self-renew by design, so
  the Integration's deep observation must distinguish "logged out" from
  "credential aged out" and offer a one-tap re-plant. Blank strings in the
  credential file (`accessToken: ""`, `expiresAt: 0`) are claude's own
  signed-out marker and should be treated as "never logged in".
- Fan-out is possible after all, if no Sprite ever holds a `refreshToken`. The
  exclusivity is a property of the refresh chain, not of the access token: the
  probe had `authprobe1` and `authprobe2` serving inference off the same tokens
  at the same time, and they only diverged once one of them refreshed. Strip
  `refreshToken` and no Sprite can rotate, so N Sprites can share one access
  token, all die together at the next app-side refresh, and all get re-planted.
  Planting on Sprite B does NOT require a refresh: reuse the current access token
  and Sprite A is untouched. Verified for N=2 with full blobs; the
  access-token-only variant at N>2 is inferred, not tested.
  So the UI does not need to own a single "current Claude Sprite", provided
  re-plant-on-refresh is implemented.
- Out of scope for the first slice: `claude setup-token` (still needs a browser
  hop and is inference-only, so it breaks the Claude Remote Control Integration),
  `ANTHROPIC_API_KEY` and `apiKeyHelper` (switch the user off their
  subscription), and Codex/Gemini Agents (Codex already has documented
  non-interactive login paths, per `.scratch/mvp/findings.md`).
- Security riders: the plaintext token on the Sprite is captured by Checkpoints;
  the Flow should say so once. Sweeping `/tmp/xdg-open.log` after any interactive
  login would remove a standing leak of the authorize URL.
