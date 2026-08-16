# 09 - T3 pairing over the tailnet

**What to build:** T3 Code offers a third setup Flow, "Set up T3 Code over Tailscale", requiring a supported coding agent and Tailscale ready on the Sprite. After the shared prefix it checks MagicDNS and Serve enablement on the tailnet; when either is off it opens the tailnet console page for the user to fix it and re-checks when they come back. Then it serves the local T3 port over HTTPS on the MagicDNS name and creates the Pairing against that URL, with no public-URL consent. Introduces the `.openURL` prompt for web-console preconditions.

**Blocked by:** 02 (Requirement and Category), 07 (Tailscale login). Also blocked on enabling Serve on the user's tailnet once, to measure certificate provisioning time and set the retry budget.

**Status:** resolved

- [x] `t3-setup-tailscale` Flow requiring T3's supported coding agents and Tailscale by id; blocked sentence names Tailscale
- [x] New integration-neutral prompt `.openURL(url, instructions)`, acknowledged
- [x] Precondition steps: MagicDNS from `status --json`, Serve by running `tailscale serve` bounded by a timeout and parsing the not-enabled wording; each prompts `.openURL` with the console page, re-detects on acknowledge, fails with the same prompt on retry
- [x] Pairing created with host `https://<MagicDNS name>/`; no public-URL consent; existing Pairing prompt reused
- [x] Certificate provisioning retry budget set from a live measurement recorded in findings
- [x] Tests against the fake: blocked without Tailscale ready, MagicDNS off path, Serve off path, happy path, cold-deep-call tripwire, not-enabled wording tripwire; a live rig; a findings entry

## Answer

Done in ab8824b. `t3-setup-tailscale` requiring the supported coding agents and `.tailscale`; `.openURL` prompt; `TailnetServeStep` (MagicDNS from status, bounded `tailscale serve`, `TailscaleServeOutputParser` for the enable URL, best-effort certificate warm-up with a provisional budget); `CreatePairingStep(host: .magicDNS)`; live rig `InteractiveT3TailnetTests` to measure certificate provisioning; findings note. Still blocked on enabling Serve on the user's tailnet for the measurement.
