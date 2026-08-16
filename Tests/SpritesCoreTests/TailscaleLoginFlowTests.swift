import Foundation
import Testing
import SpritesCore

/// Log in to Tailscale against a scripted tailscale: install, the tailscaled
/// Service, the pasted-then-saved auth key, the fixed `up` flag set, and
/// observation from `status --json`.
@MainActor
struct TailscaleLoginFlowTests {
    nonisolated static let sprite = "morning-cherry-1234"
    nonisolated static let goodKey = "tskey-auth-kGOODGOODGOOD-abcdefghijklmnopqrstuvwxyz0123456789ABCD"
    nonisolated static let expiredKey = "tskey-auth-kEXPIREDXPIRE-abcdefghijklmnopqrstuvwxyz0123456789ABCD"
    nonisolated static let statePath = "/var/lib/tailscale/tailscaled.state"
    nonisolated static let handConfiguredMarker = "/tmp/hand-configured"
    nonisolated static let needsApprovalMarker = "/tmp/needs-approval"

    nonisolated static let loggedInStatus = """
        {"Version":"1.102.2","TUN":true,"BackendState":"Running","AuthURL":"",
         "TailscaleIPs":["100.90.6.35","fd7a:115c:a1e0::be36:624"],
         "Self":{"HostName":"morning-cherry-1234","DNSName":"morning-cherry-1234.tailcc654.ts.net.","Online":true},
         "Health":[],"MagicDNSSuffix":"tailcc654.ts.net",
         "CurrentTailnet":{"Name":"goranmoomin@gmail.com","MagicDNSSuffix":"tailcc654.ts.net","MagicDNSEnabled":true},
         "CertDomains":["morning-cherry-1234.tailcc654.ts.net"],"Peer":null,"User":null}
        """
    nonisolated static let loggedOutStatus = """
        {"Version":"1.102.2","TUN":true,"BackendState":"NeedsLogin","AuthURL":"","TailscaleIPs":null,
         "Self":{"HostName":"morning-cherry-1234","DNSName":"","Online":false},
         "Health":["Tailscale is stopped."],"MagicDNSSuffix":"","CurrentTailnet":null,"CertDomains":null,"Peer":null,"User":null}
        """

    nonisolated static func loginFlow(store: any SavedLoginStore = InMemorySavedLoginStore()) -> Flow {
        TailscaleIntegration(loginStore: store).loginFlow()
    }

    /// The tailscale surface, answering from the fake's files the way the
    /// real tailscaled answers from its state: `up` with the good key writes
    /// the state file, `status --json` reads it back.
    nonisolated static func scriptTailscale(_ fake: FakeSpritesPlatform, sprite: String = sprite) async {
        await fake.scriptExec(where: { $0.argv == ["uname", "-m"] }) { _, io in
            io.stdout("x86_64\n")
            io.exit(0)
        }
        await fake.scriptExec(where: { $0.argv.first == "curl" && $0.argv.last == TailscaleIntegration.releaseIndexURL }) { _, io in
            io.stdout(#"{"TarballsVersion":"1.102.2","Tarballs":{"amd64":"tailscale_1.102.2_amd64.tgz","arm64":"tailscale_1.102.2_arm64.tgz"}}"#)
            io.exit(0)
        }
        await fake.scriptExec(where: { $0.argv.first == "sh" && $0.argv.last?.contains("pkgs.tailscale.com") == true }) { _, io in
            await fake.setFile(on: sprite, path: TailscaleIntegration.tailscalePath, content: "#!bin")
            await fake.setFile(on: sprite, path: TailscaleIntegration.tailscaledPath, content: "#!bin")
            io.exit(0)
        }
        await fake.scriptExec(where: { $0.argv.starts(with: [TailscaleIntegration.tailscalePath, "status", "--json"]) }) { _, io in
            let state = await fake.fileContents(on: sprite, path: statePath) ?? ""
            if state.contains("_needs-approval") {
                io.stdout(#"{"BackendState":"NeedsMachineAuth","AuthURL":"","TailscaleIPs":null,"Self":{"DNSName":""}}"#)
            } else {
                io.stdout(state.contains("_current-profile") ? loggedInStatus : loggedOutStatus)
            }
            io.exit(0)
        }
        await fake.scriptExec(where: { $0.argv.starts(with: [TailscaleIntegration.tailscalePath, "up"]) }) { command, io in
            guard command.argv.contains("--auth-key=file:" + TailscaleIntegration.authKeyPath),
                let key = await fake.fileContents(on: sprite, path: TailscaleIntegration.authKeyPath)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            else {
                io.stderr("no auth key file\n")
                io.exit(2)
                return
            }
            if await fake.fileContents(on: sprite, path: handConfiguredMarker) != nil {
                io.stderr("Error: changing settings via 'tailscale up' requires mentioning all\n"
                    + "non-default flags. To proceed, either re-run your command with --reset or\n"
                    + "use the command below to explicitly mention the current value of\n"
                    + "all non-default settings:\n\n\ttailscale up --json --ssh\n")
                io.exit(1)
                return
            }
            if key == goodKey, await fake.fileContents(on: sprite, path: needsApprovalMarker) != nil {
                await fake.setFile(on: sprite, path: statePath, content: "_machinekey\n_needs-approval\n")
                io.stderr("timeout waiting for Tailscale service to enter a Running state; check health with \"tailscale status\"\n")
                io.exit(1)
            } else if key == goodKey {
                await fake.setFile(on: sprite, path: statePath, content: "_machinekey\n_current-profile\n")
                io.exit(0)
            } else {
                io.stderr("backend error: invalid key: unable to validate API key\n")
                io.exit(1)
            }
        }
        await fake.scriptExec(where: { $0.argv.first == "chmod" || $0.argv.first == "rm" }) { _, io in io.exit(0) }
    }

    private func responder(_ run: FlowRun, key: String = goodKey, save: Bool = true) -> Task<[FlowPrompt], Never> {
        Task {
            var prompts: [FlowPrompt] = []
            while let prompt = await run.nextPrompt() {
                prompts.append(prompt)
                switch prompt {
                case .openURLAndEnterCode: run.respond(.text(key))
                case .consent: run.respond(save ? .approved : .declined)
                default: run.respond(.declined)
                }
            }
            return prompts
        }
    }

    @Test func firstLoginInstallsDefinesTheServicePastesTheKeyAndSaves() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await Self.scriptTailscale(fake)
        let store = InMemorySavedLoginStore()
        let run = FlowRun(flow: Self.loginFlow(store: store), platform: fake, sprite: Self.sprite)

        let responder = responder(run)
        await run.start()
        let prompts = await responder.value

        #expect(run.phase == .succeeded)
        guard case .openURLAndEnterCode(let url, _) = prompts.first else {
            Issue.record("expected the paste prompt first, got \(prompts)")
            return
        }
        #expect(url == TailscaleIntegration.adminKeysURL)
        // Installed into the user's bin, tailscaled as a Service with no flags.
        #expect(await fake.fileContents(on: Self.sprite, path: TailscaleIntegration.tailscaledPath) != nil)
        let service = try #require(try await fake.services(on: Self.sprite).first)
        #expect(service.name == "tailscaled")
        #expect(service.cmd == TailscaleIntegration.tailscaledPath)
        #expect(service.args.isEmpty)
        // The fixed complete flag set, key by file (never argv), file gone after.
        let up = try #require(await fake.execLog.first { $0.command.argv.contains("up") })
        #expect(up.command.argv == [
            TailscaleIntegration.tailscalePath, "up", "--json",
            "--auth-key=file:/home/sprite/.tailscale-authkey",
            "--hostname=morning-cherry-1234", "--timeout=60s",
        ])
        #expect(!up.command.argv.contains { $0.contains("tskey") })
        #expect(await fake.execLog.contains { $0.command.argv == ["rm", "-f", TailscaleIntegration.authKeyPath] })
        #expect(store.load(SavedTailscaleLogin.self, for: TailscaleIntegration.id)?.authKey == Self.goodKey)

        let detail = SpriteDetailModel(platform: fake, sprite: Self.sprite)
        await detail.refresh()
        let line = detail.integrationLines?.first { $0.title == "Tailscale" }
        #expect(line?.summary == "connected")
        #expect(line?.isReady == true)
        #expect(line?.details == [
            IntegrationStatus.Detail("MagicDNS name", "morning-cherry-1234.tailcc654.ts.net"),
            IntegrationStatus.Detail("Tailnet", "goranmoomin@gmail.com"),
            IntegrationStatus.Detail("Addresses", "100.90.6.35"),
            IntegrationStatus.Detail("Service", "running"),
        ])
    }

    @Test func savedKeyJoinsSilentlyAndSkipsTheInstall() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await Self.scriptTailscale(fake)
        await fake.setFile(on: Self.sprite, path: TailscaleIntegration.tailscaledPath, content: "#!bin")
        let store = InMemorySavedLoginStore()
        store.save(SavedTailscaleLogin(authKey: Self.goodKey, savedAt: Date()), for: TailscaleIntegration.id)
        let run = FlowRun(flow: Self.loginFlow(store: store), platform: fake, sprite: Self.sprite)

        let responder = responder(run)
        await run.start()
        let prompts = await responder.value

        #expect(run.phase == .succeeded)
        #expect(prompts.isEmpty, "the plant branch prompted: \(prompts)")
        #expect(await fake.execLog.allSatisfy { $0.command.argv.first != "curl" })
        #expect(await fake.fileContents(on: Self.sprite, path: Self.statePath)?.contains("_current-profile") == true)
    }

    @Test func aRejectedSavedKeyIsForgottenAndPastedAgain() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await Self.scriptTailscale(fake)
        let store = InMemorySavedLoginStore()
        store.save(SavedTailscaleLogin(authKey: Self.expiredKey, savedAt: Date()), for: TailscaleIntegration.id)
        let run = FlowRun(flow: Self.loginFlow(store: store), platform: fake, sprite: Self.sprite)

        let responder = responder(run, save: false)
        await run.start()
        let prompts = await responder.value

        #expect(run.phase == .succeeded)
        #expect(prompts.contains { if case .openURLAndEnterCode = $0 { return true } else { return false } })
        #expect(store.load(for: TailscaleIntegration.id) == nil)
        #expect(await fake.execLog.filter { $0.command.argv.contains("up") }.count == 2)
    }

    @Test func aTailnetThatApprovesDevicesByHandAsksAndKeepsTheKey() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await Self.scriptTailscale(fake)
        await fake.setFile(on: Self.sprite, path: Self.needsApprovalMarker, content: "yes")
        let store = InMemorySavedLoginStore()
        store.save(SavedTailscaleLogin(authKey: Self.goodKey, savedAt: Date()), for: TailscaleIntegration.id)
        let run = FlowRun(flow: Self.loginFlow(store: store), platform: fake, sprite: Self.sprite)

        let responder = Task {
            var prompts: [FlowPrompt] = []
            while let prompt = await run.nextPrompt() {
                prompts.append(prompt)
                guard case .openURL = prompt else { run.respond(.declined); continue }
                // "The user" approves the device in the admin console.
                await fake.setFile(on: Self.sprite, path: Self.statePath, content: "_machinekey\n_current-profile\n")
                run.respond(.acknowledged)
            }
            return prompts
        }
        await run.start()
        let prompts = await responder.value

        #expect(run.phase == .succeeded)
        guard case .openURL(let url, _) = prompts.first else {
            Issue.record("expected the device-approval ask, got \(prompts)")
            return
        }
        #expect(url == TailscaleIntegration.adminMachinesURL)
        // Not the key's fault: still saved.
        #expect(store.load(for: TailscaleIntegration.id) != nil)
    }

    @Test func aHandConfiguredTailscaledSurfacesItsOwnErrorInsteadOfResetting() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await Self.scriptTailscale(fake)
        await fake.setFile(on: Self.sprite, path: Self.handConfiguredMarker, content: "ssh on")
        let store = InMemorySavedLoginStore()
        store.save(SavedTailscaleLogin(authKey: Self.goodKey, savedAt: Date()), for: TailscaleIntegration.id)
        let run = FlowRun(flow: Self.loginFlow(store: store), platform: fake, sprite: Self.sprite)

        // Nothing should be asked; a stray prompt is declined so the test
        // fails instead of hanging.
        let responder = Task {
            while let prompt = await run.nextPrompt() {
                Issue.record("unexpected prompt \(String(describing: prompt))")
                run.respond(.declined)
            }
        }
        await run.start()
        await responder.value

        #expect(run.phase == .failed)
        #expect(run.failureMessage?.contains("requires mentioning all") == true)
        // Not the key's fault: still saved, and never `--reset`.
        #expect(store.load(for: TailscaleIntegration.id) != nil)
        #expect(await fake.execLog.allSatisfy { !$0.command.argv.contains("--reset") })
    }

    @Test func aPasteThatIsNotAnAuthKeyFailsBeforeTouchingTailscaled() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        await Self.scriptTailscale(fake)
        let run = FlowRun(flow: Self.loginFlow(), platform: fake, sprite: Self.sprite)

        let responder = responder(run, key: "tskey-client-notanauthkey")
        await run.start()
        _ = await responder.value

        #expect(run.phase == .failed)
        #expect(run.failureMessage?.contains("tskey-auth-") == true)
        #expect(await fake.execLog.allSatisfy { !$0.command.argv.contains("up") })
    }

    @Test func observationNeedsNoExecUntilTheServiceRuns() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: Self.sprite, status: .running)
        let model = SpriteDetailModel(platform: fake, sprite: Self.sprite)
        await model.refresh()
        #expect(model.integrationLines?.first { $0.title == "Tailscale" }?.summary == "not set up")
        #expect(await fake.execLog.allSatisfy { $0.command.argv.first != TailscaleIntegration.tailscalePath })

        await fake.setService(
            on: Self.sprite,
            Service(name: "anything", cmd: TailscaleIntegration.tailscaledPath, args: [],
                    state: ServiceState(status: .stopped, pid: nil)))
        await model.refresh()
        let stopped = model.integrationLines?.first { $0.title == "Tailscale" }
        #expect(stopped?.summary == "service stopped")
        #expect(stopped?.details == [IntegrationStatus.Detail("Service", "stopped")])
        #expect(await fake.execLog.allSatisfy { $0.command.argv.first != TailscaleIntegration.tailscalePath })
        #expect(model.offeredFlows?.contains { $0.id == "tailscale-login" } == true)
    }

    /// Tripwire on the `status --json` fields the app reads (the format is
    /// documented as subject to change).
    @Test func statusParserPinsTheFieldsWeRead() throws {
        let running = try #require(TailscaleStatus.parse(Data(Self.loggedInStatus.utf8)))
        #expect(running.backendState == "Running")
        #expect(running.magicDNSName == "morning-cherry-1234.tailcc654.ts.net")
        #expect(running.tailnet == "goranmoomin@gmail.com")
        #expect(running.addresses == ["100.90.6.35"])
        #expect(running.magicDNSEnabled)
        #expect(running.summary == "connected")

        let loggedOut = try #require(TailscaleStatus.parse(Data(Self.loggedOutStatus.utf8)))
        #expect(loggedOut.backendState == "NeedsLogin")
        #expect(loggedOut.magicDNSName == nil)
        #expect(loggedOut.addresses.isEmpty)
        #expect(loggedOut.authURL == nil)
        #expect(loggedOut.summary == "needs login")

        let approval = try #require(TailscaleStatus.parse(Data(#"{"BackendState":"NeedsMachineAuth","AuthURL":"https://login.tailscale.com/a/1"}"#.utf8)))
        #expect(approval.summary == "waiting for device approval")
        #expect(approval.authURL == "https://login.tailscale.com/a/1")
        #expect(TailscaleStatus.parse(Data("Failed to connect to local Tailscale daemon".utf8)) == nil)
    }
}
