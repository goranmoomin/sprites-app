import Foundation
import Testing
import SpritesCore

// Interactive live rig for T3 pairing over the tailnet: runs the real Flow
// on a sprite that is already logged in to Tailscale (run the Tailscale rig
// first), prints every web-console ask (MagicDNS, Serve) to
// /tmp/interactive-status.txt and waits for /tmp/tailnet-precondition-done.txt
// before re-checking, then records how long the HTTPS certificate took to
// provision, which the findings still list as unmeasured.
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
struct InteractiveT3TailnetTests {
    @Test(.timeLimit(.minutes(20)))
    func interactiveTailnetPairingMeasuresCertificateProvisioning() async throws {
        let environment = ProcessInfo.processInfo.environment
        let platform = HTTPSpritesPlatform(token: environment["SPRITES_LIVE_TOKEN"]!)
        let sprite = environment["SPRITES_LIVE_SPRITE"]!

        let started = ContinuousClock.now
        let run = FlowRun(flow: Integrations.t3Code.tailnetSetupFlow(), platform: platform, sprite: sprite)
        let responder = Task {
            while let prompt = await run.nextPrompt() {
                switch prompt {
                case .openURL(let url, let instructions):
                    note("### PRECONDITION \(url.absoluteString): \(instructions)")
                    try? FileManager.default.removeItem(atPath: "/tmp/tailnet-precondition-done.txt")
                    for _ in 0..<900 where !FileManager.default.fileExists(atPath: "/tmp/tailnet-precondition-done.txt") {
                        try? await Task.sleep(for: .seconds(1))
                    }
                    run.respond(FileManager.default.fileExists(atPath: "/tmp/tailnet-precondition-done.txt") ? .acknowledged : .declined)
                case .t3Pairing(let pairing):
                    note("### PAIRING host=\(pairing.host) url=\(pairing.pairURL?.absoluteString ?? "-")")
                    run.respond(.acknowledged)
                default:
                    note("### UNEXPECTED PROMPT \(String(describing: prompt))")
                    run.respond(.declined)
                }
            }
        }
        await run.start()
        await responder.value
        note("### FLOW_PHASE \(run.phase) \(run.blockedReason ?? "") elapsed=\(ContinuousClock.now - started)")
        if let failure = run.failureMessage { note("### FAILURE \(failure)") }
        // The certificate lines from the step's own transcript are the
        // measurement: "HTTPS certificate ready" or "still provisioning".
        note("### TRANSCRIPT_TAIL \(run.transcript.suffix(1200).debugDescription)")
        let serve = try await platform.runCapturing(on: sprite, [TailscaleIntegration.tailscalePath, "serve", "status", "--json"])
        note("### SERVE_STATUS \(serve.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
}
