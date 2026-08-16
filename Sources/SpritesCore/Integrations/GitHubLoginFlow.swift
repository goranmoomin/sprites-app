import Foundation

extension GitHubIntegration {
    /// The self-expiring task pinning the sprite awake for the device
    /// flow, which blocks for up to 899 seconds while the user is away.
    public static let loginKeepAliveTaskName = "github-login"

    /// Log in to GitHub on the sprite: plant the saved login when one
    /// exists, otherwise mint one through gh's device flow behind native
    /// UI; either way git can push afterwards and commits are authored as
    /// the user.
    public func loginFlow() -> Flow {
        Flow(
            id: "github-login",
            title: "Log in to GitHub",
            steps: [GitHubLoginStep(store: loginStore)]
        )
    }

    /// The silent plant: two files, `config.yml` first (a hosts file without
    /// it is the hard-failure case), both 600 since `writeFile` lands 644;
    /// then git wiring. Never `GH_TOKEN`: there is nowhere persistent to
    /// put one, and it would mask the file account.
    static func plant(_ login: SavedGitHubLogin, on sprite: String, platform: SpritesPlatform)
        async throws
    {
        try await platform.writeFile(on: sprite, path: configPath, content: "version: \"1\"\n")
        try await platform.writeFile(
            on: sprite, path: hostsPath,
            content: GitHubHostsFile.render(login: login.login, token: login.token))
        _ = try await platform.runCapturing(on: sprite, ["chmod", "600", configPath, hostsPath])
        try await configureGit(login, on: sprite, platform: platform)
    }

    /// `setup-git` is mandatory (a planted token alone leaves git prompting,
    /// observed live), presence-only, and idempotent. The identity is set
    /// only while the base image's "nobody" address is still in place, so
    /// a hand-set identity survives.
    static func configureGit(_ login: SavedGitHubLogin, on sprite: String, platform: SpritesPlatform)
        async throws
    {
        let setup = try await platform.runCapturing(
            on: sprite, ["gh", "auth", "setup-git", "--hostname", "github.com"], env: ghEnv)
        guard setup.exitCode == 0 else {
            throw FlowError.failed("gh auth setup-git failed: " + setup.stderrText)
        }
        let current = try await platform.runCapturing(
            on: sprite, ["git", "config", "--global", "user.email"])
        let email = current.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.isEmpty || email == baseImageEmail else { return }
        _ = try await platform.runCapturing(
            on: sprite, ["git", "config", "--global", "user.name", login.name.isEmpty ? login.login : login.name])
        _ = try await platform.runCapturing(
            on: sprite, ["git", "config", "--global", "user.email", login.noreplyEmail])
    }

    /// gh's update notifier prints to stderr once a day and would pollute
    /// parsed output.
    static let ghEnv = ["GH_NO_UPDATE_NOTIFIER": "1"]
}

/// Anchors into gh's device-flow output (all on stderr, observed live):
///
///     ! First copy your one-time code: 4261-1EFE
///     Open this URL to continue in your web browser: https://github.com/login/device
///
/// Anchored on the literal wordings so a reworded gh fails visibly, not
/// silently. The code alphabet is GitHub's and undocumented, so the rest of
/// the line is taken as-is.
public enum GitHubOutputParser {
    public static let codeMarker = "one-time code: "
    public static let urlMarker = "Open this URL"
    /// What gh prints when the 15-minute device-flow window lapses.
    public static let deadlineMarker = "context deadline exceeded"

    public static func extractDeviceCode(from raw: String) -> String? {
        line(after: codeMarker, in: raw)
    }

    public static func extractDeviceURL(from raw: String) -> URL? {
        guard let line = raw.split(whereSeparator: \.isNewline).first(where: { $0.contains(urlMarker) }),
            let match = line.firstMatch(of: /https:\/\/\S+/)
        else { return nil }
        return URL(string: String(match.0))
    }

    private static func line(after marker: String, in raw: String) -> String? {
        guard let range = raw.range(of: marker) else { return nil }
        let rest = raw[range.upperBound...].prefix { !$0.isNewline }
        let value = rest.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}

/// The branching login: plants the saved login silently when one exists
/// (no browser); otherwise runs `gh auth login --web` as a plain non-TTY
/// exec, shows the one-time code and URL, and waits for gh to exit. gh
/// writes `hosts.yml` itself on success, so `gh auth token` is the arbiter
/// of the outcome, and the token is captured right then or never. The mint
/// cannot run unattended: GitHub demands a scroll-to-bottom and a second
/// factor (observed live), which the copy warns about.
struct GitHubLoginStep: FlowStep {
    let id = "github-login"
    let title = "Log in to GitHub"
    let store: any SavedLoginStore

    static let mintArgv = GitHubIntegration.loginArgv
    /// The session list reports resolved path + args (observed live), so
    /// stale-login matching is by this suffix, never argv[0].
    static var mintCommandSuffix: String { mintArgv.joined(separator: " ") }

    func run(in context: FlowContext) async throws {
        if let saved = store.load(SavedGitHubLogin.self, for: GitHubIntegration.id) {
            context.output("Using the saved GitHub login for \(saved.login)\n")
            try await GitHubIntegration.plant(saved, on: context.sprite, platform: context.platform)
            context.output("Planted the login into \(GitHubIntegration.hostsPath)\n")
            // Verification is free here (a real API round trip): a dead
            // token is forgotten and the flow falls through to a fresh mint
            // in place, so recovery never leaves the screen.
            switch try await verify(in: context) {
            case .loggedIn(let login):
                context.output("GitHub confirms \(login)\n")
                return
            case .badCredentials:
                store.clear(for: GitHubIntegration.id)
                context.output(
                    "The saved GitHub login no longer works; it has been forgotten. "
                        + "Sign in again to mint a new one.\n")
            }
        }
        try await mint(in: context)
    }

    enum Verification {
        case loggedIn(String)
        case badCredentials
    }

    /// `gh api user` round-trips the API for free, so there is no consent
    /// gate, unlike Claude's inference probe. Anything but a clean login
    /// or a 401 reports `gh auth status` verbatim: its wording already says
    /// what is wrong and which source the token came from (a stray
    /// `GH_TOKEN` shows as "(GH_TOKEN)").
    private func verify(in context: FlowContext) async throws -> Verification {
        let user = try await context.platform.runCapturing(
            on: context.sprite, ["gh", "api", "user", "--jq", ".login"], env: GitHubIntegration.ghEnv)
        if user.exitCode == 0 {
            return .loggedIn(user.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if user.stderrText.contains("Bad credentials") || user.stderrText.contains("HTTP 401") {
            return .badCredentials
        }
        let status = try await context.platform.runCapturing(
            on: context.sprite, ["gh", "auth", "status"], env: GitHubIntegration.ghEnv)
        context.output(status.stdoutText + status.stderrText)
        throw FlowError.failed(
            "GitHub did not confirm the login: " + (status.stdoutText + status.stderrText)
                .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The mint branch: the device flow, pinned awake by the keep-alive
    /// task for its whole 15-minute window.
    private func mint(in context: FlowContext) async throws {
        try await context.platform.upsertTask(
            on: context.sprite, named: GitHubIntegration.loginKeepAliveTaskName,
            expiringInSeconds: 16 * 60)
        do {
            try await runDeviceFlow(in: context)
            try await captureAndConfigure(in: context)
        } catch {
            try? await context.platform.deleteTask(
                on: context.sprite, named: GitHubIntegration.loginKeepAliveTaskName)
            throw error
        }
        try? await context.platform.deleteTask(
            on: context.sprite, named: GitHubIntegration.loginKeepAliveTaskName)
    }

    private func runDeviceFlow(in context: FlowContext) async throws {
        // Sweep zombies: an abandoned login polls GitHub for its full
        // window. Best-effort, and surgical by command suffix.
        if let sessions = try? await context.platform.listExecSessions(on: context.sprite) {
            for stale in sessions where stale.command.hasSuffix(Self.mintCommandSuffix) {
                try? await context.platform.killExecSession(on: context.sprite, sessionID: stale.id)
            }
        }
        // Never a PTY: under one gh prompts through a terminal query that
        // hangs headlessly (observed live). Stdin closed, as /dev/null.
        let session = try await context.platform.exec(
            on: context.sprite, command: ExecCommand(Self.mintArgv, env: GitHubIntegration.ghEnv))
        try await session.sendEOF()
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
        var seen = ""
        var code: String?
        var url: URL?
        // Phase 1: the two stderr lines, printed at once before gh blocks.
        while code == nil || url == nil {
            guard let event = try await reader.next(within: .seconds(60)) else {
                throw FlowError.failed("gh auth login ended before printing a code. Retry to start over.")
            }
            switch event {
            case .stdout(let data), .stderr(let data):
                let text = String(decoding: data, as: UTF8.self)
                seen += text
                context.output(text)
            case .exit(let status):
                throw FlowError.failed("gh auth login exited early with status \(status)")
            }
            code = GitHubOutputParser.extractDeviceCode(from: seen)
            url = GitHubOutputParser.extractDeviceURL(from: seen)
        }
        guard let code, let url else { return }

        // Phase 2: native step UI while gh polls underneath.
        let response = await context.prompt(.openURLAndShowCode(
            url: url, code: code,
            instructions: "Open GitHub, enter this code and approve the GitHub CLI. GitHub will "
                + "also ask for a second factor. Come back once it says the device is connected."))
        guard response == .acknowledged else { throw FlowError.declined }

        // Phase 3: wait for gh to exit; it prints nothing until then. If the
        // socket died during the hop, reattach by identity; if the session
        // is already gone, gh's own hosts file is the arbiter.
        var active = reader
        var exitCode: Int?
        attempts: for attempt in 0..<2 {
            if attempt == 1 {
                guard let sessionID,
                    let reattached = try? await context.platform.attachExec(
                        on: context.sprite, sessionID: sessionID)
                else { break attempts }
                active = ExecEventReader(reattached)
            }
            while exitCode == nil {
                guard let event = try await active.next(within: .seconds(16 * 60)) else {
                    continue attempts  // stream ended without exit: the drop signature
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
            break attempts
        }
        if seen.contains(GitHubOutputParser.deadlineMarker) {
            throw FlowError.failed(
                "GitHub's 15-minute window passed before the code was entered. Retry to get a new code.")
        }
        if let exitCode, exitCode != 0 {
            throw FlowError.failed("gh auth login exited with status \(exitCode)")
        }
    }

    /// The token is only ever recoverable via `gh auth token`, right after
    /// the mint or never. Then the account, git wiring, and the save
    /// consent: declining just means the next sprite mints again.
    private func captureAndConfigure(in context: FlowContext) async throws {
        let tokenResult = try await context.platform.runCapturing(
            on: context.sprite, ["gh", "auth", "token"], env: GitHubIntegration.ghEnv)
        guard tokenResult.exitCode == 0 else {
            throw FlowError.failed(
                "The sign-in did not complete on this Sprite (gh holds no token). Retry to start over.")
        }
        let token = tokenResult.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        let userResult = try await context.platform.runCapturing(
            on: context.sprite, ["gh", "api", "user"], env: GitHubIntegration.ghEnv)
        guard userResult.exitCode == 0,
            let user = try? JSONSerialization.jsonObject(with: userResult.stdout) as? [String: Any],
            let login = user["login"] as? String, let id = user["id"] as? Int
        else {
            context.output(userResult.stderrText)
            throw FlowError.failed("gh api user did not return the account. Retry to start over.")
        }
        let saved = SavedGitHubLogin(
            token: token, login: login, name: user["name"] as? String ?? "", id: id,
            scopes: GitHubIntegration.scopes, mintedAt: Date())
        context.output("Logged in to GitHub as \(login)\n")
        try await GitHubIntegration.configureGit(saved, on: context.sprite, platform: context.platform)

        let save = await context.prompt(.consent(
            title: "Save the GitHub login?",
            message: "Saving lets the app log later Sprites in with one tap. The token stays valid "
                + "on every Sprite that uses it and on your other devices; it can only be revoked "
                + "at GitHub, and a Checkpoint restore can bring a login back. Deleting a Sprite "
                + "is how a login leaves it.",
            approveTitle: "Save for other Sprites"))
        if save == .approved {
            store.save(saved, for: GitHubIntegration.id)
            context.output("Saved the login for reuse on other Sprites\n")
        }
    }
}
