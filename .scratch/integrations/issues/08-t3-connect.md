# 08 - T3 Connect

**What to build:** T3 Code offers a second setup Flow, "Set up T3 Code with T3 Connect", first in its chooser. It reuses the shared install and Service-definition steps, asks consent naming the tunnel, the account authorization, what transits T3's relay and where TLS terminates, and the per-Sprite cost of a few taps; runs `t3 connect login --headless` behind open-URL-and-enter-code with stdin held open for the pasted code; then `t3 connect link`, restarts the Service, and waits for the relay-confirmed link. No public-URL consent and no Pairing prompt. The T3 tile shows linked state and mode; the Open in T3 Code action's copy on a linked Sprite says the Sprite is in the T3 Code list under its name. Managed link only; telemetry left at T3's default; no unlink.

**Blocked by:** 02 (Requirement and Category), 03 (Status details).

**Status:** ready-for-agent

- [ ] `t3-setup-connect` Flow with the same Requirement as `t3-setup`, reusing the existing install and Service steps unchanged
- [ ] Consent copy covers tunnel, account, relay contents (control plane only; titles transit and reach APNs; TLS ends at Cloudflare's edge on T3's zone) and the per-Sprite cost
- [ ] Headless login step: non-TTY exec, URL parsed from stdout, `.openURLAndEnterCode`, code written to the session's stdin, success line parsed
- [ ] Link, Service restart, poll for the relay-confirmed marker file with a bounded budget; readiness on the Connect path is that file
- [ ] Observation adds details for authorization present, desired mode, and linked; file probes only
- [ ] The T3 integration orders its Flows Connect, pairing over public URL, (later) pairing over tailnet, Pair again
- [ ] Tests against the fake: flow offering, happy path, declined consent, login exit without success line, link never confirmed, cold-deep-call tripwire, tripwires for the login URL line and the credential/marker file names; a live rig; a findings entry
