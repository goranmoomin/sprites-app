import Foundation
import Testing
import SpritesCore

/// T3 Connect against a scripted t3: consent, the headless login behind
/// open-URL-and-enter-code with the code typed into a PTY that outlives the
/// browser hop, link, Service restart, and the relay-confirmed marker as
/// readiness.
@MainActor
struct T3ConnectFlowTests {
    nonisolated static let sprite = "morning-cherry-1234"
    nonisolated static let authorizeURL = "https://app.t3.codes/connect#state=st4te&challenge=ch4llenge"
    nonisolated static let goodCode = "ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUV.st4te"
    /// Where the CLI installs the relay client; the fake only cares that
    /// something is there, since `link` asks only when it is missing.
    nonisolated static let cloudflaredPath =
        "/home/sprite/.t3/tools/cloudflared/2026.5.2/linux-x64/cloudflared"

    private func makeFake() async -> FakeSpritesPlatform {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await ClaudeCodeLoginFlowTests.plantLoggedIn(fake, sprite: Self.sprite)
        await fake.setFile(on: Self.sprite, path: T3CodeIntegration.binaryPath, content: "#!bin")
        await Self.scriptT3Connect(fake)
        return fake
    }

    /// What becomes of the login while the user is in the browser: the
    /// prompt is held on a live socket, the socket dies under a PTY that
    /// keeps holding it, the session is lost with the socket, or the login
    /// finishes and exits before the app is back.
    nonisolated enum Hop: Sendable {
        case held
        case socketDropped
        case sessionLost
        case finishedWhileAway
    }

    /// The `t3 connect` surface answering from the fake's files the way the
    /// CLI answers from its secrets directory. `link` only writes the
    /// desired mode; the "relay" confirms the link a moment after the
    /// Service is started, as the startup reconcile does.
    nonisolated static func scriptT3Connect(
        _ fake: FakeSpritesPlatform, sprite: String = sprite, relayConfirms: Bool = true,
        hop: Hop = .held, relayClientRefused: Bool = false
    ) async {
        await fake.scriptExec(where: { $0.argv.starts(with: [T3CodeIntegration.binaryPath, "connect", "status"]) }) { _, io in
            let authenticated = await fake.fileContents(on: sprite, path: T3CodeIntegration.connectCredentialPath) != nil
            io.stdout(#"{"desired":null,"authenticated":\#(authenticated),"linked":false}"# + "\n")
            io.exit(0)
        }
        await fake.scriptExec(where: { $0.argv == [T3CodeIntegration.binaryPath, "connect", "login", "--headless"] }) { _, io in
            io.stdout("T3 Connect\n\nHeadless authorization\nOpen this URL on a device with a browser:\n  \(authorizeURL)\n\n"
                + "After signing in, return here and enter the code shown in your browser.\n? Authorization code > ")
            // The app got suspended in the browser and its socket died.
            switch hop {
            case .held, .finishedWhileAway: break
            case .socketDropped: io.dropConnection()
            case .sessionLost:
                io.dropConnection()
                io.exit(143)
                return
            }
            guard let code = await io.readLine(), code == goodCode else {
                io.stderr("Authorization failed: invalid code\n")
                io.exit(1)
                return
            }
            await fake.setFile(on: sprite, path: T3CodeIntegration.connectCredentialPath,
                               content: #"{"accessToken":"a","refreshToken":"r","expiresAtEpochMs":0,"identity":"me@example.com"}"#)
            // Coloured under a PTY, as the CLI prints it live.
            io.stdout("\u{1b}[32mSigned in as\u{1b}[0m me@example.com\n")
            if case .finishedWhileAway = hop {
                io.dropConnection()  // signed in, and the socket died before the app was back
            }
            io.exit(0)
        }
        await fake.scriptExec(where: { $0.argv == [T3CodeIntegration.binaryPath, "connect", "link"] }) { _, io in
            guard await fake.fileContents(on: sprite, path: T3CodeIntegration.connectCredentialPath) != nil else {
                io.stderr("Not signed in\n")
                io.exit(1)
                return
            }
            // The first managed link on a Sprite asks to fetch cloudflared,
            // and takes silence for No. Coloured, as under a PTY.
            if await fake.fileContents(on: sprite, path: cloudflaredPath) == nil {
                // In two chunks: a PTY read can split a line anywhere, and
                // the anchor has to survive it.
                io.stdout("\u{1b}[96m?\u{1b}[0m \u{1b}[1mThe T3 relay cli")
                io.stdout("ent is required for T3 Connect. "
                    + "Download and install version 2026.5.2?\u{1b}[0m \u{1b}[90m\u{203a}\u{1b}[0m \u{1b}[90m(y/N)\u{1b}[0m")
                let answer = await io.readLine()
                guard !relayClientRefused, answer?.lowercased().hasPrefix("y") == true else {
                    io.stdout("T3 Connect setup cancelled. The relay client was not installed.\n")
                    io.exit(0)
                    return
                }
                await fake.setFile(on: sprite, path: cloudflaredPath, content: "#!cloudflared")
                io.stdout("Relay client: Downloading...\nRelay client: Installing...\n"
                    + "\u{2713} Relay client ready \u{b7} cloudflared 2026.5.2\n")
            }
            await fake.setFile(on: sprite, path: T3CodeIntegration.connectDesiredLinkPath, content: "managed")
            io.stdout("Authorized as me@example.com\nStart T3 to provision the environment link and launch its managed tunnel.\n")
            if relayConfirms {
                Task {
                    try? await Task.sleep(for: .milliseconds(80))
                    await fake.setFile(on: sprite, path: T3CodeIntegration.connectLinkedUserPath, content: "user_123")
                }
            }
            io.exit(0)
        }
        // The observation probe: presence answers from the fake's files.
        await fake.scriptExec(where: { $0.argv.first == "sh" && $0.argv.last?.contains(T3CodeIntegration.connectLinkedUserPath) == true }) { _, io in
            var lines: [String] = []
            if await fake.fileContents(on: sprite, path: T3CodeIntegration.connectCredentialPath) != nil { lines.append("authorized") }
            if let mode = await fake.fileContents(on: sprite, path: T3CodeIntegration.connectDesiredLinkPath) { lines.append(mode) }
            if await fake.fileContents(on: sprite, path: T3CodeIntegration.connectLinkedUserPath) != nil { lines.append("linked") }
            io.stdout(lines.joined(separator: "\n") + "\n")
            io.exit(0)
        }
    }

    private func flow(pollInterval: Duration = .milliseconds(20)) -> Flow {
        Integrations.t3Code.connectSetupFlow(linkPollInterval: pollInterval)
    }

    private func responder(_ run: FlowRun, code: String = goodCode, consent: FlowResponse = .approved)
        -> Task<[FlowPrompt], Never>
    {
        Task {
            var prompts: [FlowPrompt] = []
            while let prompt = await run.nextPrompt() {
                prompts.append(prompt)
                switch prompt {
                case .consent: run.respond(consent)
                case .openURLAndEnterCode: run.respond(.text(code))
                default: run.respond(.declined)
                }
            }
            return prompts
        }
    }

    @Test func happyPathAuthorizesLinksRestartsAndWaitsForTheRelay() async throws {
        let fake = await makeFake()
        let run = FlowRun(flow: flow(), platform: fake, sprite: Self.sprite)

        let responder = responder(run)
        await run.start()
        let prompts = await responder.value

        #expect(run.phase == .succeeded)
        // Consent first, then the headless URL; never a public-URL consent
        // or a Pairing screen on this path.
        guard prompts.count == 2, case .consent(let title, _, _) = prompts[0],
            case .openURLAndEnterCode(let url, _) = prompts[1]
        else {
            Issue.record("unexpected prompts \(prompts)")
            return
        }
        #expect(title.contains("T3 account"))
        #expect(url.absoluteString == Self.authorizeURL)
        // A PTY login (the only kind of session that survives the browser
        // hop), the code typed in, then link and a Service restart.
        let login = try #require(await fake.execLog.first { $0.command.argv.contains("login") })
        #expect(login.command.tty == true)
        #expect(login.command.env["TERM"] == "xterm-256color")
        #expect(login.command.argv.last == "--headless")
        let link = try #require(await fake.execLog.first { $0.command.argv == [T3CodeIntegration.binaryPath, "connect", "link"] })
        #expect(link.command.tty == true)
        // The relay-client confirm was answered, so cloudflared landed.
        #expect(run.transcript.contains("Relay client ready"))
        #expect(await fake.fileContents(on: Self.sprite, path: Self.cloudflaredPath) != nil)
        let metadata = try await fake.getSprite(named: Self.sprite)
        #expect(metadata.urlVisibility == .private)
        #expect(await fake.fileContents(on: Self.sprite, path: T3CodeIntegration.connectLinkedUserPath) != nil)
        #expect(run.transcript.contains("appears in your T3 Code app as \"morning-cherry-1234\""))

        // Observation: the link shows as a detail, files only.
        let detail = SpriteDetailModel(platform: fake, sprite: Self.sprite)
        await detail.refresh()
        let line = detail.integrationLines?.first { $0.title == "T3 Code" }
        #expect(line?.isReady == true)
        #expect(line?.details.contains(IntegrationStatus.Detail("T3 Connect", "linked (managed)")) == true)
        // The keep-alive is released and the login session ended naturally.
        #expect(try await fake.listTasks(on: Self.sprite).isEmpty)
        #expect(try await fake.listExecSessions(on: Self.sprite).isEmpty)
    }

    /// The observed iOS failure: leaving for the browser suspends the app
    /// and kills the WebSocket while the CLI holds its prompt. The PTY
    /// survives server-side; the step reattaches by identity and types the
    /// code into the same process.
    @Test func socketDropDuringTheHopReattachesAndCompletes() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await ClaudeCodeLoginFlowTests.plantLoggedIn(fake, sprite: Self.sprite)
        await fake.setFile(on: Self.sprite, path: T3CodeIntegration.binaryPath, content: "#!bin")
        await Self.scriptT3Connect(fake, hop: .socketDropped)
        let run = FlowRun(flow: flow(), platform: fake, sprite: Self.sprite)

        let responder = responder(run)
        await run.start()
        _ = await responder.value

        #expect(run.phase == .succeeded, Comment(rawValue: run.failureMessage ?? ""))
        #expect(await fake.attachLog.count == 1)
        #expect(await fake.fileContents(on: Self.sprite, path: T3CodeIntegration.connectCredentialPath) != nil)
        #expect(await fake.fileContents(on: Self.sprite, path: T3CodeIntegration.connectLinkedUserPath) != nil)
        #expect(try await fake.listTasks(on: Self.sprite).isEmpty)
    }

    /// The credential file is the arbiter, not the exit status: a login that
    /// signed in and exited while the app was away leaves nothing to attach
    /// to, and only the file says it worked.
    @Test func theCredentialIsTheArbiterWhenTheLoginFinishesWhileAway() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await ClaudeCodeLoginFlowTests.plantLoggedIn(fake, sprite: Self.sprite)
        await fake.setFile(on: Self.sprite, path: T3CodeIntegration.binaryPath, content: "#!bin")
        await Self.scriptT3Connect(fake, hop: .finishedWhileAway)
        let run = FlowRun(flow: flow(), platform: fake, sprite: Self.sprite)

        let responder = responder(run)
        await run.start()
        _ = await responder.value

        #expect(run.phase == .succeeded, Comment(rawValue: run.failureMessage ?? ""))
        // The identity still names the account, read through the colouring.
        #expect(run.transcript.contains("Authorized as me@example.com"))
        #expect(try await fake.listTasks(on: Self.sprite).isEmpty)
    }

    /// A relay client already on the Sprite means no confirm to answer, and
    /// nothing sent to a CLI that is not asking.
    @Test func anInstalledRelayClientLinksWithoutAConfirm() async throws {
        let fake = await makeFake()
        await fake.setFile(on: Self.sprite, path: Self.cloudflaredPath, content: "#!cloudflared")
        let run = FlowRun(flow: flow(), platform: fake, sprite: Self.sprite)

        let responder = responder(run)
        await run.start()
        _ = await responder.value

        #expect(run.phase == .succeeded, Comment(rawValue: run.failureMessage ?? ""))
        #expect(!run.transcript.contains("Approving the relay client download"))
    }

    /// The CLI exits 0 after refusing the relay client, so the desired-link
    /// secret is what says whether the link was recorded.
    @Test func aRefusedRelayClientFailsInsteadOfWaitingForTheRelay() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await ClaudeCodeLoginFlowTests.plantLoggedIn(fake, sprite: Self.sprite)
        await fake.setFile(on: Self.sprite, path: T3CodeIntegration.binaryPath, content: "#!bin")
        await Self.scriptT3Connect(fake, relayClientRefused: true)
        let run = FlowRun(flow: flow(), platform: fake, sprite: Self.sprite)

        let responder = responder(run)
        await run.start()
        _ = await responder.value

        #expect(run.phase == .failed)
        #expect(run.failureMessage?.contains("without recording the link") == true)
        #expect(await fake.fileContents(on: Self.sprite, path: T3CodeIntegration.connectDesiredLinkPath) == nil)
        // The keep-alive is released and the refused link leaves no PTY.
        #expect(try await fake.listTasks(on: Self.sprite).isEmpty)
        #expect(try await fake.listExecSessions(on: Self.sprite).isEmpty)
    }

    /// The keep-alive pins the Sprite while the user is in the browser, and
    /// is gone once the Flow is done with it.
    @Test func theKeepAlivePinsTheSpriteDuringTheHop() async throws {
        let fake = await makeFake()
        let run = FlowRun(flow: flow(), platform: fake, sprite: Self.sprite)

        let responder = Task { @MainActor in
            while let prompt = await run.nextPrompt() {
                switch prompt {
                case .consent: run.respond(.approved)
                case .openURLAndEnterCode:
                    let during = (try? await fake.listTasks(on: Self.sprite)) ?? []
                    #expect(during.contains { $0.name == T3CodeIntegration.connectLoginKeepAliveTaskName })
                    run.respond(.text(Self.goodCode))
                default: run.respond(.declined)
                }
            }
        }
        await run.start()
        await responder.value

        #expect(run.phase == .succeeded, Comment(rawValue: run.failureMessage ?? ""))
        #expect(try await fake.listTasks(on: Self.sprite).isEmpty)
    }

    /// The login sweeps its own abandoned PTYs at the start, by argument
    /// suffix, and touches nothing else.
    @Test func theLoginSweepsItsStaleSessions() async throws {
        let fake = await makeFake()
        let stale: any ExecSession = try await fake.exec(
            on: Self.sprite,
            command: ExecCommand(
                [T3CodeIntegration.binaryPath, "connect", "login", "--headless"], tty: true))
        let staleID = await stale.sessionID
        await stale.cancel()  // abandoned: detached but alive
        let bystanderID = await Self.addBystander(fake)

        let run = FlowRun(flow: flow(), platform: fake, sprite: Self.sprite)
        let responder = responder(run)
        await run.start()
        _ = await responder.value

        #expect(run.phase == .succeeded, Comment(rawValue: run.failureMessage ?? ""))
        #expect(await fake.killLog.map(\.sessionID) == [staleID])
        #expect(try await fake.listExecSessions(on: Self.sprite).map(\.id) == [bystanderID])
    }

    /// So does the link, whose abandoned PTYs hold the install lock. Its
    /// stale session only survives to be swept once a credential exists, so
    /// this run skips the login.
    @Test func theLinkSweepsItsStaleSessions() async throws {
        let fake = await makeFake()
        await fake.setFile(on: Self.sprite, path: T3CodeIntegration.connectCredentialPath, content: "{}")
        let stale: any ExecSession = try await fake.exec(
            on: Self.sprite,
            command: ExecCommand([T3CodeIntegration.binaryPath, "connect", "link"], tty: true))
        let staleID = await stale.sessionID
        await stale.cancel()
        let bystanderID = await Self.addBystander(fake)

        let run = FlowRun(flow: flow(), platform: fake, sprite: Self.sprite)
        let responder = responder(run)
        await run.start()
        _ = await responder.value

        #expect(run.phase == .succeeded, Comment(rawValue: run.failureMessage ?? ""))
        #expect(await fake.killLog.map(\.sessionID) == [staleID])
        #expect(try await fake.listExecSessions(on: Self.sprite).map(\.id) == [bystanderID])
    }

    /// An innocent abandoned session no sweep may touch.
    nonisolated private static func addBystander(_ fake: FakeSpritesPlatform) async -> String? {
        await fake.scriptExec(where: { $0.argv.first == "sleep" }) { _, io in
            _ = await io.readLine()
            io.exit(0)
        }
        let bystander = try? await fake.exec(
            on: sprite, command: ExecCommand(["sleep", "600"], tty: true))
        let id = await bystander?.sessionID
        await bystander?.cancel()
        return id
    }

    /// A session that is gone by the time the code comes back cannot be
    /// resumed, and says so instead of leaking the platform's `notFound`.
    @Test func aSessionGoneBeforeTheCodeArrivesFailsWithCopy() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await ClaudeCodeLoginFlowTests.plantLoggedIn(fake, sprite: Self.sprite)
        await fake.setFile(on: Self.sprite, path: T3CodeIntegration.binaryPath, content: "#!bin")
        await Self.scriptT3Connect(fake, hop: .sessionLost)
        let run = FlowRun(flow: flow(), platform: fake, sprite: Self.sprite)

        let responder = responder(run)
        await run.start()
        _ = await responder.value

        #expect(run.phase == .failed)
        #expect(run.failureMessage?.contains("ended while you were away") == true)
        #expect(try await fake.listTasks(on: Self.sprite).isEmpty)
    }

    @Test func decliningTheConsentStopsBeforeAnyLogin() async throws {
        let fake = await makeFake()
        let run = FlowRun(flow: flow(), platform: fake, sprite: Self.sprite)

        let responder = responder(run, consent: .declined)
        await run.start()
        _ = await responder.value

        #expect(run.phase == .cancelled)
        #expect(await fake.execLog.allSatisfy { !$0.command.argv.contains("login") })
        // The Service is still defined: interrupted setup leaves a
        // consistent sprite.
        #expect(try await fake.services(on: Self.sprite).count == 1)
    }

    @Test func aWrongCodeFailsWithTheCLIsExit() async throws {
        let fake = await makeFake()
        let run = FlowRun(flow: flow(), platform: fake, sprite: Self.sprite)

        let responder = responder(run, code: "WRONG.st4te")
        await run.start()
        _ = await responder.value

        #expect(run.phase == .failed)
        #expect(run.failureMessage?.contains("did not sign in") == true)
        #expect(await fake.fileContents(on: Self.sprite, path: T3CodeIntegration.connectCredentialPath) == nil)
    }

    @Test func aLinkTheRelayNeverConfirmsFailsHonestly() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await ClaudeCodeLoginFlowTests.plantLoggedIn(fake, sprite: Self.sprite)
        await fake.setFile(on: Self.sprite, path: T3CodeIntegration.binaryPath, content: "#!bin")
        await Self.scriptT3Connect(fake, relayConfirms: false)
        let flow = Integrations.t3Code.connectSetupFlow(
            linkPollInterval: .milliseconds(10), linkTimeout: .milliseconds(100))
        let run = FlowRun(flow: flow, platform: fake, sprite: Self.sprite)

        let responder = responder(run)
        await run.start()
        _ = await responder.value

        #expect(run.phase == .failed)
        #expect(run.failureMessage?.contains("did not confirm the link") == true)
        // Authorized and asked to link, so the next observation says so.
        let detail = SpriteDetailModel(platform: fake, sprite: Self.sprite)
        await detail.refresh()
        let line = detail.integrationLines?.first { $0.title == "T3 Code" }
        #expect(line?.details.contains(IntegrationStatus.Detail("T3 Connect", "authorized, link pending")) == true)
    }

    @Test func anAlreadyAuthorizedSpriteSkipsTheLogin() async throws {
        let fake = await makeFake()
        await fake.setFile(on: Self.sprite, path: T3CodeIntegration.connectCredentialPath, content: "{}")
        let run = FlowRun(flow: flow(), platform: fake, sprite: Self.sprite)

        let responder = responder(run)
        await run.start()
        let prompts = await responder.value

        #expect(run.phase == .succeeded)
        #expect(prompts.count == 1)
        #expect(await fake.execLog.allSatisfy { !$0.command.argv.contains("login") })
    }

    @Test func t3OffersConnectFirstThenPairingThenPairAgain() async throws {
        let fake = await makeFake()
        let model = SpriteDetailModel(platform: fake, sprite: Self.sprite)
        await model.refresh()
        let t3 = model.board?.flatMap(\.tiles).first { $0.id == "t3-code" }
        #expect(t3?.flows.map(\.id) == ["t3-setup-connect", "t3-setup", "t3-setup-tailscale"])
        #expect(t3?.flows.first?.requires == [T3CodeIntegration.supportedCodingAgents])
    }

    /// Tripwires on the CLI wording and file names the app depends on.
    @Test func parserAnchorsOnTheCLIsWording() {
        let banner = "T3 Connect\n\nHeadless authorization\nOpen this URL on a device with a browser:\n  \(Self.authorizeURL)\n\n? Authorization code > "
        #expect(T3ConnectOutputParser.extractAuthorizationURL(from: banner)?.absoluteString == Self.authorizeURL)
        #expect(T3ConnectOutputParser.extractAuthorizationURL(from: "https://clerk.t3.codes/oauth/authorize?x") == nil)
        // Both anchors read the visible text: the CLI colours them under a PTY.
        let coloured = "\u{1b}[1mOpen this URL\u{1b}[0m on a device with a browser:\n  \(Self.authorizeURL)\n"
        #expect(T3ConnectOutputParser.extractAuthorizationURL(from: coloured)?.absoluteString == Self.authorizeURL)
        #expect(T3ConnectOutputParser.extractIdentity(from: "Signed in as me@example.com\n") == "me@example.com")
        #expect(T3ConnectOutputParser.extractIdentity(from: "\u{1b}[32mSigned in as\u{1b}[0m me@example.com\n") == "me@example.com")
        #expect(T3ConnectOutputParser.extractIdentity(from: "Authorized as me@example.com\n") == nil)
        #expect(T3ConnectOutputParser.asksForRelayClient(
            "\u{1b}[96m?\u{1b}[0m \u{1b}[1mThe T3 relay client is required for T3 Connect. "
                + "Download and install version 2026.5.2?\u{1b}[0m \u{1b}[90m\u{203a}\u{1b}[0m \u{1b}[90m(y/N)\u{1b}[0m"))
        #expect(!T3ConnectOutputParser.asksForRelayClient("\u{2713} Relay client ready \u{b7} cloudflared 2026.5.2\n"))
        #expect(T3CodeIntegration.connectCredentialPath == "/home/sprite/.t3/userdata/secrets/cloud-cli-oauth-token.bin")
        #expect(T3CodeIntegration.connectDesiredLinkPath == "/home/sprite/.t3/userdata/secrets/cloud-cli-desired-link.bin")
        #expect(T3CodeIntegration.connectLinkedUserPath == "/home/sprite/.t3/userdata/secrets/cloud-linked-user-id.bin")
    }
}
