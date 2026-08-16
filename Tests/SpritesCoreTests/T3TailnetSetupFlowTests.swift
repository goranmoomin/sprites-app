import Foundation
import Testing
import SpritesCore

/// T3 pairing over the tailnet: blocked until Tailscale is ready, the two
/// web-console preconditions as `.openURL` prompts that re-check, then a
/// Pairing on the MagicDNS name with no public-URL consent.
@MainActor
struct T3TailnetSetupFlowTests {
    nonisolated static let sprite = "morning-cherry-1234"
    nonisolated static let serveEnabledMarker = "/tmp/serve-enabled"
    nonisolated static let magicDNSOffMarker = "/tmp/magicdns-off"

    private func makeFake(tailscaleReady: Bool = true) async -> FakeSpritesPlatform {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await ClaudeCodeLoginFlowTests.plantLoggedIn(fake, sprite: Self.sprite)
        await fake.setFile(on: Self.sprite, path: T3CodeIntegration.binaryPath, content: "#!bin")
        await TailscaleLoginFlowTests.scriptTailscale(fake, sprite: Self.sprite)
        if tailscaleReady {
            await fake.setService(
                on: Self.sprite,
                Service(name: "tailscaled", cmd: TailscaleIntegration.tailscaledPath, args: [],
                        state: ServiceState(status: .running, pid: 7)))
            await fake.setFile(on: Self.sprite, path: TailscaleLoginFlowTests.statePath, content: "_current-profile")
        }
        await Self.scriptServe(fake)
        return fake
    }

    /// `tailscale serve` refuses with the enable URL until the marker says
    /// the tailnet has Serve on; the certificate probe answers 200.
    nonisolated static func scriptServe(_ fake: FakeSpritesPlatform, sprite: String = sprite) async {
        await fake.scriptExec(where: { $0.argv.starts(with: ["timeout", "20", TailscaleIntegration.tailscalePath, "serve"]) }) { _, io in
            if await fake.fileContents(on: sprite, path: serveEnabledMarker) == nil {
                io.stdout("\nServe is not enabled on your tailnet.\nTo enable, visit:\n\n\thttps://login.tailscale.com/f/serve?node=nVHfATME8G11CNTRL\n")
                io.exit(1)
            } else {
                io.exit(0)
            }
        }
        await fake.scriptExec(where: { $0.argv.first == "curl" && $0.argv.last?.hasSuffix(".ts.net/") == true }) { _, io in
            io.stdout("200")
            io.exit(0)
        }
        // A pairing on whatever base URL is asked for.
        await fake.scriptExec(where: { $0.argv.first == T3CodeIntegration.binaryPath && $0.argv.contains("pairing") }) { command, io in
            let base = command.argv[command.argv.firstIndex(of: "--base-url")! + 1]
            io.stdout(#"{"pairUrl":"\#(base)/pair#token=otp-777","credential":"otp-777"}"# + "\n")
            io.exit(0)
        }
    }

    private func responder(_ run: FlowRun, fake: FakeSpritesPlatform, enableServeOnAsk: Bool = true)
        -> Task<[FlowPrompt], Never>
    {
        Task {
            var prompts: [FlowPrompt] = []
            while let prompt = await run.nextPrompt() {
                prompts.append(prompt)
                switch prompt {
                case .openURL(let url, _):
                    // "The user" fixes it in the console, then comes back.
                    if url.path.hasPrefix("/f/serve"), enableServeOnAsk {
                        await fake.setFile(on: Self.sprite, path: Self.serveEnabledMarker, content: "on")
                    }
                    run.respond(enableServeOnAsk ? .acknowledged : .declined)
                case .t3Pairing: run.respond(.acknowledged)
                default: run.respond(.declined)
                }
            }
            return prompts
        }
    }

    @Test func blockedUntilTailscaleIsReadyNamingTailscale() async throws {
        let fake = await makeFake(tailscaleReady: false)
        let run = FlowRun(flow: Integrations.t3Code.tailnetSetupFlow(), platform: fake, sprite: Self.sprite)
        await run.start()
        #expect(run.phase == .blocked)
        #expect(run.blockedReason == "This needs Tailscale ready on this sprite. Run its Flow first.")
        #expect(Integrations.t3Code.tailnetSetupFlow().requires == [T3CodeIntegration.supportedCodingAgents, .tailscale])
    }

    @Test func serveOffAsksOnceThenServesAndPairsOnTheMagicDNSName() async throws {
        let fake = await makeFake()
        let run = FlowRun(
            flow: Integrations.t3Code.tailnetSetupFlow(certificateProbeInterval: .milliseconds(10)),
            platform: fake, sprite: Self.sprite)

        let responder = responder(run, fake: fake)
        await run.start()
        let prompts = await responder.value

        #expect(run.phase == .succeeded)
        guard prompts.count == 2, case .openURL(let enableURL, _) = prompts[0],
            case .t3Pairing(let pairing) = prompts[1]
        else {
            Issue.record("unexpected prompts \(prompts)")
            return
        }
        #expect(enableURL.absoluteString == "https://login.tailscale.com/f/serve?node=nVHfATME8G11CNTRL")
        #expect(pairing.host == "morning-cherry-1234.tailcc654.ts.net")
        #expect(pairing.pairURL?.absoluteString == "https://morning-cherry-1234.tailcc654.ts.net/pair#token=otp-777")
        // Served bounded, on the t3 port; the sprite URL stayed private.
        #expect(await fake.execLog.filter { $0.command.argv.contains("serve") }.count == 2)
        #expect(await fake.execLog.contains { $0.command.argv.suffix(2) == ["--https=443", "http://127.0.0.1:3773"] })
        #expect(try await fake.getSprite(named: Self.sprite).urlVisibility == .private)
    }

    @Test func magicDNSOffAsksForTheDNSPage() async throws {
        // A status without MagicDNS on: script the answer ahead of the
        // shared tailscale script so it wins.
        let fakeStatus = TailscaleLoginFlowTests.loggedInStatus.replacing("\"MagicDNSEnabled\":true", with: "\"MagicDNSEnabled\":false")
        let fake2 = FakeSpritesPlatform()
        await fake2.addSprite(name: Self.sprite, status: .running)
        await ClaudeCodeLoginFlowTests.plantLoggedIn(fake2, sprite: Self.sprite)
        await fake2.setFile(on: Self.sprite, path: T3CodeIntegration.binaryPath, content: "#!bin")
        await fake2.setService(
            on: Self.sprite,
            Service(name: "tailscaled", cmd: TailscaleIntegration.tailscaledPath, args: [],
                    state: ServiceState(status: .running, pid: 7)))
        await fake2.scriptExec(where: { $0.argv.starts(with: [TailscaleIntegration.tailscalePath, "status", "--json"]) }) { _, io in
            io.stdout(fakeStatus)
            io.exit(0)
        }
        await Self.scriptServe(fake2)
        let run = FlowRun(flow: Integrations.t3Code.tailnetSetupFlow(), platform: fake2, sprite: Self.sprite)

        let responder = Task {
            var first: FlowPrompt?
            while let prompt = await run.nextPrompt() {
                if first == nil { first = prompt }
                run.respond(.declined)
            }
            return first
        }
        await run.start()
        let first = await responder.value

        #expect(run.phase == .cancelled)
        guard case .openURL(let url, let instructions) = first else {
            Issue.record("expected the DNS-page ask, got \(String(describing: first))")
            return
        }
        #expect(url == T3CodeIntegration.tailscaleDNSSettingsURL)
        #expect(instructions.contains("MagicDNS"))
    }

    @Test func t3OffersTheTailnetVariantAfterConnectAndPairing() async throws {
        let fake = await makeFake()
        let model = SpriteDetailModel(platform: fake, sprite: Self.sprite)
        await model.refresh()
        let t3 = model.board?.flatMap(\.tiles).first { $0.id == "t3-code" }
        #expect(t3?.flows.map(\.id) == ["t3-setup-connect", "t3-setup", "t3-setup-tailscale"])
    }

    @Test func serveRefusalParserPinsTheWording() {
        let refusal = "\nServe is not enabled on your tailnet.\nTo enable, visit:\n\n\thttps://login.tailscale.com/f/serve?node=abc\n"
        #expect(TailscaleServeOutputParser.extractEnableURL(from: refusal)?.absoluteString == "https://login.tailscale.com/f/serve?node=abc")
        #expect(TailscaleServeOutputParser.extractEnableURL(from: "No serve config\n") == nil)
    }
}
