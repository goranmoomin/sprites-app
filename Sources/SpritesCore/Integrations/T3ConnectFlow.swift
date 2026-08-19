import Foundation

extension T3CodeIntegration {
    /// T3 Connect's on-disk state (verified in source and live), all under
    /// the default T3 home since the Service passes no `--base-dir`. The
    /// credential rotates on use, so it is never copied or saved: each
    /// Sprite authorizes itself.
    public static let secretsDirectory = "/home/sprite/.t3/userdata/secrets"
    public static let connectCredentialPath = secretsDirectory + "/cloud-cli-oauth-token.bin"
    public static let connectDesiredLinkPath = secretsDirectory + "/cloud-cli-desired-link.bin"
    /// Written by the relay at reconcile, never by the CLI: presence means
    /// LINKED, and is the readiness of the T3 Connect path.
    public static let connectLinkedUserPath = secretsDirectory + "/cloud-linked-user-id.bin"

    /// The self-expiring task pinning the sprite awake while the user is in
    /// the browser signing in to T3. The window past which waiting is
    /// pointless is the code's: it is a Clerk authorization code, and those
    /// live 10 minutes (measured).
    public static let connectLoginKeepAliveTaskName = "t3-connect-login"
    static let connectLoginKeepAliveSeconds = 12 * 60

    /// The same, for the link: nobody is away, but the relay client download
    /// runs for as long as it runs and a backgrounded app must not sleep the
    /// Sprite out from under it.
    public static let connectLinkKeepAliveTaskName = "t3-connect-link"
    static let connectLinkKeepAliveSeconds = 10 * 60

    /// The environment both `t3 connect` PTYs need: the sprite PTY starts
    /// with TERM unset and a 0x0 size, which leaves a prompt with no
    /// terminal to draw on.
    static let connectPTYEnv = ["TERM": "xterm-256color"]

    /// Set up T3 Code through T3 Connect (managed link): the shared install
    /// and Service steps, then authorize this Sprite through the CLI's own
    /// headless login and link it, so it appears in the T3 Code app's list
    /// with no public URL and no visible Pairing.
    public func connectSetupFlow(
        linkPollInterval: Duration = .seconds(2), linkTimeout: Duration = .seconds(180)
    ) -> Flow {
        Flow(
            id: "t3-setup-connect",
            title: "Set up T3 Code with T3 Connect",
            requires: [T3CodeIntegration.supportedCodingAgents],
            steps: [
                InstallT3Step(),
                DefineT3ServiceStep(),
                T3ConnectConsentStep(),
                T3ConnectLoginStep(),
                T3ConnectLinkStep(pollInterval: linkPollInterval, timeout: linkTimeout),
            ]
        )
    }

    /// One exec answering the three presence questions (credential, desired
    /// mode, relay-confirmed link), in the ADR 0001 spirit: files, no
    /// network, and honest wording ("a credential is present", since the
    /// CLI's own status never round-trips).
    static func observeConnect(on sprite: String, platform: SpritesPlatform) async -> IntegrationStatus.Detail? {
        let probe = try? await platform.runCapturing(on: sprite, [
            "sh", "-c",
            "test -e \(connectCredentialPath) && echo authorized; "
                + "cat \(connectDesiredLinkPath) 2>/dev/null && echo; "
                + "test -e \(connectLinkedUserPath) && echo linked; true",
        ])
        guard let probe else { return nil }
        let lines = probe.stdoutText.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.contains("authorized") else { return nil }
        let mode = lines.first { $0 == "managed" || $0 == "publish_only" }
        if lines.contains("linked") {
            return .init("T3 Connect", "linked" + (mode.map { " (\($0))" } ?? ""))
        }
        return .init("T3 Connect", mode == nil ? "authorized" : "authorized, link pending")
    }
}

/// Anchors into `t3 connect login --headless` output (observed live):
///
///     Headless authorization
///     Open this URL on a device with a browser:
///       https://app.t3.codes/connect#state=...&challenge=...
///     ...
///     ? Authorization code >
///
/// and the success line `Signed in as <identity>`, which the CLI colours
/// under a PTY, so both anchors read the visible text. The URL is a hard
/// dependency: a reworded line fails the Flow. The identity is not, since
/// the credential file is the arbiter of the login, so it only names the
/// account in the transcript.
public enum T3ConnectOutputParser {
    public static let urlMarker = "Open this URL"
    public static let signedInMarker = "Signed in as "
    /// `t3 connect link`'s one confirm, raised on the first managed link of
    /// a Sprite (observed live):
    ///
    ///     ? The T3 relay client is required for T3 Connect. Download and
    ///       install version 2026.5.2? > (y/N)
    ///
    /// Anchored on the invariant half of the sentence: the version moves.
    public static let relayClientMarker = "relay client is required"

    public static func asksForRelayClient(_ raw: String) -> Bool {
        stripANSI(raw).contains(relayClientMarker)
    }

    /// The same three replacements as `ClaudeOutputParser.stripANSI`, kept
    /// here so this fix stays inside T3 Connect; the two want unifying.
    static func stripANSI(_ text: String) -> String {
        text
            .replacing(/\u{1b}\][^\u{07}\u{1b}]*(\u{07}|\u{1b}\\)/, with: "")  // OSC
            .replacing(/\u{1b}\[[0-9;?]*[a-zA-Z]/, with: "")  // CSI
            .replacing(/\u{1b}./, with: "")
    }

    public static func extractAuthorizationURL(from raw: String) -> URL? {
        let visible = stripANSI(raw)
        guard let range = visible.range(of: urlMarker),
            let match = visible[range.upperBound...].firstMatch(of: /https:\/\/\S+/)
        else { return nil }
        return URL(string: String(match.0))
    }

    public static func extractIdentity(from raw: String) -> String? {
        let visible = stripANSI(raw)
        guard let range = visible.range(of: signedInMarker) else { return nil }
        let rest = visible[range.upperBound...].prefix { !$0.isNewline }
        let identity = rest.trimmingCharacters(in: .whitespaces)
        return identity.isEmpty ? nil : identity
    }
}

/// The tunnel and the account are never silent: what transits T3's relay,
/// where TLS ends, and the per-Sprite cost, before anything is authorized.
struct T3ConnectConsentStep: FlowStep {
    let id = "t3-connect-consent"
    let title = "Link this Sprite to your T3 account"

    func run(in context: FlowContext) async throws {
        let response = await context.prompt(.consent(
            title: "Link this Sprite to your T3 account?",
            message: "This authorizes T3 Connect for this Sprite and opens a Cloudflare tunnel from "
                + "it to T3's relay, so the Sprite appears in your T3 Code app with no public URL "
                + "and no pairing code. Linking downloads Cloudflare's connector onto the Sprite "
                + "the first time, which the T3 CLI fetches and verifies itself. T3's relay carries "
                + "control-plane data only: no thread "
                + "content, files, or terminal output. Project and thread titles do transit and "
                + "reach Apple for notifications, and TLS ends at Cloudflare's edge on T3's zone. "
                + "Every Sprite authorizes itself: expect a few taps in the browser each time.",
            approveTitle: "Continue"))
        guard response == .approved else { throw FlowError.declined }
    }
}

/// `t3 connect login --headless` in a headless PTY: the URL comes out on
/// stdout, the pasted code goes back as keystrokes, and the credential file
/// is the arbiter of the outcome. `--headless` is mandatory: the default
/// path prints a loopback URL useless on a phone.
///
/// The PTY is for survival, not interaction: iOS suspends the app and kills
/// the WebSocket during the browser hop, and only a TTY session outlives
/// its socket (ADR 0005). The first implementation ran a plain non-TTY exec
/// and lost its process to every hop.
struct T3ConnectLoginStep: FlowStep {
    let id = "t3-connect-login"
    let title = "Authorize this Sprite"

    static let loginArgv = [T3CodeIntegration.binaryPath, "connect", "login", "--headless"]
    /// The session list reports resolved path + args (observed live), and
    /// `t3` is a launcher symlink whose resolved path is not the one we
    /// exec, so stale-login matching is by the arguments alone.
    static var loginCommandSuffix: String { loginArgv.dropFirst().joined(separator: " ") }

    func run(in context: FlowContext) async throws {
        // Presence-only, like the CLI's own status (which never round-trips).
        if try await context.platform.fileExists(
            on: context.sprite, path: T3CodeIntegration.connectCredentialPath)
        {
            context.output("A T3 Connect credential is already present on this Sprite\n")
            return
        }

        try await context.platform.upsertTask(
            on: context.sprite, named: T3CodeIntegration.connectLoginKeepAliveTaskName,
            expiringInSeconds: T3CodeIntegration.connectLoginKeepAliveSeconds)
        do {
            try await authorize(in: context)
        } catch {
            try? await context.platform.deleteTask(
                on: context.sprite, named: T3CodeIntegration.connectLoginKeepAliveTaskName)
            throw error
        }
        try? await context.platform.deleteTask(
            on: context.sprite, named: T3CodeIntegration.connectLoginKeepAliveTaskName)
    }

    private func authorize(in context: FlowContext) async throws {
        // Sweep zombies: an abandoned login PTY outlives its socket forever.
        // Best-effort, and surgical by command suffix.
        if let sessions = try? await context.platform.listExecSessions(on: context.sprite) {
            for stale in sessions where stale.command.hasSuffix(Self.loginCommandSuffix) {
                try? await context.platform.killExecSession(on: context.sprite, sessionID: stale.id)
            }
        }

        let session = try await context.platform.exec(
            on: context.sprite,
            command: ExecCommand(
                Self.loginArgv, tty: true, env: T3CodeIntegration.connectPTYEnv,
                rows: 40, cols: 120))
        let sessionID = await session.sessionID
        do {
            try await drive(session, sessionID: sessionID, in: context)
        } catch {
            await session.cancel()
            if let sessionID {
                try? await context.platform.killExecSession(on: context.sprite, sessionID: sessionID)
            }
            throw error
        }
    }

    private func drive(_ session: any ExecSession, sessionID: String?, in context: FlowContext)
        async throws
    {
        let reader = ExecEventReader(session)

        // Phase 1: the banner and the authorization URL, on the live socket.
        var seen = ""
        var url: URL?
        while url == nil {
            guard let event = try await reader.next(within: .seconds(60)) else {
                throw FlowError.failed("t3 connect login ended before printing the authorization URL.")
            }
            switch event {
            case .stdout(let data), .stderr(let data):
                let text = String(decoding: data, as: UTF8.self)
                seen += text
                context.output(text)
            case .exit(let status):
                throw FlowError.failed("t3 connect login exited early with status \(status)")
            }
            url = T3ConnectOutputParser.extractAuthorizationURL(from: seen)
        }
        guard let url else { return }

        // Phase 2: native step UI while the CLI holds its prompt. No socket
        // is needed while the user is away.
        let response = await context.prompt(.openURLAndEnterCode(
            url: url,
            instructions: "Sign in to T3, approve the T3 CLI, then copy the code the page shows and "
                + "paste it here."))
        guard case .text(let code) = response else { throw FlowError.declined }

        // Phase 3: type the code on the held socket; reattach by identity
        // only if it died (a stream that ended without an exit is the drop
        // signature). Output keeps accumulating into `seen`, and a
        // reattach's scrollback replay preserves the success line.
        var active = session
        var activeReader = reader
        var submitted = false
        var exitCode: Int?
        submission: for attempt in 0..<2 {
            if attempt == 1 {
                guard let sessionID,
                    let reattached = try? await context.platform.attachExec(
                        on: context.sprite, sessionID: sessionID)
                else {
                    // The process ended while the user was away. If a code
                    // already went in, the credential below is the arbiter.
                    if submitted { break submission }
                    throw FlowError.failed(
                        "The sign-in session ended while you were away. Retry to start over.")
                }
                active = reattached
                activeReader = ExecEventReader(reattached)
            }
            do {
                // The CLI prompt (Effect's `Prompt.text`) reads input as key
                // events, so Enter arrives as its own later keystroke rather
                // than a \r the pasted chunk could swallow.
                try await active.send(Data(code.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
                try await Task.sleep(for: .milliseconds(300))
                try await active.send(Data("\r".utf8))
                submitted = true
            } catch {
                continue submission  // dead socket; the next attempt reattaches
            }
            while exitCode == nil {
                let event: ExecEvent?
                do {
                    event = try await activeReader.next(within: .seconds(120))
                } catch {
                    break submission  // silent for two minutes: let the file answer
                }
                guard let event else {
                    continue submission  // stream ended without exit: the drop signature
                }
                switch event {
                case .stdout(let data), .stderr(let data):
                    let text = String(decoding: data, as: UTF8.self)
                    seen += text
                    context.output(text)
                case .exit(let status):
                    exitCode = status
                }
            }
            break submission
        }

        // The credential file is the arbiter, not the exit status: a login
        // whose socket died after the code went in still authorized the
        // Sprite, and only the file says so. Without an exit the CLI may
        // still be exchanging the code, so that case gets a short grace.
        let grace: Duration = exitCode == nil ? .seconds(30) : .zero
        guard try await fileAppears(
            at: T3CodeIntegration.connectCredentialPath, on: context, within: grace,
            every: .seconds(2))
        else {
            if !submitted {
                throw FlowError.failed(
                    "The connection dropped during sign-in before the code could be submitted. "
                        + "Retry to start over.")
            }
            let status = exitCode.map { " (exit status \($0))" } ?? ""
            throw FlowError.failed(
                "t3 connect login did not sign in\(status). Check the code and retry.")
        }
        context.output(
            T3ConnectOutputParser.extractIdentity(from: seen).map { "Authorized as \($0)\n" }
                ?? "Authorized this Sprite for T3 Connect\n")
    }
}

/// Presence of a path, polled only for as long as the caller's grace allows:
/// a zero grace is one probe. Both `t3 connect` steps read their outcome off
/// the Sprite rather than an exit status, and the writes that produce it can
/// outlive our socket.
private func fileAppears(
    at path: String, on context: FlowContext, within grace: Duration, every pollInterval: Duration
) async throws -> Bool {
    let deadline = ContinuousClock.now + grace
    while true {
        if try await context.platform.fileExists(on: context.sprite, path: path) { return true }
        guard ContinuousClock.now < deadline else { return false }
        try await Task.sleep(for: pollInterval)
    }
}

/// `t3 connect link` writes only the desired-link secret; provisioning is
/// a startup-only fiber of `t3 serve` (verified in source), so the Service
/// restarts and the relay-confirmed marker file is the readiness.
///
/// It runs in a PTY because the first managed link on a Sprite asks to
/// download the relay client (cloudflared), and that is an Effect
/// `Prompt.confirm`: under a plain exec it cannot be answered and the CLI
/// cancels with status 130 (observed live). The step answers it, since the
/// consent already covered the tunnel this connector is for.
struct T3ConnectLinkStep: FlowStep {
    let id = "t3-connect-link"
    let title = "Link and restart t3 serve"
    let pollInterval: Duration
    /// Exponential retry on the CLI side runs up to 10 minutes; a healthy
    /// link lands in seconds (3.8s live including the tunnel install), so
    /// the default three minutes is generous without hiding a failure.
    let timeout: Duration

    static let linkArgv = [T3CodeIntegration.binaryPath, "connect", "link"]
    /// The session list reports resolved path + args (observed live), and
    /// `t3` is a launcher symlink whose resolved path is not the one we
    /// exec, so stale-link matching is by the arguments alone.
    static var linkCommandSuffix: String { linkArgv.dropFirst().joined(separator: " ") }

    func run(in context: FlowContext) async throws {
        try await context.platform.upsertTask(
            on: context.sprite, named: T3CodeIntegration.connectLinkKeepAliveTaskName,
            expiringInSeconds: T3CodeIntegration.connectLinkKeepAliveSeconds)
        do {
            try await link(in: context)
        } catch {
            try? await context.platform.deleteTask(
                on: context.sprite, named: T3CodeIntegration.connectLinkKeepAliveTaskName)
            throw error
        }
        try? await context.platform.deleteTask(
            on: context.sprite, named: T3CodeIntegration.connectLinkKeepAliveTaskName)
        try await context.platform.stopService(on: context.sprite, named: T3CodeIntegration.serviceName)
        try await context.platform.startService(on: context.sprite, named: T3CodeIntegration.serviceName)
        context.output("Restarted the t3 service; waiting for the relay to confirm the link\n")
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if try await context.platform.fileExists(
                on: context.sprite, path: T3CodeIntegration.connectLinkedUserPath)
            {
                context.output(
                    "Linked. This Sprite now appears in your T3 Code app as \"\(context.sprite)\"; "
                        + "tap Connect on it there.\n")
                return
            }
            try await Task.sleep(for: pollInterval)
        }
        throw FlowError.failed(
            "The relay did not confirm the link in time. Check the t3 service logs, then retry.")
    }

    /// The link exec, answering the relay-client download when the CLI asks
    /// for it. The desired-link secret is the arbiter: the download can take
    /// minutes, and a socket that dies under it leaves the PTY working.
    private func link(in context: FlowContext) async throws {
        // Sweep zombies: an abandoned link PTY holds the install lock and
        // outlives its socket. Best-effort, and surgical by command suffix.
        if let sessions = try? await context.platform.listExecSessions(on: context.sprite) {
            for stale in sessions where stale.command.hasSuffix(Self.linkCommandSuffix) {
                try? await context.platform.killExecSession(on: context.sprite, sessionID: stale.id)
            }
        }
        let session = try await context.platform.exec(
            on: context.sprite,
            command: ExecCommand(
                Self.linkArgv, tty: true, env: T3CodeIntegration.connectPTYEnv,
                rows: 40, cols: 120))
        let sessionID = await session.sessionID
        do {
            let exitCode = try await drive(session, in: context)
            // The desired-link secret is the arbiter, not the exit status:
            // the CLI exits 0 after "setup cancelled" when the relay client
            // is refused, and a download can outlive our socket.
            guard try await fileAppears(
                at: T3CodeIntegration.connectDesiredLinkPath, on: context,
                within: exitCode == nil ? .seconds(120) : .zero, every: pollInterval)
            else {
                let outcome = exitCode.map { "exited with status \($0)" } ?? "lost its connection"
                throw FlowError.failed("t3 connect link \(outcome) without recording the link.")
            }
        } catch {
            // No terminal outcome may leave a live link PTY behind it.
            await session.cancel()
            if let sessionID {
                try? await context.platform.killExecSession(on: context.sprite, sessionID: sessionID)
            }
            throw error
        }
    }

    /// Reads the link's output to the end, answering the one confirm it can
    /// raise. Returns the exit status, or nil if the socket died first. The
    /// anchor is matched against everything seen, since a PTY read can split
    /// a line anywhere.
    private func drive(_ session: any ExecSession, in context: FlowContext) async throws -> Int? {
        let reader = ExecEventReader(session)
        var seen = ""
        var answered = false
        while true {
            // Each install stage prints as it starts, so silence this long
            // means the download is wedged rather than slow.
            let event: ExecEvent?
            do {
                event = try await reader.next(within: .seconds(120))
            } catch {
                return nil
            }
            guard let event else { return nil }
            switch event {
            case .stdout(let data), .stderr(let data):
                let text = String(decoding: data, as: UTF8.self)
                seen += text
                context.output(text)
                if !answered, T3ConnectOutputParser.asksForRelayClient(seen) {
                    answered = true
                    context.output("Approving the relay client download\n")
                    try await session.send(Data("y".utf8))
                    try await Task.sleep(for: .milliseconds(300))
                    try await session.send(Data("\r".utf8))
                }
            case .exit(let status):
                return status
            }
        }
    }
}
