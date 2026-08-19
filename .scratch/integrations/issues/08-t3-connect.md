# 08 - T3 Connect

**What to build:** T3 Code offers a second setup Flow, "Set up T3 Code with T3 Connect", first in its chooser. It reuses the shared install and Service-definition steps, asks consent naming the tunnel, the account authorization, what transits T3's relay and where TLS terminates, and the per-Sprite cost of a few taps; runs `t3 connect login --headless` behind open-URL-and-enter-code with stdin held open for the pasted code; then `t3 connect link`, restarts the Service, and waits for the relay-confirmed link. No public-URL consent and no Pairing prompt. The T3 tile shows linked state and mode; the Open in T3 Code action's copy on a linked Sprite says the Sprite is in the T3 Code list under its name. Managed link only; telemetry left at T3's default; no unlink.

**Blocked by:** 02 (Requirement and Category), 03 (Status details).

**Status:** resolved

- [x] `t3-setup-connect` Flow with the same Requirement as `t3-setup`, reusing the existing install and Service steps unchanged
- [x] Consent copy covers tunnel, account, relay contents (control plane only; titles transit and reach APNs; TLS ends at Cloudflare's edge on T3's zone) and the per-Sprite cost
- [x] Headless login step: non-TTY exec, URL parsed from stdout, `.openURLAndEnterCode`, code written to the session's stdin, success line parsed
- [x] Link, Service restart, poll for the relay-confirmed marker file with a bounded budget; readiness on the Connect path is that file
- [x] Observation adds details for authorization present, desired mode, and linked; file probes only
- [x] The T3 integration orders its Flows Connect, pairing over public URL, (later) pairing over tailnet, Pair again
- [x] Tests against the fake: flow offering, happy path, declined consent, login exit without success line, link never confirmed, cold-deep-call tripwire, tripwires for the login URL line and the credential/marker file names; a live rig; a findings entry

## Answer

Done in b1730a2. `t3-setup-connect` first in T3's chooser (Connect, pairing, tailnet, Pair again), consent copy, headless login with stdin code and one reattach, link, Service stop/start, relay marker poll (interval and timeout parameters), `T3 Connect` observation detail from one presence exec, `T3ConnectOutputParser` tripwires, live rig `InteractiveT3ConnectTests`, findings note.

## Comments

2026-08-17: The login as shipped did not complete on device, failing two ways for one reason. The non-TTY exec died with the WebSocket when the browser suspended the app (only TTY sessions outlive their socket; see ADR 0005), so the reattach 404'd and the raw `notFound` reached the failure surface. When the session did outlive the drop, the attach protocol is TTY-framed by construction, so the code went to a non-TTY session without its stdin stream-ID prefix, the CLI never saw it, and the read timed out at `? Authorization code >`. The login now runs in a headless PTY with `TERM=xterm-256color` at 40x120, pinned by a `t3-connect-login` keep-alive task, with a stale-session sweep by argv suffix, the code typed in with Enter as its own keystroke, Claude's two-attempt submission loop, and `cloud-cli-oauth-token.bin` as the arbiter instead of the exit status. Two lines of the checklist above are superseded: "non-TTY exec", and "success line parsed", which is now cosmetic (the file decides, and the parsed identity only names the account in the transcript). The rest stands. Findings entry updated under "Why the login needs a PTY".

2026-08-17: With the login fixed, the same class of failure showed up one step later: `t3 connect link` exited 130, because the first managed link now asks to download the relay client (cloudflared 2026.5.2) through an Effect `Prompt.confirm` that a plain exec cannot answer. This is new since the 2026-08-11 probe, which is why "link is non-interactive" was ever true. `link` now runs in a PTY too and the step answers the confirm, the consent copy names the download, and `cloud-cli-desired-link.bin` is the arbiter because refusing the install still exits 0. The link step also got the treatment the login has: its own keep-alive task for the download, a sweep of abandoned link PTYs by argument suffix (they hold the CLI's install lock), and a kill on every non-terminal outcome. Findings entry: "The relay client, and why link is interactive too".
