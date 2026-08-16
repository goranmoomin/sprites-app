import Foundation
import Testing
import SpritesCore

// Interactive live rig for the GitHub login Flow: prints the device code
// and URL to /tmp/interactive-status.txt, waits for /tmp/github-login-done.txt
// to appear once the device is approved in a browser, and then lets the
// Flow finish (gh notices the approval by itself). A second sprite gets the
// saved login planted silently. Requires the same env as the Claude rig.
private func note(_ line: String) {
    let url = URL(fileURLWithPath: "/tmp/interactive-status.txt")
    let data = Data((line + "\n").utf8)
    if let handle = try? FileHandle(forWritingTo: url) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SPRITES_INTERACTIVE"] == "1"))
struct InteractiveGitHubTests {
    @Test(.timeLimit(.minutes(20)))
    func interactiveGitHubLoginThenSilentPlant() async throws {
        let environment = ProcessInfo.processInfo.environment
        let platform = HTTPSpritesPlatform(token: environment["SPRITES_LIVE_TOKEN"]!)
        let sprite = environment["SPRITES_LIVE_SPRITE"]!
        let second = environment["SPRITES_LIVE_SPRITE2"] ?? sprite + "-2"
        for name in [sprite, second] where !(try await platform.listSprites().contains { $0.name == name }) {
            _ = try await platform.createSprite(named: name)
            note("### CREATED sprite \(name)")
        }

        let store = InMemorySavedLoginStore()
        let run = FlowRun(
            flow: GitHubIntegration(loginStore: store).loginFlow(), platform: platform, sprite: sprite)
        let responder = Task {
            while let prompt = await run.nextPrompt() {
                switch prompt {
                case .openURLAndShowCode(let url, let code, _):
                    note("### DEVICE_URL \(url.absoluteString)")
                    note("### DEVICE_CODE \(code)")
                    let donePath = "/tmp/github-login-done.txt"
                    for _ in 0..<900 where !FileManager.default.fileExists(atPath: donePath) {
                        try? await Task.sleep(for: .seconds(1))
                    }
                    run.respond(FileManager.default.fileExists(atPath: donePath) ? .acknowledged : .declined)
                case .consent(let title, _, _):
                    note("### CONSENT \(title); approving")
                    run.respond(.approved)
                default:
                    note("### UNEXPECTED PROMPT \(String(describing: prompt))")
                    run.respond(.declined)
                }
            }
        }
        await run.start()
        await responder.value
        note("### FLOW_PHASE \(run.phase)")
        if let failure = run.failureMessage { note("### FAILURE \(failure)") }
        note("### TRANSCRIPT_TAIL \(run.transcript.suffix(600).debugDescription)")

        let detail = SpriteDetailModel(platform: platform, sprite: sprite)
        await detail.refresh()
        for line in detail.integrationLines ?? [] where line.title == "GitHub" {
            note("### STATUS \(line.title): \(line.summary) \(line.details)")
        }
        // Real gh, real API: what the file probe cannot see.
        let status = try await platform.runCapturing(on: sprite, ["gh", "auth", "status"])
        note("### GH_AUTH_STATUS exit=\(status.exitCode) \(status.stderrText.debugDescription)")
        let identity = try await platform.runCapturing(on: sprite, ["git", "config", "--global", "user.email"])
        note("### GIT_EMAIL \(identity.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines))")
        guard run.phase == .succeeded, store.load(for: GitHubIntegration.id) != nil else { return }

        // The fan-out claim: the second sprite plants with no dialogue.
        let plant = FlowRun(
            flow: GitHubIntegration(loginStore: store).loginFlow(), platform: platform, sprite: second)
        let watcher = Task {
            while let prompt = await plant.nextPrompt() {
                note("### PLANT PROMPTED \(String(describing: prompt))")
                plant.respond(.declined)
            }
        }
        await plant.start()
        await watcher.value
        note("### PLANT_PHASE \(plant.phase)")
        let second_status = try await platform.runCapturing(on: second, ["gh", "api", "user", "--jq", ".login"])
        note("### SECOND_SPRITE_LOGIN exit=\(second_status.exitCode) \(second_status.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines))")
        // The unverified live fact from the findings: config.yml present with
        // hosts.yml absent.
        _ = try await platform.runCapturing(on: second, ["rm", "-f", GitHubIntegration.hostsPath])
        let orphan = try await platform.runCapturing(on: second, ["gh", "auth", "status"])
        note("### CONFIG_WITHOUT_HOSTS exit=\(orphan.exitCode) \(orphan.stderrText.debugDescription)")
    }
}
