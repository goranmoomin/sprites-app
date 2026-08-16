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
/// and the success line `Signed in as <identity>`.
public enum T3ConnectOutputParser {
    public static let urlMarker = "Open this URL"
    public static let signedInMarker = "Signed in as "

    public static func extractAuthorizationURL(from raw: String) -> URL? {
        guard let range = raw.range(of: urlMarker),
            let match = raw[range.upperBound...].firstMatch(of: /https:\/\/\S+/)
        else { return nil }
        return URL(string: String(match.0))
    }

    public static func extractIdentity(from raw: String) -> String? {
        guard let range = raw.range(of: signedInMarker) else { return nil }
        let rest = raw[range.upperBound...].prefix { !$0.isNewline }
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
                + "and no pairing code. T3's relay carries control-plane data only: no thread "
                + "content, files, or terminal output. Project and thread titles do transit and "
                + "reach Apple for notifications, and TLS ends at Cloudflare's edge on T3's zone. "
                + "Every Sprite authorizes itself: expect a few taps in the browser each time.",
            approveTitle: "Continue"))
        guard response == .approved else { throw FlowError.declined }
    }
}

/// `t3 connect login --headless` in a plain non-TTY exec: the URL comes out
/// on stdout, the pasted code goes back over stdin (held open across the
/// browser hop), and `Signed in as` is the success line. `--headless` is
/// mandatory: the default path prints a loopback URL useless on a phone.
struct T3ConnectLoginStep: FlowStep {
    let id = "t3-connect-login"
    let title = "Authorize this Sprite"

    static let loginArgv = [T3CodeIntegration.binaryPath, "connect", "login", "--headless"]

    func run(in context: FlowContext) async throws {
        // Presence-only, like the CLI's own status (which never round-trips).
        if try await context.platform.fileExists(
            on: context.sprite, path: T3CodeIntegration.connectCredentialPath)
        {
            context.output("A T3 Connect credential is already present on this Sprite\n")
            return
        }

        let session = try await context.platform.exec(
            on: context.sprite, command: ExecCommand(Self.loginArgv))
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
        var reader = ExecEventReader(session)
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

        let response = await context.prompt(.openURLAndEnterCode(
            url: url,
            instructions: "Sign in to T3, approve the T3 CLI, then copy the code the page shows and "
                + "paste it here."))
        guard case .text(let code) = response else { throw FlowError.declined }

        // The CLI reads the code from stdin. If the socket died during the
        // hop, reattach by identity once; the process holds its prompt.
        let line = Data((code.trimmingCharacters(in: .whitespacesAndNewlines) + "\n").utf8)
        do {
            try await session.send(line)
        } catch {
            guard let sessionID else {
                throw FlowError.failed("The connection dropped during sign-in. Retry to start over.")
            }
            let reattached = try await context.platform.attachExec(on: context.sprite, sessionID: sessionID)
            reader = ExecEventReader(reattached)
            try await reattached.send(line)
        }
        var exitCode: Int?
        while exitCode == nil {
            guard let event = try await reader.next(within: .seconds(120)) else {
                throw FlowError.failed("The sign-in session ended without finishing. Retry to start over.")
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
        guard exitCode == 0, let identity = T3ConnectOutputParser.extractIdentity(from: seen) else {
            throw FlowError.failed(
                "t3 connect login did not sign in (exit status \(exitCode ?? -1)). Check the code and retry.")
        }
        context.output("Authorized as \(identity)\n")
    }
}

/// `t3 connect link` writes only the desired-link secret; provisioning is
/// a startup-only fiber of `t3 serve` (verified in source), so the Service
/// restarts and the relay-confirmed marker file is the readiness.
struct T3ConnectLinkStep: FlowStep {
    let id = "t3-connect-link"
    let title = "Link and restart t3 serve"
    let pollInterval: Duration
    /// Exponential retry on the CLI side runs up to 10 minutes; a healthy
    /// link lands in seconds (3.8s live including the tunnel install), so
    /// the default three minutes is generous without hiding a failure.
    let timeout: Duration

    func run(in context: FlowContext) async throws {
        let link = try await context.platform.runCapturing(
            on: context.sprite, [T3CodeIntegration.binaryPath, "connect", "link"])
        context.output(link.stdoutText + link.stderrText)
        guard link.exitCode == 0 else {
            throw FlowError.failed("t3 connect link exited with status \(link.exitCode).")
        }
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
}
