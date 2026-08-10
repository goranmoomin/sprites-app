import Foundation
import Testing
import SpritesCore

@MainActor
struct ClaudeCodeLoginFlowTests {
    nonisolated static let oauthURL = "https://claude.ai/oauth/authorize?code=true&client_id=abc"

    /// The transcript shape observed on a real sprite: spinner ANSI, then
    /// the sign-in prompt with the OAuth URL, then the masked paste field.
    /// On success `claude auth login` writes the documented credential file
    /// itself, which the script mirrors.
    nonisolated static func scriptHappyClaudeLogin(_ fake: FakeSpritesPlatform, sprite: String = "morning-cherry-1234") async {
        await fake.scriptExec(where: { $0.argv == ["claude", "auth", "login", "--claudeai"] && $0.tty }) { _, io in
            io.stdout("\u{1b}[2J\u{1b}[?25l\u{1b}[38;5;215m*\u{1b}[0m Signing in...\r\n")
            io.stdout(
                "If your browser didn't open, visit: \(oauthURL)\r\n"
                    + "Paste code here if prompted > ")
            guard let code = await io.readLine(), code == "auth-code-42" else {
                io.stdout("Invalid code. Please try again.\r\n")
                io.exit(1)
                return
            }
            await fake.setFile(
                on: sprite,
                path: "/home/sprite/.claude/.credentials.json",
                content: #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-fake"}}"#)
            io.stdout("Login successful.\r\n")
            io.exit(0)
        }
        await scriptAuthStatus(fake, sprite: sprite)
    }

    /// `claude auth status --json` answers from the credential store, like
    /// the real CLI.
    nonisolated static func scriptAuthStatus(_ fake: FakeSpritesPlatform, sprite: String) async {
        await fake.scriptExec(where: { $0.argv == ["claude", "auth", "status", "--json"] }) { _, io in
            let loggedIn = await fake.fileContents(
                on: sprite, path: "/home/sprite/.claude/.credentials.json") != nil
            io.stdout(#"{"loggedIn": "# + (loggedIn ? "true" : "false") + "}\n")
            io.exit(0)
        }
    }

    @Test func loginFlowCompletesAgainstScriptedTranscriptAndInstallsHooks() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        await Self.scriptHappyClaudeLogin(fake)

        let run = FlowRun(
            flow: Integrations.claudeCode.loginFlow(),
            platform: fake, sprite: "morning-cherry-1234")

        // Answer the native step UI (open-URL button, code paste field)
        // as the user would.
        let responder = Task {
            let prompt = await run.nextPrompt()
            guard case .openURLAndEnterCode(let url, _) = prompt else {
                Issue.record("expected openURLAndEnterCode, got \(String(describing: prompt))")
                return
            }
            #expect(url.absoluteString == Self.oauthURL)
            run.respond(.text("auth-code-42"))
        }
        await run.start()
        await responder.value

        #expect(run.phase == .succeeded)

        // Heartbeat hooks were installed into user-level Claude settings.
        let settings = try #require(await fake.fileContents(
            on: "morning-cherry-1234", path: "/home/sprite/.claude/settings.json"))
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(settings.utf8)) as? [String: Any])
        let hooks = try #require(json["hooks"] as? [String: Any])
        for event in ["UserPromptSubmit", "PostToolUse", "Stop"] {
            #expect(hooks[event] != nil, "missing \(event) hook")
        }
        // No release on SubagentStop: it would drop the wake-hold mid-prompt.
        #expect(hooks["SubagentStop"] == nil)
        #expect(settings.contains("sprite-env curl"))
        #expect(settings.contains("claude-heartbeat"))

        // And the detail screen now observes "logged in".
        let detail = SpriteDetailModel(platform: fake, sprite: "morning-cherry-1234")
        await detail.refresh()
        #expect(detail.integrationLines?.first { $0.title == "Claude Code" }?.summary == "logged in")
    }

    /// The sprite base image ships settings.json with its own hooks on the
    /// heartbeat events; the install must append, never clobber them, and
    /// re-running must not stack duplicates.
    @Test func hookInstallPreservesBaseImageHooksAndIsIdempotent() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        let envCheck = "\"$HOME\"/.sprite-shared/hooks/sprite-env-check.sh"
        await fake.setFile(
            on: "morning-cherry-1234", path: "/home/sprite/.claude/settings.json",
            content: """
                {"hooks": {
                    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "\(envCheck.replacing("\"", with: "\\\""))"}]}],
                    "PostToolUse": [{"hooks": [{"type": "command", "command": "\(envCheck.replacing("\"", with: "\\\""))"}]}]
                }}
                """)
        await Self.scriptHappyClaudeLogin(fake)

        func hookGroups() async throws -> [String: [[String: Any]]] {
            let settings = try #require(await fake.fileContents(
                on: "morning-cherry-1234", path: "/home/sprite/.claude/settings.json"))
            let json = try #require(
                try JSONSerialization.jsonObject(with: Data(settings.utf8)) as? [String: Any])
            return try #require(json["hooks"] as? [String: [[String: Any]]])
        }
        func commands(in groups: [[String: Any]]) -> [String] {
            groups.flatMap { group in
                ((group["hooks"] as? [[String: Any]]) ?? []).compactMap { $0["command"] as? String }
            }
        }

        for attempt in 1...2 {
            let run = FlowRun(
                flow: Integrations.claudeCode.loginFlow(),
                platform: fake, sprite: "morning-cherry-1234")
            let responder = Task {
                if await run.nextPrompt() != nil {
                    run.respond(.text("auth-code-42"))
                }
            }
            await run.start()
            await responder.value
            #expect(run.phase == .succeeded)

            let hooks = try await hookGroups()
            for event in ["UserPromptSubmit", "PostToolUse"] {
                let found = commands(in: try #require(hooks[event]))
                #expect(found.contains(envCheck), "attempt \(attempt): base-image hook lost on \(event)")
                #expect(
                    found.filter { $0.contains("claude-heartbeat") }.count == 1,
                    "attempt \(attempt): expected exactly one heartbeat hook on \(event), got \(found)")
            }
            let stop = commands(in: try #require(hooks["Stop"]))
            #expect(stop.filter { $0.contains("claude-heartbeat") }.count == 1)
        }
    }

    @Test func extractsTheOAuthURLFromTheLiveAuthLoginShape() throws {
        // Structure captured live from `claude auth login --claudeai`: a
        // bare URL after the "didn't open, visit:" wording.
        let wanted = "https://claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a"
            + "&scope=org%3Acreate_api_key+user%3Aprofile+user%3Ainference"
        let transcript = "\u{1b}]9999;browser-open;https://claude.com/cai/oauth/authorize?legacy\u{1b}\\"
            + "Opening browser...\r\nIf your browser didn't open, visit: \(wanted)\r\n"
            + "Paste code here if prompted > "

        #expect(ClaudeOutputParser.extractSignInURL(from: transcript)?.absoluteString == wanted)
    }

    @Test func extractsTheOAuthURLFromTheLiveTranscriptShape() throws {
        // Structure captured from a real sprite (claude v2.1.220): the CLI
        // first emits a browser-open OSC with the localhost-callback URL
        // variant, then the marker, then OSC-8 hyperlinks carrying an id
        // param, with the visible URL text wrapped across lines.
        let wanted = "https://claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a"
            + "&response_type=code&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback"
        let transcript = "\u{1b}]9999;browser-open;https://claude.com/cai/oauth/authorize?code=true"
            + "&redirect_uri=http%3A%2F%2Flocalhost%3A39311%2Fcallback\u{1b}\\"
            + "\u{1b}[38;2;153;153;153mBrowser didn't open? Use the url below to sign in (c to copy)\u{1b}[39m\r\n"
            + "\u{1b}]8;id=talicz;\(wanted)\u{1b}\\"
            + "\u{1b}[38;2;153;153;153mhttps://claude.com/cai/oauth/authorize?code=true&client_id=9d\u{1b}[39m\u{1b}]8;;\u{1b}\\\r\n"

        #expect(ClaudeOutputParser.extractSignInURL(from: transcript)?.absoluteString == wanted)
    }

    @Test func rewordedPromptFailsVisiblyWithRawOutput() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        // The CLI reworded its prompt; the anchored parser must not guess.
        await fake.scriptExec(where: { $0.argv.contains("login") }) { _, io in
            io.stdout("Please visit the following address to authenticate:\r\n")
            io.stdout("https://claude.ai/oauth/authorize?code=true\r\n")
            _ = await io.readLine()  // sits waiting, like the real CLI
            io.exit(0)
        }

        let run = FlowRun(
            flow: Integrations.claudeCode.loginFlow(urlTimeout: .milliseconds(200)),
            platform: fake, sprite: "morning-cherry-1234")
        await run.start()

        #expect(run.phase == .failed)
        #expect(run.failureMessage?.contains("sign-in URL") == true)
        // The raw CLI output is the failure surface.
        #expect(run.transcript.contains("Please visit the following address"))
    }

    /// The observed iOS failure: suspension kills the WebSocket during the
    /// Safari/Mail hop. The PTY survives server-side; the step reattaches
    /// by identity, tolerates the scrollback replay, and completes.
    @Test func socketDropDuringTheHopReattachesAndCompletes() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        await fake.scriptExec(where: { $0.argv == ["claude", "auth", "login", "--claudeai"] && $0.tty }) { _, io in
            io.stdout(
                "If your browser didn't open, visit: \(Self.oauthURL)\r\n"
                    + "Paste code here if prompted > ")
            io.dropConnection()  // the app got suspended; the socket died
            guard let code = await io.readLine(), code == "auth-code-42" else {
                io.exit(1)
                return
            }
            await fake.setFile(
                on: "morning-cherry-1234",
                path: "/home/sprite/.claude/.credentials.json",
                content: #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-fake"}}"#)
            io.stdout("Login successful.\r\n")
            io.exit(0)
        }
        await Self.scriptAuthStatus(fake, sprite: "morning-cherry-1234")

        let run = FlowRun(
            flow: Integrations.claudeCode.loginFlow(),
            platform: fake, sprite: "morning-cherry-1234")
        let responder = Task {
            guard await run.nextPrompt() != nil else {
                Issue.record("expected the sign-in prompt")
                return
            }
            // The keep-alive task pins the sprite while the user is away.
            let tasksDuring = (try? await fake.listTasks(on: "morning-cherry-1234")) ?? []
            #expect(tasksDuring.contains { $0.name == ClaudeCodeIntegration.loginKeepAliveTaskName })
            run.respond(.text("auth-code-42"))
        }
        await run.start()
        await responder.value

        #expect(run.phase == .succeeded)
        #expect(await fake.attachLog.count == 1)
        // The keep-alive is released and the login session ended naturally.
        let tasksAfter = (try? await fake.listTasks(on: "morning-cherry-1234")) ?? []
        #expect(!tasksAfter.contains { $0.name == ClaudeCodeIntegration.loginKeepAliveTaskName })
        #expect(try await fake.listExecSessions(on: "morning-cherry-1234").isEmpty)
    }

    /// The tail case: the login process itself died while the user was
    /// away. Reattach fails, and the step reports it honestly instead of a
    /// cryptic exit status.
    @Test func processDeathDuringTheHopFailsCleanly() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        await fake.scriptExec(where: { $0.argv.contains("login") }) { _, io in
            io.stdout(
                "If your browser didn't open, visit: \(Self.oauthURL)\r\n"
                    + "Paste code here if prompted > ")
            io.dropConnection()
            io.exit(1)  // died while the user was off in Mail
        }

        let run = FlowRun(
            flow: Integrations.claudeCode.loginFlow(),
            platform: fake, sprite: "morning-cherry-1234")
        let responder = Task {
            if await run.nextPrompt() != nil {
                run.respond(.text("auth-code-42"))
            }
        }
        await run.start()
        await responder.value

        #expect(run.phase == .failed)
        #expect(run.failureMessage?.contains("while you were away") == true)
        let tasksAfter = (try? await fake.listTasks(on: "morning-cherry-1234")) ?? []
        #expect(!tasksAfter.contains { $0.name == ClaudeCodeIntegration.loginKeepAliveTaskName })
    }

    /// Declining must not leave a live login PTY parked at an OAuth prompt.
    @Test func decliningKillsTheLoginSession() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        await fake.scriptExec(where: { $0.argv.contains("login") }) { _, io in
            io.stdout(
                "If your browser didn't open, visit: \(Self.oauthURL)\r\n"
                    + "Paste code here if prompted > ")
            _ = await io.readLine()
            io.exit(1)
        }

        let run = FlowRun(
            flow: Integrations.claudeCode.loginFlow(),
            platform: fake, sprite: "morning-cherry-1234")
        let responder = Task {
            if await run.nextPrompt() != nil {
                run.respond(.declined)
            }
        }
        await run.start()
        await responder.value

        #expect(run.phase == .cancelled)
        #expect(await fake.killLog.count == 1)
        #expect(try await fake.listExecSessions(on: "morning-cherry-1234").isEmpty)
    }

    /// Starting the flow sweeps zombies from abandoned attempts, so retry is
    /// idempotent from any wreckage state. Surgical: command-suffix match.
    @Test func flowStartSweepsStaleLoginSessions() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        await Self.scriptHappyClaudeLogin(fake)
        // An innocent bystander session the sweep must not touch.
        await fake.scriptExec(where: { $0.argv.first == "sleep" }) { _, io in
            _ = await io.readLine()
            io.exit(0)
        }

        let zombie = try await fake.exec(
            on: "morning-cherry-1234",
            command: ExecCommand(
                ["claude", "auth", "login", "--claudeai"], tty: true,
                env: ["TERM": "xterm-256color"], rows: 40, cols: 120))
        let zombieID = await zombie.sessionID
        await zombie.cancel()  // abandoned: detached but alive
        let bystander = try await fake.exec(
            on: "morning-cherry-1234", command: ExecCommand(["sleep", "600"], tty: true))
        await bystander.cancel()

        let run = FlowRun(
            flow: Integrations.claudeCode.loginFlow(),
            platform: fake, sprite: "morning-cherry-1234")
        let responder = Task {
            if await run.nextPrompt() != nil {
                run.respond(.text("auth-code-42"))
            }
        }
        await run.start()
        await responder.value

        #expect(run.phase == .succeeded)
        #expect(await fake.killLog.map(\.sessionID) == [zombieID])
        // Only the bystander survives: zombie swept, login exited naturally.
        #expect(try await fake.listExecSessions(on: "morning-cherry-1234").map(\.command)
            == ["/usr/bin/sleep 600"])
    }

    @Test func aDerailedStepCanBeRetried() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        let attempts = Counter()
        await fake.scriptExec(where: { $0.argv == ["claude", "auth", "login", "--claudeai"] }) { _, io in
            if await attempts.increment() == 1 {
                io.stdout("Error: could not reach anthropic.com\r\n")
                io.exit(1)
            } else {
                io.stdout(
                    "If your browser didn't open, visit: "
                        + "\u{1b}]8;;\(Self.oauthURL)\u{7}link\u{1b}]8;;\u{7}\r\n")
                guard let _ = await io.readLine() else {
                    io.exit(1)
                    return
                }
                await fake.setFile(
                    on: "morning-cherry-1234",
                    path: "/home/sprite/.claude/.credentials.json", content: "{}")
                io.exit(0)
            }
        }
        await Self.scriptAuthStatus(fake, sprite: "morning-cherry-1234")

        let run = FlowRun(
            flow: Integrations.claudeCode.loginFlow(),
            platform: fake, sprite: "morning-cherry-1234")
        await run.start()

        #expect(run.phase == .failed)
        #expect(run.transcript.contains("could not reach anthropic.com"))

        let responder = Task {
            if await run.nextPrompt() != nil {
                run.respond(.text("any-code"))
            }
        }
        await run.retry()
        await responder.value

        #expect(run.phase == .succeeded)
    }
}

actor Counter {
    private(set) var value = 0
    func increment() -> Int {
        value += 1
        return value
    }
}
