import Foundation
import Testing
import SpritesCore

// Interactive live rig for the Claude login Flow: prints the sign-in URL
// (to /tmp/interactive-status.txt), then waits for /tmp/claude-login-code.txt to
// appear with the pasted OAuth code and feeds it through the real Flow.
// print() is fully buffered when redirected; append to a file instead so
// progress is visible while the test waits for the pasted code.
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
struct InteractiveLoginTests {
    @Test(.timeLimit(.minutes(15)))
    func interactiveClaudeLoginEndToEnd() async throws {
        let platform = HTTPSpritesPlatform(
            token: ProcessInfo.processInfo.environment["SPRITES_LIVE_TOKEN"]!)
        let sprite = ProcessInfo.processInfo.environment["SPRITES_LIVE_SPRITE"]!

        if !(try await platform.listSprites().contains { $0.name == sprite }) {
            _ = try await platform.createSprite(named: sprite)
            note("### CREATED sprite \(sprite)")
        }

        let run = FlowRun(
            flow: Integrations.claudeCode.loginFlow(urlTimeout: .seconds(120)),
            platform: platform, sprite: sprite)

        let responder = Task {
            guard case .openURLAndEnterCode(let url, _) = await run.nextPrompt() else {
                note("### NO PROMPT")
                return
            }
            note("### SIGN_IN_URL \(url.absoluteString)")
            let codePath = "/tmp/claude-login-code.txt"
            var code: String?
            for _ in 0..<600 {
                if let contents = try? String(contentsOfFile: codePath, encoding: .utf8) {
                    let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        code = trimmed
                        break
                    }
                }
                try? await Task.sleep(for: .seconds(1))
            }
            guard let code else {
                note("### NO CODE PROVIDED; DECLINING")
                run.respond(.declined)
                return
            }
            // Shape capture for the clipboard-matcher design: length and
            // charset classes, never the code itself.
            let classes = [
                ("alnum", code.allSatisfy { $0.isLetter || $0.isNumber }),
                ("has-#", code.contains("#")),
                ("has--", code.contains("-")),
                ("has-_", code.contains("_")),
            ]
            note("### CODE SHAPE \(code.count) chars, \(classes.filter(\.1).map(\.0).joined(separator: ","))")
            note("### CODE RECEIVED (\(code.count) chars); SUBMITTING")
            run.respond(.text(code))
            // The minted-token screen: shape only, never the token itself.
            if case .claudeMintedToken(let token) = await run.nextPrompt() {
                note("### TOKEN CAPTURED (\(token.count) chars, prefix \(token.prefix(13)))")
                run.respond(.acknowledged)
            } else {
                note("### NO TOKEN PROMPT")
            }
        }
        await run.start()
        await responder.value

        note("### FLOW_PHASE \(run.phase)")
        if let failure = run.failureMessage {
            note("### FAILURE \(failure)")
        }
        note("### TRANSCRIPT_TAIL \(ClaudeOutputParser.stripANSI(run.transcript).suffix(800).debugDescription)")

        // Observation: does the detail screen now see the login?
        let detail = SpriteDetailModel(platform: platform, sprite: sprite)
        await detail.refresh()
        for line in detail.integrationLines ?? [] {
            note("### STATUS \(line.title): \(line.summary)")
        }

        // Credentials and hooks on disk.
        let hasCredentials = try await platform.fileExists(
            on: sprite, path: ClaudeCodeIntegration.credentialsPath)
        note("### CREDENTIALS_FILE \(hasCredentials)")
        let settings = try await platform.readFile(
            on: sprite, path: ClaudeCodeIntegration.settingsPath)
        note("### HOOKS_INSTALLED \(settings?.contains("claude-heartbeat") == true)")

        guard run.phase == .succeeded else { return }

        // Heartbeat check: drive a claude prompt headlessly and watch for
        // the claude-heartbeat task while it runs.
        note("### RUNNING claude -p")
        let prompt = Task {
            try await platform.runCapturing(
                on: sprite, ["claude", "-p", "Reply with exactly: ok"])
        }
        var sawHeartbeat = false
        for _ in 0..<30 where !sawHeartbeat {
            let tasks = (try? await platform.listTasks(on: sprite)) ?? []
            if tasks.contains(where: { $0.name == "claude-heartbeat" }) {
                sawHeartbeat = true
            }
            try? await Task.sleep(for: .seconds(1))
        }
        let result = try await prompt.value
        note("### CLAUDE_P exit=\(result.exitCode) output=\(result.stdoutText.suffix(200).debugDescription)")
        note("### HEARTBEAT_SEEN \(sawHeartbeat)")
        let tasksAfter = (try? await platform.listTasks(on: sprite)) ?? []
        note("### HEARTBEAT_AFTER \(tasksAfter.contains { $0.name == "claude-heartbeat" })")
    }
}
