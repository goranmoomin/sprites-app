# 07 - Log in to Tailscale

**What to build:** A Tailscale tile in the "other" row. The login Flow installs the pinned static tailscale into the user's bin, defines `tailscaled` as a Service, and joins the tailnet with a reusable auth key. First time: the Flow opens the admin keys page and asks the user to generate a reusable (non-ephemeral) key and paste it, then offers to save it. Every time: the key goes to a 600 file and `tailscale up` runs with `--auth-key=file:`, the Sprite's name as hostname, and the same fixed complete flag set (no `--reset`; the complete-set-of-flags error surfaces verbatim). The tile shows MagicDNS name, tailnet, addresses and Service state; an expired or revoked key is forgotten and re-prompted; the copy says not to checkpoint after joining.

**Blocked by:** 02 (Requirement and Category), 03 (Status details), 04 (SavedLoginStore).

**Status:** resolved

- [x] `TailscaleIntegration` registered, category other, recognizing a `tailscaled` Service by command; offering the login Flow until logged in
- [x] Install resolves the pinned stable version from Tailscale's JSON index and unpacks the static tarball into the user's bin; the Service has no args, the default socket, dir `/home/sprite`
- [x] Prompt reuses `.openURLAndEnterCode` on the admin keys page; save-with-consent as `SavedTailscaleLogin {authKey, savedAt}`; key written to a 600 file, never in argv, file removed after `up`
- [x] `up` uses one fixed complete flag set every run, hostname = Sprite name, and never `--reset`; readiness polled from `status --json` `BackendState`, with `NeedsMachineAuth` shown as waiting for device approval
- [x] Observation: not set up / not running from the Service list alone; one `status --json` only when the Service runs; details MagicDNS name (trailing dot stripped), tailnet, CGNAT-filtered addresses, Service state; JSON parsed, exit code ignored
- [x] Expired/revoked key: the saved key is forgotten and the paste prompt shown again
- [x] Copy: do not checkpoint after joining; the node stays listed in the admin console until removed there
- [x] Tests against the fake: recognition, flow offering, first-time paste then silent plant, flag-set error surfaced, expired-key recovery, observation details, cold-deep-call tripwire, `status --json` field tripwire; a live rig (records the real expired-key wording); a findings entry

## Answer

Done in 6c9dee3. `TailscaleIntegration`/`TailscaleLoginFlow` with the saved reusable auth key over `.openURLAndEnterCode`, static install, `tailscaled` Service, fixed `up` flag set (no `--reset`; flag-set error surfaced verbatim), key-rejection forget-and-reprompt, `status --json` observation only while the Service runs, `Requirement.tailscale`, tripwires, live rig `InteractiveTailscaleTests` (records the unmeasured bad-key wording), findings note.
