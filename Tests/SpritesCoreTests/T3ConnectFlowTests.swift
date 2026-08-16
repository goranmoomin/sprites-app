import Foundation
import Testing
import SpritesCore

/// T3 Connect against a scripted t3: consent, the headless login behind
/// open-URL-and-enter-code with the code fed over stdin, link, Service
/// restart, and the relay-confirmed marker as readiness.
@MainActor
struct T3ConnectFlowTests {
    nonisolated static let sprite = "morning-cherry-1234"
    nonisolated static let authorizeURL = "https://app.t3.codes/connect#state=st4te&challenge=ch4llenge"
    nonisolated static let goodCode = "ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUV.st4te"

    private func makeFake() async -> FakeSpritesPlatform {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await ClaudeCodeLoginFlowTests.plantLoggedIn(fake, sprite: Self.sprite)
        await fake.setFile(on: Self.sprite, path: T3CodeIntegration.binaryPath, content: "#!bin")
        await Self.scriptT3Connect(fake)
        return fake
    }

    /// The `t3 connect` surface answering from the fake's files the way the
    /// CLI answers from its secrets directory. `link` only writes the
    /// desired mode; the "relay" confirms the link a moment after the
    /// Service is started, as the startup reconcile does.
    nonisolated static func scriptT3Connect(
        _ fake: FakeSpritesPlatform, sprite: String = sprite, relayConfirms: Bool = true
    ) async {
        await fake.scriptExec(where: { $0.argv.starts(with: [T3CodeIntegration.binaryPath, "connect", "status"]) }) { _, io in
            let authenticated = await fake.fileContents(on: sprite, path: T3CodeIntegration.connectCredentialPath) != nil
            io.stdout(#"{"desired":null,"authenticated":\#(authenticated),"linked":false}"# + "\n")
            io.exit(0)
        }
        await fake.scriptExec(where: { $0.argv == [T3CodeIntegration.binaryPath, "connect", "login", "--headless"] }) { _, io in
            io.stdout("T3 Connect\n\nHeadless authorization\nOpen this URL on a device with a browser:\n  \(authorizeURL)\n\n"
                + "After signing in, return here and enter the code shown in your browser.\n? Authorization code > ")
            guard let code = await io.readLine(), code == goodCode else {
                io.stderr("Authorization failed: invalid code\n")
                io.exit(1)
                return
            }
            await fake.setFile(on: sprite, path: T3CodeIntegration.connectCredentialPath,
                               content: #"{"accessToken":"a","refreshToken":"r","expiresAtEpochMs":0,"identity":"me@example.com"}"#)
            io.stdout("Signed in as me@example.com\n")
            io.exit(0)
        }
        await fake.scriptExec(where: { $0.argv == [T3CodeIntegration.binaryPath, "connect", "link"] }) { _, io in
            guard await fake.fileContents(on: sprite, path: T3CodeIntegration.connectCredentialPath) != nil else {
                io.stderr("Not signed in\n")
                io.exit(1)
                return
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
        // Non-TTY login, code over stdin, then link and a Service restart.
        let login = try #require(await fake.execLog.first { $0.command.argv.contains("login") })
        #expect(login.command.tty == false)
        #expect(login.command.argv.last == "--headless")
        #expect(await fake.execLog.contains { $0.command.argv == [T3CodeIntegration.binaryPath, "connect", "link"] })
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
        #expect(t3?.flows.map(\.id) == ["t3-setup-connect", "t3-setup"])
        #expect(t3?.flows.map(\.requires) == [[T3CodeIntegration.supportedCodingAgents], [T3CodeIntegration.supportedCodingAgents]])
    }

    /// Tripwires on the CLI wording and file names the app depends on.
    @Test func parserAnchorsOnTheCLIsWording() {
        let banner = "T3 Connect\n\nHeadless authorization\nOpen this URL on a device with a browser:\n  \(Self.authorizeURL)\n\n? Authorization code > "
        #expect(T3ConnectOutputParser.extractAuthorizationURL(from: banner)?.absoluteString == Self.authorizeURL)
        #expect(T3ConnectOutputParser.extractAuthorizationURL(from: "https://clerk.t3.codes/oauth/authorize?x") == nil)
        #expect(T3ConnectOutputParser.extractIdentity(from: "Signed in as me@example.com\n") == "me@example.com")
        #expect(T3ConnectOutputParser.extractIdentity(from: "Authorized as me@example.com\n") == nil)
        #expect(T3CodeIntegration.connectCredentialPath == "/home/sprite/.t3/userdata/secrets/cloud-cli-oauth-token.bin")
        #expect(T3CodeIntegration.connectDesiredLinkPath == "/home/sprite/.t3/userdata/secrets/cloud-cli-desired-link.bin")
        #expect(T3CodeIntegration.connectLinkedUserPath == "/home/sprite/.t3/userdata/secrets/cloud-linked-user-id.bin")
    }
}
