import Foundation

extension ClaudeCodeIntegration {
    /// The named task Claude's hooks refresh while a prompt is being worked
    /// on, holding the sprite awake.
    public static let heartbeatTaskName = "claude-heartbeat"

    /// The self-expiring task pinning the sprite awake for the login
    /// dialogue, so it cannot decay toward cold during the Safari/Mail hop.
    public static let loginKeepAliveTaskName = "claude-code-login"

    /// Log in Claude Code on the sprite: reuse the saved login when one
    /// exists, otherwise mint a setup-token with native UI; then install
    /// the Heartbeat hooks. Never shows a terminal (ADR 0002).
    public func loginFlow(
        urlTimeout: Duration = .seconds(180), verifyTimeout: Duration = .seconds(120)
    ) -> Flow {
        Flow(
            id: "claude-code-login",
            title: "Log in Claude Code",
            steps: [
                ClaudeLoginStep(
                    store: loginStore, urlTimeout: urlTimeout, verifyTimeout: verifyTimeout),
                InstallHeartbeatHooksStep(),
            ]
        )
    }

    /// Merges the token into the env block of user-level Claude settings,
    /// which the CLI reads on every start. T3 drives Claude through the
    /// agent SDK with a pass-through environment by default, so this also
    /// authenticates T3-driven Claude; a custom Claude homePath configured
    /// in T3 sets CLAUDE_CONFIG_DIR and would bypass this file.
    static func plantToken(_ token: String, on sprite: String, platform: SpritesPlatform)
        async throws
    {
        let existing = try await platform.readFile(on: sprite, path: settingsPath) ?? "{}"
        var settings = (try? JSONSerialization.jsonObject(with: Data(existing.utf8)))
            as? [String: Any] ?? [:]
        var env = settings["env"] as? [String: Any] ?? [:]
        env["CLAUDE_CODE_OAUTH_TOKEN"] = token
        settings["env"] = env
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try await platform.writeFile(
            on: sprite, path: settingsPath, content: String(decoding: data, as: UTF8.self))
    }
}

/// Extracts the OAuth URL from claude's PTY output. Anchored on the known
/// prompt wording: a reworded CLI must fail visibly, not silently.
public enum ClaudeOutputParser {
    /// Known prompt wordings observed live: `auth login` says "If your
    /// browser didn't open, visit: <url>"; `setup-token` says "Browser
    /// didn't open? Use the url below to sign in".
    public static let signInMarker = "didn't open"

    public static func extractSignInURL(from raw: String) -> URL? {
        // The marker anchor keeps this from matching the browser-open OSC
        // the CLI emits earlier (whose URL is the localhost-callback
        // variant).
        guard let markerRange = raw.range(of: signInMarker) else { return nil }
        // Prefer an OSC-8 hyperlink after the marker: ESC ] 8 ; params ;
        // URL (BEL | ESC \). Observed live with an id=... param, so params
        // must not be assumed empty.
        if let match = raw[markerRange.upperBound...].firstMatch(of: /\u{1b}\]8;[^;\u{07}\u{1b}]*;(https:[^\u{07}\u{1b}]+)/) {
            return URL(string: String(match.1))
        }
        // Fall back to a bare URL in the visible text after the marker.
        // Untrustworthy for terminal-wrapped URLs, so it only backs up the
        // hyperlink path.
        let visible = stripANSI(raw)
        guard let visibleMarker = visible.range(of: signInMarker) else { return nil }
        if let match = visible[visibleMarker.upperBound...].firstMatch(of: /https:\/\/[^\s)]+/) {
            return URL(string: String(match.0))
        }
        return nil
    }

    /// setup-token prints the minted token under this line (observed live:
    /// "Your OAuth token (valid for 1 year):"). Anchored like the URL
    /// marker: a reworded CLI must fail visibly, not silently.
    public static let mintedTokenMarker = "Your OAuth token"

    /// Observed live: the token renders in an Ink box that wraps it across
    /// screen lines at the box width regardless of PTY cols, so extraction
    /// is line-based: the token starts at its prefix and continuation
    /// lines consisting purely of token characters are joined, until any
    /// other text ("Store this token securely.") ends it.
    public static func extractSetupToken(from raw: String) -> String? {
        let lines = visibleLines(raw)
        guard let markerIndex = lines.firstIndex(where: { $0.contains(mintedTokenMarker) })
        else { return nil }
        for index in markerIndex..<lines.count {
            guard let match = lines[index].firstMatch(of: /sk-ant-oat01-[A-Za-z0-9_-]+/)
            else { continue }
            var token = String(match.0)
            // Wrapped only when the fragment runs to its line's very end.
            guard match.range.upperBound == lines[index].endIndex else { return token }
            for line in lines[(index + 1)...] {
                guard line.wholeMatch(of: /[A-Za-z0-9_-]+/) != nil else { break }
                token += line
            }
            return token
        }
        return nil
    }

    /// Screen lines as a reader would see them. Ink repaints with cursor
    /// movement rather than newlines (observed live), so every escape
    /// sequence except SGR styling is a layout break, never zero-width
    /// glue: deleting them would fuse adjacent screen lines.
    static func visibleLines(_ raw: String) -> [String] {
        raw
            .replacing(/\u{1b}\][^\u{07}\u{1b}]*(\u{07}|\u{1b}\\)/, with: "")  // OSC
            .replacing(/\u{1b}\[[0-9;:<=>?]*m/, with: "")  // SGR styling: zero-width
            .replacing(/\u{1b}\[[0-9;:<=>?]*[ -\/]*[@-~]/, with: "\n")  // CSI movement/erase
            .replacing(/\u{1b}./, with: "\n")  // remaining escapes
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    public static func stripANSI(_ text: String) -> String {
        text
            .replacing(/\u{1b}\][^\u{07}\u{1b}]*(\u{07}|\u{1b}\\)/, with: "")  // OSC
            .replacing(/\u{1b}\[[0-9;?]*[a-zA-Z]/, with: "")  // CSI
            .replacing(/\u{1b}./, with: "")
    }
}

/// The branching login: plants the saved token silently when one exists
/// (no PTY, no browser); otherwise drives `claude setup-token` in a
/// headless PTY: extract the OAuth URL, show native step UI, send the
/// pasted code back over the socket, then parse the minted `sk-ant-oat01-`
/// token out of the output, offer to save it, and plant it into the
/// settings env block. setup-token persists nothing on the sprite itself
/// (observed live), so the token exists only in the PTY output, and the
/// plant is what logs the sprite in. One token fans out to any number of
/// Sprites: it carries no refresh chain, so nothing rotates.
///
/// iOS may suspend the app and kill the WebSocket during the Safari/Mail
/// hop; the PTY survives server-side (observed live), so the step lazily
/// reattaches by identity only when the socket actually died.
struct ClaudeLoginStep: FlowStep {
    let id = "claude-login"
    let title = "Log in to Claude"
    let store: any SavedLoginStore
    let urlTimeout: Duration
    let verifyTimeout: Duration

    static let mintArgv = ["claude", "setup-token"]
    /// The session list reports resolved path + args (observed live), so
    /// stale-login matching is by this suffix, never argv[0].
    static var mintCommandSuffix: String { mintArgv.joined(separator: " ") }
    static let probeArgv = ["claude", "-p", "Reply with exactly: ok"]

    func run(in context: FlowContext) async throws {
        if let saved = store.load(SavedClaudeLogin.self, for: ClaudeCodeIntegration.id) {
            context.output(
                "Using the saved Claude login (saved "
                    + "\(saved.mintedAt.formatted(date: .abbreviated, time: .omitted)))\n")
            try await ClaudeCodeIntegration.plantToken(
                saved.token, on: context.sprite, platform: context.platform)
            context.output("Planted the token into \(ClaudeCodeIntegration.settingsPath)\n")
            // A failed probe means the saved token is dead (revoked or a
            // year old): forget it and fall through to a fresh mint in
            // place, so recovery never leaves the screen.
            if try await verifyIfWanted(in: context) == false {
                store.clear(for: ClaudeCodeIntegration.id)
                context.output(
                    "The saved Claude login no longer works; it has been forgotten. "
                        + "Sign in again to mint a new one.\n")
                try await mint(in: context)
            }
            return
        }
        try await mint(in: context)
    }

    /// The skippable verify: a real inference probe is the only honest
    /// check (`auth status` reports logged in for any planted string).
    /// Returns nil when skipped, false when the token failed the probe. A
    /// hung probe is an infrastructure problem, not a dead credential, so
    /// it fails the step without touching the planted login.
    private func verifyIfWanted(in context: FlowContext) async throws -> Bool? {
        let wanted = await context.prompt(.consent(
            title: "Verify the login?",
            message: "Runs a tiny claude prompt on the Sprite to prove the token works. "
                + "This uses a sliver of your subscription.",
            approveTitle: "Verify"))
        guard wanted == .approved else { return nil }

        let probed = try await withThrowingTaskGroup(of: ExecResult?.self) { group in
            group.addTask {
                try await context.platform.runCapturing(on: context.sprite, Self.probeArgv)
            }
            group.addTask {
                try await Task.sleep(for: verifyTimeout)
                return nil
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
        guard let result = probed else {
            throw FlowError.failed(
                "The verification probe timed out. The login stays planted; retry to verify again.")
        }
        context.output(result.stdoutText + result.stderrText)
        guard result.exitCode == 0 else { return false }
        _ = await context.prompt(.consent(
            title: "Login verified",
            message: "claude replied: "
                + result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines),
            approveTitle: "Continue"))
        return true
    }

    /// The mint branch: the full browser dialogue, pinned awake by the
    /// keep-alive task.
    private func mint(in context: FlowContext) async throws {
        try await context.platform.upsertTask(
            on: context.sprite, named: ClaudeCodeIntegration.loginKeepAliveTaskName,
            expiringInSeconds: 15 * 60)
        do {
            try await runDialogue(in: context)
        } catch {
            await sweepAuthorizeLog(in: context)
            try? await context.platform.deleteTask(
                on: context.sprite, named: ClaudeCodeIntegration.loginKeepAliveTaskName)
            throw error
        }
        await sweepAuthorizeLog(in: context)
        try? await context.platform.deleteTask(
            on: context.sprite, named: ClaudeCodeIntegration.loginKeepAliveTaskName)
    }

    /// The CLI's browser-open attempt leaves the full authorize URL in a
    /// world-readable tmp file, which Checkpoints would capture.
    /// Best-effort, on success and failure paths both.
    private func sweepAuthorizeLog(in context: FlowContext) async {
        _ = try? await context.platform.runCapturing(
            on: context.sprite, ["rm", "-f", ClaudeCodeIntegration.xdgOpenLogPath])
    }

    private func runDialogue(in context: FlowContext) async throws {
        // Sweep zombies: an abandoned login PTY outlives its socket forever.
        // Best-effort, and surgical by command suffix.
        if let sessions = try? await context.platform.listExecSessions(on: context.sprite) {
            for stale in sessions where stale.command.hasSuffix(Self.mintCommandSuffix) {
                try? await context.platform.killExecSession(on: context.sprite, sessionID: stale.id)
            }
        }

        // Observed live: the sprite PTY starts with TERM unset and a 0x0
        // size, and claude silently waits forever without them. 120 cols
        // also keeps the printed token on one unwrapped line.
        let session = try await context.platform.exec(
            on: context.sprite,
            command: ExecCommand(
                Self.mintArgv, tty: true,
                env: ["TERM": "xterm-256color"], rows: 40, cols: 120))
        let sessionID = await session.sessionID
        do {
            try await drive(session, sessionID: sessionID, in: context)
        } catch {
            // No terminal outcome may leak a live login PTY; killing an
            // already-exited session 404s harmlessly.
            await session.cancel()
            if let sessionID {
                try? await context.platform.killExecSession(
                    on: context.sprite, sessionID: sessionID)
            }
            throw error
        }
    }

    private func drive(
        _ session: any ExecSession, sessionID: String?, in context: FlowContext
    ) async throws {
        let reader = ExecEventReader(session)

        // Phase 1: scan PTY output for the sign-in URL. Live-socket only:
        // scrollback replay strips the OSC-8 hyperlink carrying the URL
        // (observed live), so a drop here means starting over.
        var seen = ""
        var url: URL?
        let deadline = ContinuousClock.now + urlTimeout
        scan: while url == nil {
            let remaining = deadline - ContinuousClock.now
            guard remaining > .zero else { break }
            let next: ExecEvent?
            do {
                next = try await reader.next(within: remaining)
            } catch {
                break scan  // no more output in time; fall through to the anchored failure
            }
            guard let event = next else { break }
            switch event {
            case .stdout(let data), .stderr(let data):
                let text = String(decoding: data, as: UTF8.self)
                seen += text
                context.output(text)
            case .exit(let code):
                throw FlowError.failed("claude setup-token exited early with status \(code)")
            }
            url = ClaudeOutputParser.extractSignInURL(from: seen)
        }
        guard let url else {
            throw FlowError.failed(
                "Could not find the sign-in URL in claude's output. The CLI may have changed its prompts.")
        }

        // Phase 2: native step UI. No socket is needed while the user is
        // away; whether the held one survives the hop is phase 3's problem.
        let response = await context.prompt(.openURLAndEnterCode(
            url: url,
            instructions: "Sign in with your Claude subscription, then paste the code shown."))
        guard case .text(let code) = response else {
            throw FlowError.declined
        }

        // Phase 3: submit the code on the held socket; reattach by identity
        // only if it died (ended without an exit: the drop signature). All
        // output keeps accumulating into `seen`: the minted token arrives
        // here, and a reattach's scrollback replay preserves it as visible
        // text (unlike the OSC-8 sign-in URL).
        var active = session
        var activeReader = reader
        var submitted = false
        var exitCode: Int?

        submission: for attempt in 0..<2 {
            if attempt == 1 {
                guard let sessionID else {
                    throw FlowError.failed(
                        "The connection dropped during sign-in and the session announced no "
                            + "identity to reattach by. Retry to start over.")
                }
                do {
                    active = try await context.platform.attachExec(
                        on: context.sprite, sessionID: sessionID)
                } catch {
                    // The process ended while the user was away. If a code
                    // already went in, the token parse below is the arbiter.
                    if submitted { break submission }
                    throw FlowError.failed(
                        "The sign-in session ended while you were away. Retry to start over.")
                }
                activeReader = ExecEventReader(active)
            }
            do {
                // Observed live: Ink treats a rapid input chunk as a paste
                // and swallows a trailing \r into the pasted text, so Enter
                // must arrive as its own later keystroke to submit.
                try await active.send(Data(code.utf8))
                try await Task.sleep(for: .milliseconds(300))
                try await active.send(Data("\r".utf8))
                submitted = true
            } catch {
                continue submission  // dead socket; the next attempt reattaches
            }
            while exitCode == nil {
                guard let event = try await activeReader.next(within: .seconds(120)) else {
                    continue submission  // stream ended without exit: the drop signature
                }
                switch event {
                case .stdout(let data), .stderr(let data):
                    let text = String(decoding: data, as: UTF8.self)
                    seen += text
                    context.output(text)
                case .exit(let code):
                    exitCode = code
                }
            }
            break submission
        }

        if exitCode == nil, !submitted {
            throw FlowError.failed(
                "The connection dropped during sign-in before the code could be submitted. "
                    + "Retry to start over.")
        }
        if let exitCode, exitCode != 0 {
            throw FlowError.failed("claude setup-token exited with status \(exitCode)")
        }

        // The captured token is the arbiter: setup-token persists nothing
        // on the sprite, so missing it means re-running the whole dialogue.
        guard let token = ClaudeOutputParser.extractSetupToken(from: seen) else {
            if exitCode == nil {
                throw FlowError.failed(
                    "The sign-in session ended while you were away and no token was captured. "
                        + "Retry to start over.")
            }
            throw FlowError.failed(
                "Could not find the minted token in claude's output. The CLI may have changed "
                    + "its prompts.")
        }

        // The consent choice: save to the app for reuse on other Sprites,
        // or use here only. Planted on this sprite either way; declining
        // save just means the next sprite mints again.
        var save = false
        switch await context.prompt(.claudeMintedToken(token: token)) {
        case .declined: throw FlowError.declined
        case .approved: save = true
        default: break
        }
        try await ClaudeCodeIntegration.plantToken(
            token, on: context.sprite, platform: context.platform)
        context.output("Planted the token into \(ClaudeCodeIntegration.settingsPath)\n")

        // Mint-branch verify failure only reports; but the save waits for
        // the verify to pass or be skipped, so a token that just failed
        // verification is never the one saved for other Sprites.
        if try await verifyIfWanted(in: context) == false {
            throw FlowError.failed(
                "The minted token failed the verification probe. Retry to mint again.")
        }
        if save {
            store.save(SavedClaudeLogin(token: token, mintedAt: Date()), for: ClaudeCodeIntegration.id)
            context.output("Saved the login for reuse on other Sprites\n")
        }
    }
}

/// Installs the Heartbeat hooks into user-level Claude settings: prompt and
/// tool events refresh a short-expiry named task, stop events delete it.
/// Hooks also cover T3-driven Claude turns.
struct InstallHeartbeatHooksStep: FlowStep {
    let id = "install-heartbeat-hooks"
    let title = "Install Heartbeat hooks"

    // PUT, not POST: observed live, POST 409s once the task exists, so a
    // long prompt's refreshes would never extend the wake-hold.
    static let refreshCommand = "sprite-env curl -s -X PUT -d "
        + #"'{"name":"claude-heartbeat","expire":"5m"}'"#
        + " /v1/tasks/claude-heartbeat"
    static let releaseCommand = "sprite-env curl -s -X DELETE /v1/tasks/claude-heartbeat"

    func run(in context: FlowContext) async throws {
        let path = ClaudeCodeIntegration.settingsPath
        let existing = try await context.platform.readFile(on: context.sprite, path: path) ?? "{}"
        var settings = (try? JSONSerialization.jsonObject(with: Data(existing.utf8)))
            as? [String: Any] ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        // Append, never assign: the base image ships its own hooks on these
        // events, and a login must not destroy them. Idempotent by matching
        // our own command string, so re-running stacks no duplicates.
        func install(_ command: String, on event: String) {
            var groups = hooks[event] as? [[String: Any]] ?? []
            let alreadyInstalled = groups.contains { group in
                ((group["hooks"] as? [[String: Any]]) ?? [])
                    .contains { $0["command"] as? String == command }
            }
            guard !alreadyInstalled else { return }
            groups.append(["hooks": [["type": "command", "command": command]]])
            hooks[event] = groups
        }
        // SubagentStop deliberately gets no release hook: a subagent can
        // finish while the parent turn keeps working, and releasing there
        // would drop the wake-hold mid-prompt.
        install(Self.refreshCommand, on: "UserPromptSubmit")
        install(Self.refreshCommand, on: "PostToolUse")
        install(Self.releaseCommand, on: "Stop")
        settings["hooks"] = hooks

        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try await context.platform.writeFile(
            on: context.sprite, path: path, content: String(decoding: data, as: UTF8.self))
        context.output("Installed heartbeat hooks into \(path)\n")
    }
}
