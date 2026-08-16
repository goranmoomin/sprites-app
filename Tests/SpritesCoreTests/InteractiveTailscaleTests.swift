import Foundation
import Testing
import SpritesCore

// Interactive live rig for the Tailscale login Flow: waits for
// /tmp/tailscale-authkey.txt to hold a reusable, non-ephemeral auth key,
// runs the real Flow on the live sprite, then plants the saved key on a
// second sprite silently. Also records the verbatim wording `up` prints for
// a bad key (still unpinned in the findings) by running once with a
// mangled key when SPRITES_LIVE_TAILSCALE_BADKEY=1. Progress goes to
// /tmp/interactive-status.txt.
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
struct InteractiveTailscaleTests {
    @Test(.timeLimit(.minutes(20)))
    func interactiveTailscaleLoginThenSilentPlant() async throws {
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
            flow: TailscaleIntegration(loginStore: store).loginFlow(), platform: platform, sprite: sprite)
        let responder = Task {
            while let prompt = await run.nextPrompt() {
                switch prompt {
                case .openURLAndEnterCode(let url, _):
                    note("### PASTE_KEY_URL \(url.absoluteString); waiting for /tmp/tailscale-authkey.txt")
                    var key: String?
                    for _ in 0..<900 {
                        if let contents = try? String(contentsOfFile: "/tmp/tailscale-authkey.txt", encoding: .utf8) {
                            let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty { key = trimmed; break }
                        }
                        try? await Task.sleep(for: .seconds(1))
                    }
                    guard let key else { run.respond(.declined); return }
                    if environment["SPRITES_LIVE_TAILSCALE_BADKEY"] == "1" {
                        run.respond(.text(String(key.dropLast(4)) + "XXXX"))
                    } else {
                        run.respond(.text(key))
                    }
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
        if let failure = run.failureMessage { note("### FAILURE (verbatim up wording) \(failure)") }
        note("### TRANSCRIPT_TAIL \(run.transcript.suffix(800).debugDescription)")

        let detail = SpriteDetailModel(platform: platform, sprite: sprite)
        await detail.refresh()
        for line in detail.integrationLines ?? [] where line.title == "Tailscale" {
            note("### STATUS \(line.summary) \(line.details)")
        }
        guard run.phase == .succeeded, store.load(for: TailscaleIntegration.id) != nil else { return }

        let plant = FlowRun(
            flow: TailscaleIntegration(loginStore: store).loginFlow(), platform: platform, sprite: second)
        let watcher = Task {
            while let prompt = await plant.nextPrompt() {
                note("### PLANT PROMPTED \(String(describing: prompt))")
                plant.respond(.declined)
            }
        }
        await plant.start()
        await watcher.value
        note("### PLANT_PHASE \(plant.phase) \(plant.failureMessage ?? "")")
        let status = try await platform.runCapturing(on: second, [TailscaleIntegration.tailscalePath, "status", "--json"])
        note("### SECOND_STATUS \(TailscaleStatus.parse(status.stdout).map { "\($0.backendState) \($0.magicDNSName ?? "")" } ?? "unparsed")")
    }
}
