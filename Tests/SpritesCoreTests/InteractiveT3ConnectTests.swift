import Foundation
import Testing
import SpritesCore

// Interactive live rig for T3 Connect: prints the authorization URL to
// /tmp/interactive-status.txt, waits for /tmp/t3-connect-code.txt to hold
// the code the hosted page shows, feeds it through the real Flow, and
// records what the relay confirms. Same env as the Claude rig; the sprite
// needs a logged-in coding agent first (run the Claude rig, or plant).
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
struct InteractiveT3ConnectTests {
    @Test(.timeLimit(.minutes(20)))
    func interactiveT3ConnectEndToEnd() async throws {
        let environment = ProcessInfo.processInfo.environment
        let platform = HTTPSpritesPlatform(token: environment["SPRITES_LIVE_TOKEN"]!)
        let sprite = environment["SPRITES_LIVE_SPRITE"]!
        if !(try await platform.listSprites().contains { $0.name == sprite }) {
            _ = try await platform.createSprite(named: sprite)
            note("### CREATED sprite \(sprite)")
        }

        let run = FlowRun(flow: Integrations.t3Code.connectSetupFlow(), platform: platform, sprite: sprite)
        let responder = Task {
            while let prompt = await run.nextPrompt() {
                switch prompt {
                case .consent(let title, _, _):
                    note("### CONSENT \(title); approving")
                    run.respond(.approved)
                case .openURLAndEnterCode(let url, _):
                    note("### AUTHORIZE_URL \(url.absoluteString); waiting for /tmp/t3-connect-code.txt")
                    var code: String?
                    for _ in 0..<900 {
                        if let contents = try? String(contentsOfFile: "/tmp/t3-connect-code.txt", encoding: .utf8) {
                            let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty { code = trimmed; break }
                        }
                        try? await Task.sleep(for: .seconds(1))
                    }
                    guard let code else { run.respond(.declined); return }
                    note("### CODE RECEIVED (\(code.count) chars); SUBMITTING")
                    run.respond(.text(code))
                default:
                    note("### UNEXPECTED PROMPT \(String(describing: prompt))")
                    run.respond(.declined)
                }
            }
        }
        await run.start()
        await responder.value
        note("### FLOW_PHASE \(run.phase) \(run.blockedReason ?? "")")
        if let failure = run.failureMessage { note("### FAILURE \(failure)") }
        note("### TRANSCRIPT_TAIL \(run.transcript.suffix(800).debugDescription)")

        let detail = SpriteDetailModel(platform: platform, sprite: sprite)
        await detail.refresh()
        for line in detail.integrationLines ?? [] where line.title == "T3 Code" {
            note("### STATUS \(line.summary) \(line.details)")
        }
        let status = try await platform.runCapturing(
            on: sprite, [T3CodeIntegration.binaryPath, "connect", "status", "--json"])
        note("### T3_CONNECT_STATUS \(status.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
}
