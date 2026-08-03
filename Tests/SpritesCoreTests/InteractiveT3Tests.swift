import Foundation
import Testing
import SpritesCore

// Interactive live rig for the T3 setup and pairing Flows plus detail
// observation, checkpoints, and keep-alive. Gated behind
// SPRITES_INTERACTIVE=1; progress is appended to /tmp/t3-status.txt.
private func note(_ line: String) {
    let url = URL(fileURLWithPath: "/tmp/t3-status.txt")
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
struct InteractiveT3Tests {
    @Test(.timeLimit(.minutes(15)))
    func t3SetupPairingObservationCheckpointsKeepAlive() async throws {
        let platform = HTTPSpritesPlatform(
            token: ProcessInfo.processInfo.environment["SPRITES_LIVE_TOKEN"]!)
        let sprite = ProcessInfo.processInfo.environment["SPRITES_LIVE_SPRITE"]!

        // 1. T3 setup Flow, consenting and acknowledging like a user.
        let run = FlowRun(flow: Integrations.t3Code.setupFlow(), platform: platform, sprite: sprite)
        let responder = Task { () -> T3Pairing? in
            var pairing: T3Pairing?
            while let prompt = await run.nextPrompt() {
                switch prompt {
                case .consent(let title, _, _):
                    note("### CONSENT PROMPT \(title)")
                    run.respond(.approved)
                case .t3Pairing(let p):
                    pairing = p
                    note("### PAIRING host=\(p.host) code=\(p.code.prefix(8))... url=\(p.pairURL?.absoluteString.prefix(60) ?? "none") expires=\(p.expiresAt.map(String.init(describing:)) ?? "nil")")
                    run.respond(.acknowledged)
                default:
                    note("### UNEXPECTED PROMPT \(prompt)")
                    run.respond(.declined)
                }
            }
            return pairing
        }
        await run.start()
        let pairing = await responder.value
        note("### T3_FLOW_PHASE \(run.phase)")
        if run.phase != .succeeded {
            note("### FAILURE \(run.failureMessage ?? "-")")
            note("### TRANSCRIPT \(run.transcript.suffix(1500))")
            return
        }
        #expect(pairing != nil)

        // 2. Observation: status line with version, action, recognition.
        let detail = SpriteDetailModel(platform: platform, sprite: sprite)
        await detail.refresh()
        for line in detail.integrationLines ?? [] {
            note("### STATUS \(line.title): \(line.summary) ready=\(line.isReady)")
        }
        note("### ACTIONS \((detail.actions ?? []).map(\.id))")
        for service in detail.services ?? [] {
            note("### SERVICE \(service.name) custom=\(detail.isCustom(service)) state=\(service.state?.status.display ?? "?")")
        }
        note("### URL_VISIBILITY \(detail.metadata?.urlVisibility.rawValue ?? "?")")

        // 3. The public URL should now serve t3.
        if let url = detail.metadata?.url {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            let (_, response) = try await URLSession.shared.data(for: request)
            note("### PUBLIC_HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        // 4. Pair again, standalone.
        let pairAgain = FlowRun(flow: Integrations.t3Code.pairAgainFlow(), platform: platform, sprite: sprite)
        let pairResponder = Task { () -> T3Pairing? in
            var second: T3Pairing?
            while let prompt = await pairAgain.nextPrompt() {
                if case .t3Pairing(let p) = prompt { second = p }
                pairAgain.respond(.acknowledged)
            }
            return second
        }
        await pairAgain.start()
        let second = await pairResponder.value
        note("### PAIR_AGAIN \(pairAgain.phase) newCode=\(second.map { $0.code != pairing?.code } ?? false)")

        // 5. Checkpoint: create with comment, list, then restore it and
        // re-observe (service and login must survive a same-state restore).
        await detail.createCheckpoint(comment: "fully set up")
        note("### CHECKPOINT_PROGRESS \(detail.checkpointProgress.map(\.type))")
        let checkpoint = detail.manualCheckpoints.last
        note("### CHECKPOINT \(checkpoint?.id ?? "none") comment=\(checkpoint?.comment ?? "-")")

        if let checkpoint {
            await detail.restoreCheckpoint(id: checkpoint.id)
            note("### RESTORE_PROGRESS \(detail.checkpointProgress.map(\.type))")
            await detail.refresh()
            note("### POST_RESTORE claude=\(detail.integrationLines?.first { $0.title == "Claude Code" }?.summary ?? "?") t3=\(detail.integrationLines?.first { $0.title == "T3 Code" }?.summary ?? "?")")
        }

        // 6. Keep-alive through the model: create, extend, release.
        await detail.keepActive()
        note("### KEEPALIVE_CREATED \(detail.keepAliveTask?.name ?? "none") expires=\(detail.keepAliveTask?.expiresAt.map(String.init(describing:)) ?? "nil")")
        let firstExpiry = detail.keepAliveTask?.expiresAt
        try await Task.sleep(for: .seconds(2))
        await detail.keepActive()
        note("### KEEPALIVE_EXTENDED moved=\(detail.keepAliveTask?.expiresAt != firstExpiry)")
        await detail.releaseKeepAlive()
        note("### KEEPALIVE_RELEASED gone=\(detail.keepAliveTask == nil)")
        note("### DONE")
    }
}
