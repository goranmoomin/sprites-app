import Foundation
import Testing
import SpritesCore

/// Log in to GitHub against a scripted gh: the device-flow mint behind the
/// show-code prompt, the free verify, the save consent, and the silent
/// plant on the next sprite.
@MainActor
struct GitHubLoginFlowTests {
    nonisolated static let sprite = "morning-cherry-1234"
    nonisolated static let token = "gho_16C7e42F292c6912E7710c838347Ae178B4a"
    nonisolated static let hostsPath = "/home/sprite/.config/gh/hosts.yml"
    nonisolated static let gitconfigPath = "/home/sprite/.gitconfig"
    nonisolated static let baseGitconfig = "[user]\n\tname = Sprite\n\temail = noreply@sprites.dev\n[init]\n\tdefaultBranch = main\n"

    nonisolated static func loginFlow(store: any SavedLoginStore = InMemorySavedLoginStore()) -> Flow {
        GitHubIntegration(loginStore: store).loginFlow()
    }

    /// gh's terminal probe under a PTY (observed live): the OSC 11
    /// background query and a cursor position report, and nothing prints
    /// until both are answered.
    nonisolated static let terminalQuery = "\u{1b}]11;?\u{1b}\\\u{1b}[6n"

    /// The gh surface the flows touch, answering from the fake's files the
    /// way the real CLI answers from disk: `auth login --web` prints its
    /// two lines (under a PTY only after its terminal queries are answered,
    /// with CRLF), then blocks until the "user" approves (the script
    /// finishes when told to), `auth token` reads hosts.yml, `api user`
    /// answers for a token that is present and not marked dead, `auth
    /// setup-git` appends the credential blocks, and `git config` reads and
    /// writes the fake gitconfig.
    nonisolated static func scriptGh(
        _ fake: FakeSpritesPlatform, sprite: String = sprite, approve: Bool = true,
        deadToken: String? = nil, dropDuringHop: Bool = false
    ) async {
        await fake.setFile(on: sprite, path: gitconfigPath, content: baseGitconfig)
        await fake.scriptExec(where: { $0.argv.starts(with: ["gh", "auth", "login"]) }) { command, io in
            if command.tty {
                io.stdout(terminalQuery)
                var answers = ""
                while !(answers.contains("\u{1b}]11;rgb:") && answers.contains("\u{1b}[1;1R")) {
                    guard let chunk = await io.read() else {
                        io.exit(1)
                        return
                    }
                    answers += chunk
                }
                io.stdout("\r\n! First copy your one-time code: 4261-1EFE\r\n"
                    + "Open this URL to continue in your web browser: https://github.com/login/device\r\n")
            } else {
                io.stderr("\n! First copy your one-time code: 4261-1EFE\n"
                    + "Open this URL to continue in your web browser: https://github.com/login/device\n")
            }
            if dropDuringHop {
                io.dropConnection()  // the app got suspended in Safari; the socket died
            }
            try? await Task.sleep(for: .milliseconds(50))
            if approve {
                await fake.setFile(
                    on: sprite, path: hostsPath,
                    content: GitHubHostsFile.render(login: "goranmoomin", token: token))
                io.exit(0)
            } else {
                io.stderr("failed to authenticate via web browser: context deadline exceeded\n")
                io.exit(1)
            }
        }
        await fake.scriptExec(where: { $0.argv == ["gh", "auth", "token"] }) { _, io in
            if let hosts = await fake.fileContents(on: sprite, path: hostsPath),
                let match = hosts.firstMatch(of: /oauth_token: (\S+)/)
            {
                io.stdout(String(match.1) + "\n")
                io.exit(0)
            } else {
                io.stderr("no oauth token found for github.com\n")
                io.exit(1)
            }
        }
        await fake.scriptExec(where: { $0.argv.starts(with: ["gh", "api", "user"]) }) { command, io in
            guard let hosts = await fake.fileContents(on: sprite, path: hostsPath),
                let match = hosts.firstMatch(of: /oauth_token: (\S+)/)
            else {
                io.stderr("To get started with GitHub CLI, please run: gh auth login\n")
                io.exit(4)
                return
            }
            if String(match.1) == deadToken {
                io.stderr("gh: Bad credentials (HTTP 401)\n{\"message\":\"Bad credentials\"}\n")
                io.exit(1)
                return
            }
            if command.argv.contains("--jq") {
                io.stdout("goranmoomin\n")
            } else {
                io.stdout(#"{"login":"goranmoomin","id":12345,"name":"Sungbin Jo"}"# + "\n")
            }
            io.exit(0)
        }
        await fake.scriptExec(where: { $0.argv.starts(with: ["gh", "auth", "status"]) }) { command, io in
            // Names its source in parentheses: an env token beats the file.
            if let env = command.env["GH_TOKEN"], !env.isEmpty {
                io.stderr("github.com\n  \u{2713} Logged in to github.com account goranmoomin (GH_TOKEN)\n")
                io.exit(0)
            } else if let hosts = await fake.fileContents(on: sprite, path: hostsPath),
                let match = hosts.firstMatch(of: /oauth_token: (\S+)/), String(match.1) != deadToken
            {
                io.stderr("github.com\n  \u{2713} Logged in to github.com account goranmoomin (\(hostsPath))\n")
                io.exit(0)
            } else {
                io.stderr("github.com\n  X Failed to log in to github.com account goranmoomin (\(hostsPath))\n  - The token in \(hostsPath) is invalid.\n")
                io.exit(1)
            }
        }
        await fake.scriptExec(where: { $0.argv.starts(with: ["gh", "auth", "setup-git"]) }) { _, io in
            let current = await fake.fileContents(on: sprite, path: gitconfigPath) ?? ""
            await fake.setFile(
                on: sprite, path: gitconfigPath,
                content: current + "[credential \"https://github.com\"]\n\thelper = \n\thelper = !/.sprite/bin/gh auth git-credential\n")
            io.exit(0)
        }
        await fake.scriptExec(where: { $0.argv.starts(with: ["git", "config", "--global"]) }) { command, io in
            let field = command.argv[3].split(separator: ".").last.map(String.init) ?? command.argv[3]
            let config = await fake.fileContents(on: sprite, path: gitconfigPath) ?? ""
            var lines = config.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let index = lines.firstIndex { $0.hasPrefix("\t\(field) = ") }
            if command.argv.count > 4 {
                let line = "\t\(field) = \(command.argv[4])"
                if let index { lines[index] = line } else { lines.insert(line, at: 1) }
                await fake.setFile(on: sprite, path: gitconfigPath, content: lines.joined(separator: "\n"))
                io.exit(0)
            } else if let index {
                io.stdout(String(lines[index].dropFirst("\t\(field) = ".count)) + "\n")
                io.exit(0)
            } else {
                io.exit(1)
            }
        }
        await fake.scriptExec(where: { $0.argv.first == "chmod" }) { _, io in io.exit(0) }
    }

    /// Answers prompts like a user who approves the device and saves, and
    /// checks the keep-alive pins the sprite while the user is away.
    private func happyResponder(_ run: FlowRun, save: Bool = true, fake: FakeSpritesPlatform? = nil)
        -> Task<[FlowPrompt], Never>
    {
        Task {
            var prompts: [FlowPrompt] = []
            while let prompt = await run.nextPrompt() {
                prompts.append(prompt)
                switch prompt {
                case .openURLAndShowCode:
                    if let fake {
                        let tasks = (try? await fake.listTasks(on: Self.sprite)) ?? []
                        #expect(tasks.contains { $0.name == GitHubIntegration.loginKeepAliveTaskName })
                    }
                    run.respond(.acknowledged)
                case .consent: run.respond(save ? .approved : .declined)
                default: run.respond(.declined)
                }
            }
            return prompts
        }
    }

    @Test func mintShowsTheCodeWaitsForGhAndWiresGit() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await Self.scriptGh(fake)
        let store = InMemorySavedLoginStore()
        let run = FlowRun(flow: Self.loginFlow(store: store), platform: fake, sprite: Self.sprite)

        let responder = happyResponder(run, fake: fake)
        await run.start()
        let prompts = await responder.value

        #expect(run.phase == .succeeded)
        guard case .openURLAndShowCode(let url, let code, _) = prompts.first else {
            Issue.record("expected the show-code prompt first, got \(prompts)")
            return
        }
        #expect(url == URL(string: "https://github.com/login/device"))
        #expect(code == "4261-1EFE")
        // A PTY (the only kind of session that survives the Safari hop),
        // with prompts and colour off and the notifier silenced.
        let login = try #require(await fake.execLog.first { $0.command.argv.contains("login") })
        #expect(login.command.tty == true)
        #expect(login.command.env["GH_NO_UPDATE_NOTIFIER"] == "1")
        #expect(login.command.env["GH_PROMPT_DISABLED"] == "1")
        #expect(login.command.env["NO_COLOR"] == "1")
        #expect(login.command.env["TERM"] == "xterm-256color")
        #expect(login.command.argv.suffix(2) == ["--scopes", "workflow"])
        // git wiring: the helper blocks and the user's own identity.
        let gitconfig = try #require(await fake.fileContents(on: Self.sprite, path: Self.gitconfigPath))
        #expect(gitconfig.contains("gh auth git-credential"))
        #expect(gitconfig.contains("name = Sungbin Jo"))
        #expect(gitconfig.contains("email = 12345+goranmoomin@users.noreply.github.com"))
        // Saved with the account for the next sprite's plant.
        let saved = try #require(store.load(SavedGitHubLogin.self, for: GitHubIntegration.id))
        #expect(saved.token == Self.token)
        #expect(saved.login == "goranmoomin")
        #expect(saved.noreplyEmail == "12345+goranmoomin@users.noreply.github.com")
        // The keep-alive was released.
        #expect(try await fake.listTasks(on: Self.sprite).isEmpty)

        let detail = SpriteDetailModel(platform: fake, sprite: Self.sprite)
        await detail.refresh()
        let line = detail.integrationLines?.first { $0.title == "GitHub" }
        #expect(line?.summary == "logged in")
        #expect(line?.details == [IntegrationStatus.Detail("Account", "goranmoomin")])
    }

    /// The observed iOS failure: leaving for Safari suspends the app and
    /// kills the WebSocket while gh polls. The PTY survives server-side;
    /// the step reattaches by identity and completes.
    @Test func socketDropDuringTheHopReattachesAndCompletes() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await Self.scriptGh(fake, dropDuringHop: true)
        let store = InMemorySavedLoginStore()
        let run = FlowRun(flow: Self.loginFlow(store: store), platform: fake, sprite: Self.sprite)

        let responder = happyResponder(run, fake: fake)
        await run.start()
        _ = await responder.value

        #expect(run.phase == .succeeded, Comment(rawValue: run.failureMessage ?? ""))
        #expect(await fake.attachLog.count == 1)
        #expect(store.load(SavedGitHubLogin.self, for: GitHubIntegration.id)?.token == Self.token)
        // The keep-alive is released and the login session ended naturally.
        #expect(try await fake.listTasks(on: Self.sprite).isEmpty)
        #expect(try await fake.listExecSessions(on: Self.sprite).isEmpty)
    }

    @Test func savedLoginPlantsSilentlyAndVerifiesForFree() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await Self.scriptGh(fake)
        let store = InMemorySavedLoginStore()
        store.save(
            SavedGitHubLogin(
                token: Self.token, login: "goranmoomin", name: "Sungbin Jo", id: 12345,
                scopes: GitHubIntegration.scopes, mintedAt: Date()),
            for: GitHubIntegration.id)
        let run = FlowRun(flow: Self.loginFlow(store: store), platform: fake, sprite: Self.sprite)

        let responder = happyResponder(run)
        await run.start()
        let prompts = await responder.value

        #expect(run.phase == .succeeded)
        #expect(prompts.isEmpty, "the plant branch prompted: \(prompts)")
        #expect(await fake.execLog.allSatisfy { !$0.command.argv.contains("login") })
        // config.yml first, then hosts.yml, both 600.
        #expect(await fake.fileContents(on: Self.sprite, path: "/home/sprite/.config/gh/config.yml") == "version: \"1\"\n")
        let hosts = try #require(await fake.fileContents(on: Self.sprite, path: Self.hostsPath))
        #expect(hosts.contains("oauth_token: \(Self.token)"))
        #expect(hosts.contains("user: goranmoomin"))
        #expect(await fake.execLog.contains { $0.command.argv == ["chmod", "600", "/home/sprite/.config/gh/config.yml", Self.hostsPath] })
        // Verified without any consent gate.
        #expect(await fake.execLog.contains { $0.command.argv == ["gh", "api", "user", "--jq", ".login"] })
        let gitconfig = try #require(await fake.fileContents(on: Self.sprite, path: Self.gitconfigPath))
        #expect(gitconfig.contains("gh auth git-credential"))
        #expect(gitconfig.contains("email = 12345+goranmoomin@users.noreply.github.com"))
    }

    @Test func aHandSetGitIdentitySurvivesTheLogin() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await Self.scriptGh(fake)
        await fake.setFile(
            on: Self.sprite, path: Self.gitconfigPath,
            content: "[user]\n\tname = Someone Else\n\temail = someone@example.com\n")
        let store = InMemorySavedLoginStore()
        store.save(
            SavedGitHubLogin(token: Self.token, login: "goranmoomin", name: "Sungbin Jo", id: 12345,
                             scopes: [], mintedAt: Date()),
            for: GitHubIntegration.id)
        let run = FlowRun(flow: Self.loginFlow(store: store), platform: fake, sprite: Self.sprite)

        await run.start()

        #expect(run.phase == .succeeded)
        let gitconfig = try #require(await fake.fileContents(on: Self.sprite, path: Self.gitconfigPath))
        #expect(gitconfig.contains("email = someone@example.com"))
        #expect(!gitconfig.contains("noreply.github.com"))
    }

    @Test func aDeadSavedLoginIsForgottenAndTheMintRunsInPlace() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await Self.scriptGh(fake, deadToken: "gho_DEADDEAD")
        let store = InMemorySavedLoginStore()
        store.save(
            SavedGitHubLogin(token: "gho_DEADDEAD", login: "goranmoomin", name: "", id: 12345,
                             scopes: [], mintedAt: Date()),
            for: GitHubIntegration.id)
        let run = FlowRun(flow: Self.loginFlow(store: store), platform: fake, sprite: Self.sprite)

        let responder = happyResponder(run, save: false)
        await run.start()
        let prompts = await responder.value

        #expect(run.phase == .succeeded)
        #expect(prompts.contains { if case .openURLAndShowCode = $0 { return true } else { return false } })
        // Forgotten, and not re-saved since the user declined.
        #expect(store.load(for: GitHubIntegration.id) == nil)
        // The mint's hosts file replaced the dead plant.
        let hosts = try #require(await fake.fileContents(on: Self.sprite, path: Self.hostsPath))
        #expect(hosts.contains("oauth_token: \(Self.token)"))
    }

    @Test func theDeviceFlowDeadlineFailsWithAnHonestMessage() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await Self.scriptGh(fake, approve: false)
        let run = FlowRun(flow: Self.loginFlow(), platform: fake, sprite: Self.sprite)

        let responder = happyResponder(run)
        await run.start()
        _ = await responder.value

        #expect(run.phase == .failed)
        #expect(run.failureMessage?.contains("15-minute window") == true)
        #expect(await fake.fileContents(on: Self.sprite, path: Self.hostsPath) == nil)
        #expect(try await fake.listTasks(on: Self.sprite).isEmpty)
    }

    @Test func decliningTheCodePromptKillsTheLogin() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await fake.scriptExec(where: { $0.argv.starts(with: ["gh", "auth", "login"]) }) { _, io in
            io.stderr("\n! First copy your one-time code: B6F3-066B\n"
                + "Open this URL to continue in your web browser: https://github.com/login/device\n")
            _ = await io.read()  // blocks like the real poll until killed
            io.exit(143)
        }
        let run = FlowRun(flow: Self.loginFlow(), platform: fake, sprite: Self.sprite)

        let responder = Task {
            while let prompt = await run.nextPrompt() {
                _ = prompt
                run.respond(.declined)
            }
        }
        await run.start()
        await responder.value

        #expect(run.phase == .cancelled)
        #expect(await fake.killLog.count == 1)
    }

    @Test func flowStartSweepsStaleLoginSessions() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await Self.scriptGh(fake)
        await fake.scriptExec(where: { $0.argv.first == "sleep" }) { _, io in
            _ = await io.readLine()
            io.exit(0)
        }
        // A pre-existing login exec: the fake's script for it exits after
        // the approval delay, but a zombie is killed before that.
        let zombie = try await fake.exec(
            on: Self.sprite,
            command: ExecCommand(GitHubIntegration.loginArgv, env: ["GH_NO_UPDATE_NOTIFIER": "1"]))
        let zombieID = await zombie.sessionID
        await zombie.cancel()
        let bystander = try await fake.exec(on: Self.sprite, command: ExecCommand(["sleep", "600"], tty: true))
        await bystander.cancel()

        let run = FlowRun(flow: Self.loginFlow(), platform: fake, sprite: Self.sprite)
        let responder = happyResponder(run)
        await run.start()
        _ = await responder.value

        #expect(run.phase == .succeeded)
        #expect(await fake.killLog.map(\.sessionID).contains(zombieID))
    }

    @Test func aBareBracesHostsFileIsLoggedOut() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await fake.setFile(on: Self.sprite, path: Self.hostsPath, content: "{}")
        let detail = SpriteDetailModel(platform: fake, sprite: Self.sprite)
        await detail.refresh()
        let line = detail.integrationLines?.first { $0.title == "GitHub" }
        #expect(line?.summary == "not logged in")
        #expect(detail.offeredFlows?.contains { $0.id == "github-login" } == true)
    }

    /// Tripwires on gh's wording, in the spirit of `signInMarker`.
    @Test func parserAnchorsOnGhsWording() {
        let output = "\n! First copy your one-time code: 4261-1EFE\n"
            + "Open this URL to continue in your web browser: https://github.com/login/device\n"
        #expect(GitHubOutputParser.extractDeviceCode(from: output) == "4261-1EFE")
        #expect(GitHubOutputParser.extractDeviceURL(from: output) == URL(string: "https://github.com/login/device"))
        #expect(GitHubOutputParser.extractDeviceCode(from: "! First copy your one-time code: ") == nil)
        #expect(GitHubOutputParser.extractDeviceCode(from: "Please visit https://github.com/login/device") == nil)
        #expect(GitHubOutputParser.extractDeviceURL(from: "your code: ABCD-1234") == nil)
        #expect(GitHubHostsFile.parse("{}") == nil)
        #expect(GitHubHostsFile.parse(GitHubHostsFile.render(login: "octo", token: "gho_x"))
            == GitHubHostsFile.Contents(user: "octo"))
    }
}
