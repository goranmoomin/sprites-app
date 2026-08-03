import Foundation
import Testing
import SpritesCore

@MainActor
struct T3SetupFlowTests {
    static let sprite = "morning-cherry-1234"

    private func makeFake(claudeLoggedIn: Bool = true) async -> FakeSpritesPlatform {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        if claudeLoggedIn {
            await fake.setFile(
                on: Self.sprite, path: "/home/sprite/.claude/.credentials.json", content: "{}")
        }
        return fake
    }

    /// Scripts the npm install and pairing dialogues; returns nothing, but
    /// installing marks the binary present so a second install is skipped.
    private func scriptT3CLI(_ fake: FakeSpritesPlatform, installCount: Counter) async {
        await fake.scriptExec(where: { $0.argv.first == "npm" && $0.argv.last == "t3" }) { _, io in
            _ = await installCount.increment()
            await fake.setFile(
                on: Self.sprite, path: "/home/sprite/.local/bin/t3", content: "#!binary")
            await fake.setFile(
                on: Self.sprite, path: "/home/sprite/.local/lib/node_modules/t3/package.json",
                content: #"{"name":"t3","version":"0.0.31"}"#)
            io.stdout("added 120 packages\n")
            io.exit(0)
        }
        await fake.scriptExec(where: {
            $0.argv.first == "/home/sprite/.local/bin/t3" && $0.argv.contains("pairing")
        }) { command, io in
            guard command.argv.contains("--json") else {
                io.stderr("expected --json\n")
                io.exit(2)
                return
            }
            io.stdout(#"{"pairUrl":"https://morning-cherry-1234-fake.sprites.app/pair#token=otp-12345","expiresAt":"2036-01-01T00:00:00Z"}"# + "\n")
            io.exit(0)
        }
    }

    @Test func setupRequiresALoggedInCodingAgent() async throws {
        let fake = await makeFake(claudeLoggedIn: false)
        let run = FlowRun(flow: Integrations.t3Code.setupFlow(), platform: fake, sprite: Self.sprite)

        await run.start()

        #expect(run.phase == .failed)
        #expect(run.failureMessage?.contains("coding agent") == true)
        #expect(try await fake.services(on: Self.sprite).isEmpty)
    }

    @Test func setupInstallsOnceDefinesServiceGatesConsentAndPairs() async throws {
        let fake = await makeFake()
        let installCount = Counter()
        await scriptT3CLI(fake, installCount: installCount)
        let run = FlowRun(flow: Integrations.t3Code.setupFlow(), platform: fake, sprite: Self.sprite)

        let responder = Task {
            while let prompt = await run.nextPrompt() {
                switch prompt {
                case .consent(_, let message, _):
                    #expect(message.contains("public"))
                    run.respond(.approved)
                case .pairing(let pairing):
                    #expect(pairing.host == "morning-cherry-1234-fake.sprites.app")
                    #expect(pairing.code == "otp-12345")
                    #expect(pairing.pairURL?.absoluteString.contains("token=otp-12345") == true)
                    run.respond(.acknowledged)
                default:
                    Issue.record("unexpected prompt \(prompt)")
                    run.respond(.declined)
                }
            }
        }
        await run.start()
        await responder.value

        #expect(run.phase == .succeeded)

        // The service runs the installed binary, never npx.
        let service = try #require(try await fake.services(on: Self.sprite).first)
        #expect(service.cmd == "/home/sprite/.local/bin/t3")
        #expect(service.args.first == "serve")
        #expect(service.args.contains("--host"))
        #expect(service.args.contains("0.0.0.0"))
        #expect(service.args.contains("--no-browser"))
        #expect(!service.cmd.contains("npx") && !service.args.contains("npx"))

        // Consent flipped the URL public.
        #expect(try await fake.getSprite(named: Self.sprite).urlVisibility == .public)

        // Recognition now offers the handoff on the detail screen.
        let detail = SpriteDetailModel(platform: fake, sprite: Self.sprite)
        await detail.refresh()
        #expect(detail.actions?.contains { $0.id == "open-in-t3-code" } == true)

        // Running setup again does not reinstall.
        let secondRun = FlowRun(flow: Integrations.t3Code.setupFlow(), platform: fake, sprite: Self.sprite)
        let secondResponder = Task {
            while let prompt = await secondRun.nextPrompt() {
                switch prompt {
                case .consent: secondRun.respond(.approved)
                default: secondRun.respond(.acknowledged)
                }
            }
        }
        await secondRun.start()
        await secondResponder.value
        #expect(secondRun.phase == .succeeded)
        #expect(await installCount.value == 1)
    }

    @Test func decliningConsentLeavesTheURLPrivateAndStopsTheFlow() async throws {
        let fake = await makeFake()
        await scriptT3CLI(fake, installCount: Counter())
        let run = FlowRun(flow: Integrations.t3Code.setupFlow(), platform: fake, sprite: Self.sprite)

        let responder = Task {
            while let prompt = await run.nextPrompt() {
                if case .consent = prompt {
                    run.respond(.declined)
                } else {
                    Issue.record("unexpected prompt after declining: \(prompt)")
                    run.respond(.declined)
                }
            }
        }
        await run.start()
        await responder.value

        #expect(run.phase == .cancelled)
        #expect(try await fake.getSprite(named: Self.sprite).urlVisibility == .private)
    }

    @Test func pairAgainWorksStandalone() async throws {
        let fake = await makeFake()
        await scriptT3CLI(fake, installCount: Counter())
        // Sprite already set up: binary installed, service defined, URL public.
        await fake.setFile(on: Self.sprite, path: "/home/sprite/.local/bin/t3", content: "#!binary")
        await fake.setService(
            on: Self.sprite,
            Service(name: "t3", cmd: "/home/sprite/.local/bin/t3",
                    args: ["serve", "--host", "0.0.0.0"], state: ServiceState(status: "running", pid: 7)))
        try await fake.setURLVisibility(sprite: Self.sprite, .public)

        let run = FlowRun(flow: Integrations.t3Code.pairAgainFlow(), platform: fake, sprite: Self.sprite)
        let responder = Task {
            var pairing: Pairing?
            while let prompt = await run.nextPrompt() {
                if case .pairing(let p) = prompt { pairing = p }
                run.respond(.acknowledged)
            }
            return pairing
        }
        await run.start()
        let pairing = await responder.value

        #expect(run.phase == .succeeded)
        #expect(pairing?.code == "otp-12345")
    }
}
