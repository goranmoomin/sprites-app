# T3 Connect

Account-authorized managed tunnel for the T3 control plane, and the second
way a Sprite can be reached by the T3 Code app (the first being the existing
`t3 serve` plus Pairing).

Evidence from a source read of the T3 Code clone at
`~/Developer/Personal/t3code` (HEAD `a261a6440`), live probes on `probe-t3`
(t3 v0.0.33, 2026-08-11), and a completed login against the user's real T3
account on 2026-08-12. Citations are `file:line` into that clone unless
prefixed with `Sources/`, which means this repo.

## Verdict

Copying one credential to many Sprites is REFUTED, and destructively so. The
credential is a Clerk OAuth pair whose refresh token rotates on use, and
replaying a consumed copy appears to revoke the entire token family - so a
second Sprite refreshing with its stale copy can log out every Sprite and
the original session. This is the opposite of the Claude setup token, which
is safe to fan out precisely because nothing rotates.

So there is no saved login for T3 Connect, and no plant. Each Sprite
authorizes for itself, through the CLI's own `t3 connect login --headless`,
which is cheap to drive: no PTY, one open-URL-and-enter-code prompt, and it
maps onto a `FlowPrompt` case that already exists.

A cleverer design was worked out and set aside: the app could run the OAuth
authorization itself in a web view and plant the result, getting each Sprite
an independent token family for zero to one tap. It is written up under "Set
aside: app-driven authorization" because the evidence took real work and the
decision could be revisited - but it authorizes against T3's own CLI client
id from an app that is not the T3 CLI, and that is not a line to cross
quietly. User decision, 2026-08-12.

Consequence for the wave's vocabulary: T3 Connect is the integration that
has no Saved login, and CONTEXT.md should say so explicitly rather than
leave the absence looking like an omission.

## The shipping design: per-Sprite login through the CLI

`t3 connect login --headless` in a plain non-TTY exec:

```
T3 Connect

Headless authorization
Open this URL on a device with a browser:
  https://app.t3.codes/connect#state=<state>&challenge=<challenge>

After signing in, return here and enter the code shown in your browser.
? Authorization code >
```

It reads the pasted code from stdin and exits 0 with `Signed in as
<identity>`. No PTY is needed - stdin was an ordinary FIFO held open across
the browser hop. It maps onto the existing `FlowPrompt.openURLAndEnterCode`
with no new case.

`--headless` is mandatory. The path selection is a pure
`SSH_CONNECTION`/`SSH_TTY` sniff, and neither is set under our exec, so the
default is the loopback flow whose URL is useless on a phone:

```
https://clerk.t3.codes/oauth/authorize?client_id=hzxSgY2cH10sDU2r&redirect_uri=http%3A%2F%2F127.0.0.1%3A34338%2Fcallback&response_type=code&scope=openid+profile+email&state=...&code_challenge=...&code_challenge_method=S256
```

The browser side, confirmed live: a Clerk modal offering Apple, GitHub,
Google and Microsoft SSO or an email code; then a GitHub OAuth consent for
`T3 Code by Ping.gg` requesting only read-only email and profile; then a
T3-side consent for `T3 CLI`; then a page headed `STEP 2 OF 2 - TERMINAL
HANDOFF` showing a one-time code shaped `<48 uppercase chars>.<the state
from the URL>` with a Copy button. The first segment is genuinely uppercase;
pasting it verbatim worked.

The Flow, then, is roughly: require a coding agent, install t3, define the
`t3 serve` Service, consent to the tunnel and to authorizing a T3 account,
`t3 connect login --headless` behind an `.openURLAndEnterCode` prompt,
`t3 connect link`, restart the Service, poll for `cloud-linked-user-id.bin`.
No public-URL consent and no pairing prompt on the managed path - see "What
Connect changes about the existing T3 integration".

Two mechanical notes for that step. The CLI reads the code from stdin, so
the step needs stdin held open across the browser hop; a FIFO worked in the
probe and an exec session's stdin will do the same. And because this is a
second Flow beside `t3-setup-pairing` rather than a branch inside it -
`Flow` has no conditionals - the two will duplicate their install and
service steps, which is worth noticing before writing them twice.

Cost per Sprite: three to four interactions. Open the URL, sign in or land
already-signed-in, tap Copy, and get the code back into the app. That is the
price of not taking the set-aside design, and it is a real one, so it should
be visible in the flow's copy rather than discovered.

## The credential

Everything lives under `<baseDir>/userdata/secrets/<name>.bin`, mode 0600,
directory 0700. With the app's service definition (no `--base-dir`) that is
`/home/sprite/.t3/userdata/secrets/`.

| File | Meaning |
|---|---|
| `cloud-cli-oauth-token.bin` | THE ACCOUNT CREDENTIAL. `{accessToken, refreshToken, expiresAtEpochMs, identity?}` |
| `cloud-cli-desired-link.bin` | `managed` or `publish_only`. Presence means exposure is enabled. |
| `cloud-linked-user-id.bin` | The account id the relay confirmed. Presence means LINKED. Written by the server at reconcile, never by the CLI. |
| `cloud-relay-url.bin` | The relay origin. Live value `https://relay.t3.codes`. |
| `cloud-relay-environment-credential.bin` | Per-environment bearer minted by the relay at link time. NOT portable, and not the client's credential. |
| `cloud-mint-ed25519-public-key.bin` | Relay's mint public key, used to verify relay-minted client tokens. |
| `cloud-endpoint-runtime-config.bin` | The cloudflared connector token. Managed links only; removed on clean shutdown. |
| `../environment-id` | UUIDv4. Created lazily by any `t3 connect` subcommand. |

Measured on the real credential:

| Field | Observed |
|---|---|
| `accessToken` | 745 chars, JWT |
| `refreshToken` | 48 chars |
| `expiresAtEpochMs` | 24 hours out |
| `identity` | the account email |

It is a bearer JSON blob: no device binding, no machine id, no keyring, no
DPoP. Hand-writing the file authenticates a Sprite - proven live, which is
exactly what makes the rotation result matter rather than being academic.

There is no non-interactive login path. The full `T3CODE_*` surface was
enumerated from source: no `T3CODE_CONNECT_TOKEN` or equivalent. Injection
is exactly one thing, writing the file, which means the app is coupled to an
internal format with no version field and no negotiation.

## The rotation experiment (CONFIRMED)

Run on one Sprite, which is sufficient: the question is only whether a
refresh token survives being used twice.

1. Copied the credential aside as `cred-A`.
2. Forced `expiresAtEpochMs` into the past and ran `t3 connect link`.
   Refresh succeeded (`Authorized as <identity>`, exit 0). Both tokens
   changed: access `f12a71e2bddf` -> `65a564b2647a`, refresh
   `a49903b42778` -> `b3ef32679836`. So refresh tokens DO rotate on use.
   Saved the result as `cred-B`.
3. Restored `cred-A` - the consumed predecessor, i.e. what a second Sprite
   would still be holding - forced expiry, ran `link` again. Refresh FAILED
   and the CLI dropped to a fresh browser authorization. This is the "second
   holder gets logged out" outcome.
4. Control, and the surprise: restored `cred-B`, which had been valid two
   steps earlier, forced expiry, ran `link`. It ALSO failed, and its refresh
   token was left unchanged.

Steps 1-4 are observed. The interpretation - refresh-token reuse detection
revoking the whole family - fits them and is standard OAuth 2.1 practice,
but it is INFERRED and wants one confirmation run from a clean login before
being quoted as fact. The design consequence holds under either reading.

Why it kills fan-out: two Sprites holding one credential are two writers to
one rotating chain. The refresh happens on `getExisting`, which is called by
`authorizeCli`, `unlinkRelayEnvironment`, the startup link reconcile and the
shutdown tunnel release - so every `t3 serve` start is a potential write.
Each Sprite refreshes on its own restart schedule, so the race is
unpredictable in timing as well as outcome.

The failure is also quiet. `authorizeCli` catches
`CloudCliCredentialRefreshError`, prints `The stored T3 Connect credential
could not be refreshed; signing in again.` and continues into a fresh
login; the startup reconcile merely logs a warning and gives up.

Clerk's own lifetimes, for context: access token 1 day (matches our 24-hour
measurement), refresh token 10 years, authorization code 10 minutes.
Rotation, reuse detection and grace windows appear nowhere in Clerk's docs,
Backend API or Frontend API specs, and the OAuth application update body
accepts only `name`, `redirect_uris`, `scopes`, `public`, `pkce_required`
and `consent_screen_enabled`. So T3 cannot turn rotation off - only Clerk
could, and Clerk exposes no knob. There is no feature request to file here,
and equally the behaviour could change without a changelog entry, so no
design should depend on rotation being either present or absent.

## Set aside: app-driven authorization

NOT the shipping design (user decision, 2026-08-12). Recorded because the
source work behind it is real, because it is the only known route to a
genuine one-click T3 Connect, and because two of the asks in "What to ask
the T3 team" exist to make a legitimate version of it possible.

The idea: the rotation hazard comes from copying a credential, not from T3.
Two authorizations against the same client produce two independent grants,
so N Sprites with N authorizations is N independent token families and
nothing interferes. The app runs those authorizations itself, in its own web
view, and plants the results.

Why it is set aside: it authorizes against `hzxSgY2cH10sDU2r`, an OAuth
application registered for the T3 CLI, from an app that is not the T3 CLI.
The consent screen would say "T3 CLI" while the thing being authorized is
Sprites App. That is a misrepresentation to the user however technically
harmless, and it is the kind of thing that breaks the day T3 tightens its
redirect URIs. It would need T3's agreement first, which is ask 3 below.

Every link in the chain below is verified in source, so if that agreement
ever arrives this is ready to build.

- The CLI does the token exchange itself, in-process, with the verifier it
  generated (`CliTokenManager.ts:289-325`). So the app cannot pre-empt the
  CLI's own login: a code minted against the app's challenge is useless to a
  CLI holding a different verifier. The two paths are alternatives, not
  composable - which is fine, because the app does not need the CLI to
  authenticate. It needs the CLI to find a credential on disk.
- There are no client-side bindings. The PKCE verifier lives for one login
  and is never persisted (`CliTokenManager.ts:267-275`); `state` is an
  in-process CSRF check (`connectAuth.ts:101-113`); no nonce is sent, no
  DPoP on the CLI credential, no device id. The environment's own id is
  generated independently and is not part of the token.
- The store is a plain four-field JSON blob with no version and no
  provenance marker (`CliTokenManager.ts:119-124`), written by a bare
  `secrets.set` (`:479-486`). A hand-written file is indistinguishable from
  a CLI-written one, proven live.
- The browser side is not a T3 protocol. It is an ordinary Clerk
  `/oauth/authorize` redirect landing on
  `https://app.t3.codes/connect/callback?code=...&state=...`, and the
  displayed blob is just `code + "." + state` read out of `URLSearchParams`
  (`connectCliAuth.ts:82-91`, `connectAuth.ts:91-93`). The code is in the
  URL, not merely in the DOM, so interception beats scraping and the hosted
  page never has to run.

What the app does, per Sprite:

1. Generate `verifier` (32 random bytes, base64url), `challenge` =
   base64url(SHA-256(verifier)), `state` (16 random bytes). Only S256
   matters; the byte counts do not.
2. Open an authorization URL in a `WKWebView`. Either the hosted entry
   `https://app.t3.codes/connect#state=<state>&challenge=<challenge>`, which
   handles Clerk's sign-in UI for a first-time user, or Clerk directly for a
   `prompt=none` attempt:
   `https://clerk.t3.codes/oauth/authorize?client_id=hzxSgY2cH10sDU2r&redirect_uri=https%3A%2F%2Fapp.t3.codes%2Fconnect%2Fcallback&response_type=code&scope=openid+profile+email&state=<state>&code_challenge=<challenge>&code_challenge_method=S256`
3. Intercept the navigation to `https://app.t3.codes/connect/callback` in
   `decidePolicyFor:navigationAction`, read `code` and `state`, and cancel
   the navigation.
4. `POST https://clerk.t3.codes/oauth/token` with
   `grant_type=authorization_code`, `code`,
   `redirect_uri=https://app.t3.codes/connect/callback`,
   `client_id=hzxSgY2cH10sDU2r`, `code_verifier`. No client secret - the
   instance advertises `token_endpoint_auth_methods_supported: none`.
5. Build the four-field JSON. `identity` comes from the `email` claim of
   `id_token`, then `preferred_username`, then `sub`. It is optional in the
   schema but it is what every `Signed in as ...` line prints, so set it.
6. Write it to `~/.t3/userdata/secrets/cloud-cli-oauth-token.bin` and
   `chmod 600`, since `writeFile` carries no mode
   (`Sources/SpritesCore/Platform/SpritesPlatform.swift:57`).
7. Run `t3 connect link`, restart the `t3` Service, poll for
   `cloud-linked-user-id.bin`.

### How many taps

Zero to one per Sprite after the first.

The hosted `/connect` page costs zero: `ConnectCliAuthorizeSurface` is a
bare effect that calls `window.location.assign(authorizeUrl)` as soon as
`isSignedIn` is true (`ConnectCliAuthSurface.tsx:57-75`). The sign-in button
renders only in the `!isSignedIn` branch. There is no continue button on the
signed-in path.

The remaining screen is Clerk's OAuth consent for "T3 CLI" - and it is
Clerk's, not T3's. Grepping `consent` across `apps`, `packages` and `infra`
in the T3 tree returns nothing; T3 renders no consent UI anywhere. Clerk
controls it with a single per-application boolean, `consent_screen_enabled`,
on by default, with no `trusted` or `first_party` flag in the schema.

Whether Clerk re-shows that screen for an already-granted client is NOT
documented, in either direction, and there is no endpoint to list or delete
a user's consent grants. The strong circumstantial argument that it is
skipped: `prompt=consent` exists specifically to force it, which is only
meaningful if the default does not. That is an inference and it is cheap to
settle - authorize twice in one browser session and count screens.

`prompt=none` is supported per Clerk's Frontend API spec (`enum: [none,
login, consent]`), but `prompt_values_supported` is absent from
`https://clerk.t3.codes/.well-known/openid-configuration`, so the capability
is undiscoverable and must be hard-coded. The spec documents no
`login_required` error shape for authorize either, so the failure shape of a
refused `prompt=none` is unknown and needs a live probe before anything
depends on it. Note the app cannot add `prompt` by using the hosted URL: the
hosted page builds the Clerk URL itself and sets none, so a silent attempt
means going direct to Clerk.

Live metadata for T3's instance, for the record: `grant_types_supported` is
`["authorization_code", "refresh_token"]`; `response_types_supported`
`["code"]`; `code_challenge_methods_supported` `["S256"]`; scopes include
`openid`, `profile`, `email`, `offline_access`. There is no registration
endpoint, so the app cannot register its own client id against T3's Clerk
instance without T3 doing it by hand.

### Web view choice

`WKWebView` with the default persistent store lets the app control
navigation, so interception is trivial and the code never reaches T3's
server. Its cookie jar is separate from Safari's, so the FIRST login is a
real sign-in even if the user is already signed in to `app.t3.codes` in
Safari; subsequent Sprites reuse the web view's session.

`ASWebAuthenticationSession` shares Safari's cookies, so even the first
Sprite might be silent - but it cannot intercept
`https://app.t3.codes/connect/callback`, because the `.https(host:path:)`
callback form needs an associated domain we do not own. A variant worth
probing: use the already-registered loopback redirect
`http://127.0.0.1:34338/callback` and run a listener on that port on the
phone. Unverified whether Clerk's registered redirect set allows arbitrary
loopback ports, and whether iOS lets the in-app Safari view reach the app's
own socket.

### Options considered

Taps count interactions per Sprite after the very first authorization.

| Option | Taps | Needs T3 | Verdict |
|---|---|---|---|
| Per-Sprite `t3 connect login --headless` | 3-4 | No | SHIPPING. The only one that uses nothing but public CLI surface. |
| T3 accepts a Clerk API key | 0 | YES, small | The clean one-click answer. Ask for it. |
| App-driven, visible web view, callback intercepted | 0 or 1 | Agreement on the client id | Set aside |
| App-driven, silent (`prompt=none`), hidden web view | 0 | Agreement on the client id | Set aside; also needs a live probe |
| Same, via loopback listener and `ASWebAuthenticationSession` | 0 or 1 | Agreement on the client id | Set aside |
| App as token broker: one grant, app refreshes, plants a fresh access token before every start | 0 | No | Set aside; smallest blast radius, largest machinery |

The broker option deserves recording because it is the only design where
Sprites never hold a long-lived refresh token. It works because `t3 serve`
runs fine with only an access token and no valid refresh token:
`getExistingNoLock` returns the stored token untouched whenever it is more
than 5 minutes from expiry, and never validates or introspects on that path.
The account token is needed only at `link`/`login`, at every `t3 serve`
startup while a link is desired, at clean shutdown, and at `unlink`/`logout`
- not continuously. Ongoing operation uses the per-environment credential
instead. The relay also accepts any valid access token for the same user,
with no binding to which grant minted it, so one brokered chain can serve
every Sprite. The costs: the app must plant before each start, so a Sprite
restarted by the platform without the app present cannot reconcile; a Sprite
stopping more than 24h after its last plant leaks a Cloudflare tunnel; and
`t3 connect unlink` from inside the Sprite stops working. It converts the
app from a provisioner into a runtime dependency. Keep it in reserve for a
security-review objection.

## What Connect changes about the existing T3 integration

With a MANAGED link the app can drop BOTH `PublicURLConsentStep` and
`CreatePairingStep`. With `--publish-only` it can drop NEITHER.

Managed:

- A public Sprite URL is irrelevant. The link proof is always generated
  against the server's own loopback origin, and the relay rejects a managed
  link whose origin is not loopback. Reachability comes from a named
  Cloudflare tunnel that cloudflared dials out to; nothing listens publicly.
  The app's existing `t3 serve --host 0.0.0.0 --port 3773` definition still
  works unchanged, because the reconcile only reads the bound port.
- A Pairing is still minted, but invisibly. When a client presses Connect,
  the relay signs a mint-request JWT and posts it through the tunnel; the
  environment verifies it and mints an ordinary pairing grant with subject
  `cloud-connect`, a 2-minute TTL and DPoP thumbprint binding, into the same
  store `t3 pair` uses. It is never a 12-character human-typable token and
  never displayed. So `CreatePairingStep` and `FlowPrompt.t3Pairing` become
  unnecessary on this path, and the CONTEXT.md term "Pairing" gains a
  second, invisible variant.
- The user-visible handoff is essentially nothing: the environment appears
  in the T3 Code app's list for anyone signed in to the same account, and
  the user taps Connect on the row. The registration carries only
  `{environmentId, label}` and no URL at all. No URL to copy, no code to
  type, no deep link to open. The app's T3 Action becomes "the sprite is in
  your T3 Code app under `<label>`".
- The tunnel hostname is derived deterministically from
  `sha256("<stage>:<userId>:<environmentId>")`, first 16 hex chars, as
  `<stage>-<16hex>.<zone>`. It is a stable reservation that survives
  restarts even though the tunnel itself is deleted and recreated on each
  stop/start, so the app could display it but never has to hand it over.
- The `label` distinguishing Sprites in that list is the machine hostname,
  falling back to the cwd basename - on a Sprite, the Sprite name. It is the
  only thing telling one Sprite from another in the T3 app, which is good
  for usability and means Sprite names become semi-public.

Publish-only (`link --publish-only`) is a different topology, and the prior
assumption that Connect replaces the public URL and the Pairing does NOT
hold for it:

- It skips the cloudflared install entirely, writes `publish_only`, and
  sends `managedTunnelsEnabled: false` with `providerKind: "manual"`.
- The environment still appears in the client's list, but attaching to it
  FAILS at the relay with `endpoint_provider_not_managed`, surfacing as an
  errored row. The relay deliberately skips the endpoint check for these
  links, commenting that they "are reached out of band (e.g. Tailscale) and
  their stored endpoint is never used for routing".
- So the client still attaches with an ordinary `t3 pair` Pairing to a URL
  the user supplies. The app would KEEP both steps and merely ADD push
  notifications and Live Activities.

That is still a real feature - agent-done pushes on a phone - but it is
additive, not a replacement, and the consent copy must say so. It is also by
far the cheapest Connect flow: no 37 MiB download and no tunnel consent.

## Environment and linking semantics

An environment is one server instance, identified by a UUIDv4 in
`~/.t3/userdata/environment-id`, generated on first need. Nothing is
hostname-, MAC- or machine-id-derived. So five Sprites produce five distinct
environments under one account, not a collision - good for the app's model.

Two collision hazards:

1. A Checkpoint restore or any image cloning copies `environment-id`, and
   two Sprites with the same id fight over one relay record. If the app ever
   bakes t3 into a Checkpoint it must delete that file on restore.
2. Switching accounts on one Sprite is rejected server-side: `This
   environment is already linked to a different cloud account. Unlink it
   before switching accounts.`

`link` REQUIRES a `t3 serve` restart, which settles a prior open question.
`t3 connect link` writes only the desired-link secret; the actual
provisioning is a startup-only fiber with exponential retry up to 10
minutes. There is no watcher and no live endpoint the CLI pokes. The CLI's
own copy says so: `Start T3 to provision the environment link and launch its
managed tunnel.` Readiness is `cloud-linked-user-id.bin` appearing. By
contrast `unlink` does have a live path, via `server-runtime.json`.

Also: on clean shutdown a managed link DELETEs its cloudflared tunnel to
avoid per-tunnel billing, and the next startup provisions a replacement
under the same reserved hostname. So a hard kill of the Service leaks a
tunnel, and the credential must stay valid for the Sprite's whole life
rather than just at setup.

cloudflared itself is cheap: 39,203,902 bytes, 0.589s to download from the
Sprite, checksum matching the pinned constant, landing at
`~/.t3/tools/cloudflared/2026.5.2/linux-x64/cloudflared` mode 0755. The
whole `t3 connect link` including install took 3.8s. It is skippable via
`T3CODE_CLOUDFLARED_PATH`, and `--publish-only` skips it entirely.

## Status and observation

`t3 connect status` logged out, verbatim, exit 0:

```
T3 Connect
  Exposure: disabled
  Authorization: missing
  Environment link: not provisioned
  Relay: not provisioned
  Publish agent activity: disabled
  Relay client: not installed

Next: Run `t3 connect link` to authorize and enable T3 Connect.
```

`--json` gives the same as `{desired, authenticated, linked, cloudUserId,
relayUrl, publishAgentActivity, relayClient{...}}`.

It is presence-only, exactly like `claude auth status`, and it makes no
network call at all. After the token family was revoked it still reported
`"authenticated": true`, because the file is on disk. Any readiness signal
must therefore either do a real round trip or be described honestly as "a
credential is present".

The app has a better option than either, precisely because it did the
exchange itself: at mint time it holds the access token and can round-trip
it once - against the relay's environment list, or Clerk's introspection
endpoint `https://clerk.t3.codes/oauth/token_info` - and record the result.

Cheap file probes, in the ADR-0001 spirit: `cloud-cli-oauth-token.bin`
present means a credential exists; `cloud-linked-user-id.bin` present means
the relay confirmed a link; `cloud-cli-desired-link.bin` tells managed from
publish-only.

## unlink and logout

Both are non-interactive and both exit 0 - including when the server-side
revoke fails. Confirmed live: `t3 connect logout` printed
`CloudCliCredentialRefreshError: Could not refresh the T3 Connect CLI
credential` and still exited 0 with the credential removed, leaving only
`server-signing-key.bin` in the secrets directory. During an earlier probe
the relay `DELETE` 401'd and the exit code was still 0, with only prose and
a WARN line.

So a revoke affordance cannot trust the exit code. It must parse for the
success line and treat "removed locally, NOT revoked remotely" as a
first-class outcome. `logout` deleting the local credential anyway also
strands any retry.

## What transits the relay, and telemetry

This is the material for the consent copy, so it is stated precisely.

The relay is a control plane, not a data plane. Thread content, file
contents, terminal output and agent transcripts do not pass through it: its
entire HTTP surface is health, OAuth metadata, push registration, client
list/link/unlink, DPoP token exchange, client connect/status, and agent
activity publish. There is no proxy or forward endpoint. The data path is
client to Cloudflare edge to cloudflared to the environment's loopback
server, over a named tunnel in T3's own Cloudflare account.

There is no end-to-end encryption anywhere in the tree. What exists is
authentication and integrity - Ed25519 JWT proofs in both directions, DPoP
proof-key binding, nonce/jti replay guards, a 2-minute credential TTL - not
confidentiality. For the consent sentence: TLS terminates at Cloudflare's
edge on a zone in T3's Cloudflare account, so Cloudflare can read the
traffic and T3, as zone owner, could. T3's relay Worker does not receive it.

What the relay stores per linked environment: environment UUID, label, OS,
arch, `serverVersion`, capability flags, endpoint URLs, local host and port,
public key, provider kind, notification and tunnel flags, and
`createdByDeviceId`.

What agent-activity publishing sends: `environmentId`, `threadId`,
`projectTitle`, `threadTitle`, `phase`, `headline`, `detail`, `modelTitle`,
`updatedAt`, `deepLink`. No message text, no file contents, no diffs, no
repo name, no git remote, no cwd, no terminal output. But project titles and
thread titles do transit, and thread titles are usually auto-generated from
the user's first prompt. `detail` is truncated to 160 chars and failure
details are replaced with the literal "The agent run failed." Titles are
also forwarded into APNs payloads, so they reach Apple too, though the
visible alert strings are generic.

Telemetry is on by default, with the PostHog key a literal in the
TypeScript source rather than a build-time define, so it ships in every npm
build. `T3CODE_TELEMETRY_ENABLED=false` disables it. The identity rule
matters to us specifically: the anonymous identifier prefers a SHA-256 of
the `userID` in `~/.claude.json`, so on every Sprite this app sets up -
which by definition has a logged-in coding agent - T3's analytics identity
is derived from the user's Claude account. The relay-path Axiom tracing has
no off switch at all.

## What to ask the T3 team

Ordered by value per unit of their effort.

1. Accept a Clerk API key (`ak_...`) as a Connect credential. These never
   expire by default, never rotate, and are instantly revocable, which is
   the clean fan-out answer and stops Sprites holding refreshable account
   grants. The relay already runs `@clerk/backend` 3.14.0 and calls
   `authenticateRequest` with `acceptsToken: "oauth_token"`; adding
   `"api_key"` is one line, and the relay already accepts two credential
   kinds so a third is an established pattern there. The CLI side needs a
   credential kind it never tries to refresh, which means a `kind`
   discriminator on the persisted token. Costs nothing at our volume: one
   key per user, not one per Sprite.
2. A supported injection interface: `t3 connect login --token-file <path>`
   or `T3CODE_CONNECT_TOKEN`, calling the already-existing store. Add a
   `version` field to the persisted JSON while at it. This turns our plant
   from format coupling into a contract.
3. An OAuth client id, or an approved redirect URI, for third-party
   provisioners - so the consent screen tells the truth. Clerk's dynamic
   client registration is off on T3's instance, so the app cannot register
   itself.
4. A real authenticated status check. `t3 connect status` makes no network
   call, so it reports `authenticated: true` for a dead token family. A
   `--check` flag that round-trips the relay would let every client report
   honestly, not just ours.
5. Consider `consent_screen_enabled: false` for the CLI application, or
   document that Clerk skips consent for an already-granted client. Their
   call, but worth naming so it is a decision rather than an accident.
6. Not worth asking: rotation and reuse-detection windows. Clerk exposes no
   configuration for either, so T3 cannot grant it.

The two privacy disclosures above belong in the same message.

## Open probes

### Gating the shipping design

1. Is there a cap on concurrent grants per user per client? This got MORE
   important, not less, when the app-driven design was set aside: the CLI
   login also produces one grant per Sprite, so N Sprites is N grants either
   way. If Clerk evicts older grants, older Sprites silently stop working -
   the rotation problem again in a new costume, and this time on the path we
   are actually shipping. Undocumented, and absent from Clerk's system-limits
   page. Probe by authorizing three or more Sprites in sequence, then
   exercising the first. This is the single most important open question
   about T3 Connect.
2. What happens to a Sprite's grant when the user signs out of T3 in the
   browser, or revokes at Clerk? Per-Sprite grants should be independent of
   the browser session, but that is unverified, and it decides what the
   destructive-flow copy can honestly promise.
3. One confirmation run of the reuse-detection result, to promote it from
   inference to fact. It no longer gates a design decision - nothing shares
   a chain now - but it is quoted as the reason there is no Saved login, so
   it should be solid before it appears in user-facing copy.
4. How often does the CLI login actually re-prompt? If Clerk keeps a session
   in the user's browser and skips consent for an already-granted client,
   Sprite number two may cost noticeably less than the three-to-four
   interactions budgeted above. Same probe as the consent question below,
   read for a different purpose.

### Gating the set-aside design, if it is ever revisited

5. Does Clerk re-show consent for an already-granted client? The difference
   between zero and one tap. Authorize twice in one browser session and count
   screens.
6. Does `prompt=none` work against `clerk.t3.codes`, and what does refusal
   look like? Probe with a session and without one, and record both exact
   responses. The silent variant is unbuildable until this is pinned.
7. Does the `WKWebView` Clerk session survive app relaunches reliably?
   Measure across a cold launch and a few days. If it does not, every Sprite
   is a full sign-in and the premise fails.
8. Which redirect URIs are registered on T3's Clerk application? We know
   `https://app.t3.codes/connect/callback` and
   `http://127.0.0.1:34338/callback` both work. Whether arbitrary loopback
   ports are allowed decides whether the loopback variant needs a fixed
   port.

### General

9. Why is there a refresh token at all? The CLI requests only
   `openid profile email`, while Clerk documents `offline_access` as the
   scope that grants one. A 48-char refresh token appeared anyway. Harmless,
   but it means our understanding of Clerk's scope handling is incomplete.
