import Foundation

extension ClaudeCodeIntegration {
    /// The named task Claude's hooks refresh while a prompt is being worked
    /// on, holding the sprite awake.
    public static let heartbeatTaskName = "claude-heartbeat"

    /// The self-expiring task pinning the sprite awake for the login
    /// dialogue, so it cannot decay toward cold during the Safari/Mail hop.
    public static let loginKeepAliveTaskName = "claude-code-login"

    /// Log in the Claude subscription on the sprite with native UI, then
    /// install the Heartbeat hooks. Never shows a terminal (ADR 0002).
    public func loginFlow(urlTimeout: Duration = .seconds(180)) -> Flow {
        Flow(
            id: "claude-code-login",
            title: "Log in Claude Code",
            steps: [
                ClaudeAuthLoginStep(urlTimeout: urlTimeout),
                InstallHeartbeatHooksStep(),
            ]
        )
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

    public static func stripANSI(_ text: String) -> String {
        text
            .replacing(/\u{1b}\][^\u{07}\u{1b}]*(\u{07}|\u{1b}\\)/, with: "")  // OSC
            .replacing(/\u{1b}\[[0-9;?]*[a-zA-Z]/, with: "")  // CSI
            .replacing(/\u{1b}./, with: "")
    }
}

/// Drives `claude auth login` in a headless PTY: extract the OAuth URL,
/// show native step UI, send the pasted code back over the socket, verify.
/// Unlike `setup-token` (which only prints a CI token and saves nothing),
/// `auth login` persists refreshable credentials to the documented store
/// (`~/.claude/.credentials.json` on Linux).
///
/// iOS may suspend the app and kill the WebSocket during the Safari/Mail
/// hop; the PTY survives server-side (observed live), so the step lazily
/// reattaches by identity only when the socket actually died.
struct ClaudeAuthLoginStep: FlowStep {
    let id = "claude-auth-login"
    let title = "Log in to Claude"
    let urlTimeout: Duration

    static let loginArgv = ["claude", "auth", "login", "--claudeai"]
    /// The session list reports resolved path + args (observed live), so
    /// stale-login matching is by this suffix, never argv[0].
    static var loginCommandSuffix: String { loginArgv.joined(separator: " ") }

    func run(in context: FlowContext) async throws {
        try await context.platform.upsertTask(
            on: context.sprite, named: ClaudeCodeIntegration.loginKeepAliveTaskName,
            expiringInSeconds: 15 * 60)
        do {
            try await runDialogue(in: context)
        } catch {
            try? await context.platform.deleteTask(
                on: context.sprite, named: ClaudeCodeIntegration.loginKeepAliveTaskName)
            throw error
        }
        try? await context.platform.deleteTask(
            on: context.sprite, named: ClaudeCodeIntegration.loginKeepAliveTaskName)
    }

    private func runDialogue(in context: FlowContext) async throws {
        // Sweep zombies: an abandoned login PTY outlives its socket forever.
        // Best-effort, and surgical by command suffix.
        if let sessions = try? await context.platform.listExecSessions(on: context.sprite) {
            for stale in sessions where stale.command.hasSuffix(Self.loginCommandSuffix) {
                try? await context.platform.killExecSession(on: context.sprite, sessionID: stale.id)
            }
        }

        // Observed live: the sprite PTY starts with TERM unset and a 0x0
        // size, and claude silently waits forever without them.
        let session = try await context.platform.exec(
            on: context.sprite,
            command: ExecCommand(
                Self.loginArgv, tty: true,
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
                throw FlowError.failed("claude auth login exited early with status \(code)")
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
        // only if it died (ended without an exit: the drop signature).
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
                    // already went in, verification below is the arbiter.
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
                    context.output(String(decoding: data, as: UTF8.self))
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
            throw FlowError.failed("claude auth login exited with status \(exitCode)")
        }

        // Verify the login actually landed: claude's own status probe, plus
        // the documented credential store the detail screen observes. With
        // no observed exit, this is the arbiter.
        let status = try await context.platform.runCapturing(
            on: context.sprite, ["claude", "auth", "status", "--json"])
        context.output(status.stdoutText)
        let loggedIn = (try? JSONSerialization.jsonObject(with: status.stdout))
            .flatMap { $0 as? [String: Any] }
            .flatMap { $0["loggedIn"] as? Bool } ?? false
        guard loggedIn else {
            if exitCode == nil {
                throw FlowError.failed(
                    "The sign-in session ended while you were away and no login was recorded. "
                        + "Retry to start over.")
            }
            throw FlowError.failed("claude auth status does not report a login after the dialogue.")
        }
        guard try await context.platform.fileExists(
            on: context.sprite, path: ClaudeCodeIntegration.credentialsPath)
        else {
            throw FlowError.failed(
                "Logged in, but no credentials at \(ClaudeCodeIntegration.credentialsPath); "
                    + "the detail screen would not observe this login.")
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

        func entry(_ command: String) -> [[String: Any]] {
            [["hooks": [["type": "command", "command": command]]]]
        }
        // SubagentStop deliberately gets no release hook: a subagent can
        // finish while the parent turn keeps working, and releasing there
        // would drop the wake-hold mid-prompt.
        hooks["UserPromptSubmit"] = entry(Self.refreshCommand)
        hooks["PostToolUse"] = entry(Self.refreshCommand)
        hooks["Stop"] = entry(Self.releaseCommand)
        settings["hooks"] = hooks

        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try await context.platform.writeFile(
            on: context.sprite, path: path, content: String(decoding: data, as: UTF8.self))
        context.output("Installed heartbeat hooks into \(path)\n")
    }
}
