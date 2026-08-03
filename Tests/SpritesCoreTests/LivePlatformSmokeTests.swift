import Foundation
import Testing
import SpritesCore

/// Live smoke test against a real sprite. Skipped unless both environment
/// variables are set:
///
///   SPRITES_LIVE_TOKEN=<sprite token> SPRITES_LIVE_SPRITE=<sprite name> \
///     swift test --filter LivePlatformSmokeTests
///
/// Exercises the real HTTP + WebSocket client end to end: shallow reads,
/// exec framing, in-sprite files, the tasks management socket, services
/// with streamed upsert progress, and checkpoint create.
private let liveConfigured =
    ProcessInfo.processInfo.environment["SPRITES_LIVE_TOKEN"] != nil
    && ProcessInfo.processInfo.environment["SPRITES_LIVE_SPRITE"] != nil

@Suite(.serialized, .enabled(if: liveConfigured))
struct LivePlatformSmokeTests {
    static var platform: HTTPSpritesPlatform {
        HTTPSpritesPlatform(token: ProcessInfo.processInfo.environment["SPRITES_LIVE_TOKEN"]!)
    }

    static var sprite: String {
        ProcessInfo.processInfo.environment["SPRITES_LIVE_SPRITE"]!
    }

    @Test func shallowObservationSeesTheSprite() async throws {
        let platform = Self.platform
        let sprites = try await platform.listSprites()
        #expect(sprites.contains { $0.name == Self.sprite })

        let metadata = try await platform.getSprite(named: Self.sprite)
        #expect(metadata.name == Self.sprite)
        #expect(metadata.url != nil)
    }

    @Test func framedExecCapturesOutputAndExitStatus() async throws {
        // Observed live: the exec endpoint merges stderr into stdout frames
        // (stream ID 2 is documented but never seen), with nondeterministic
        // interleaving between the two pipes. Exit codes are exact.
        let platform = Self.platform
        let result = try await platform.runCapturing(
            on: Self.sprite, ["sh", "-c", "echo out; echo err >&2; exit 3"])
        #expect(result.stdoutText.contains("out\n"))
        #expect(result.stdoutText.contains("err\n"))
        #expect(result.exitCode == 3)
    }

    @Test func filesRoundTripThroughExec() async throws {
        let platform = Self.platform
        let path = "/tmp/sprites-app-live-smoke.txt"
        #expect(try await platform.fileExists(on: Self.sprite, path: "/no/such/file") == false)

        try await platform.writeFile(on: Self.sprite, path: path, content: "live smoke\n")
        #expect(try await platform.fileExists(on: Self.sprite, path: path))
        #expect(try await platform.readFile(on: Self.sprite, path: path) == "live smoke\n")

        _ = try await platform.runCapturing(on: Self.sprite, ["rm", path])
    }

    @Test func tasksCreateListDeleteAgainstTheManagementSocket() async throws {
        let platform = Self.platform
        try await platform.upsertTask(on: Self.sprite, named: "live-smoke-task", expiringInSeconds: 120)

        let tasks = try await platform.listTasks(on: Self.sprite)
        let task = try #require(tasks.first { $0.name == "live-smoke-task" })
        #expect(task.expiresAt != nil)

        try await platform.deleteTask(on: Self.sprite, named: "live-smoke-task")
        let after = try await platform.listTasks(on: Self.sprite)
        #expect(!after.contains { $0.name == "live-smoke-task" })
    }

    @Test func serviceLifecycleUpsertObserveLogsStopStartDelete() async throws {
        let platform = Self.platform
        let definition = ServiceDefinition(
            cmd: "/usr/bin/python3",
            args: ["-u", "-m", "http.server", "18123"],
            httpPort: 18123)

        var progress: [ServiceUpsertEvent] = []
        for try await event in try await platform.upsertService(
            on: Self.sprite, named: "live-smoke-svc", definition: definition)
        {
            progress.append(event)
        }
        #expect(progress.contains { $0.type == "complete" })

        var service = try #require(
            try await platform.services(on: Self.sprite).first { $0.name == "live-smoke-svc" })
        #expect(service.cmd == "/usr/bin/python3")
        #expect(service.args == ["-u", "-m", "http.server", "18123"])
        #expect(service.state?.status == .running)

        try await platform.stopService(on: Self.sprite, named: "live-smoke-svc")
        service = try #require(
            try await platform.services(on: Self.sprite).first { $0.name == "live-smoke-svc" })
        #expect(service.state?.status != .running)

        try await platform.startService(on: Self.sprite, named: "live-smoke-svc")
        service = try #require(
            try await platform.services(on: Self.sprite).first { $0.name == "live-smoke-svc" })
        #expect(service.state?.status == .running)

        let logs = try await platform.serviceLogs(on: Self.sprite, named: "live-smoke-svc", lines: 50)
        #expect(!logs.isEmpty)

        try await platform.deleteService(on: Self.sprite, named: "live-smoke-svc")
        let after = try await platform.services(on: Self.sprite)
        #expect(!after.contains { $0.name == "live-smoke-svc" })
    }

    @MainActor
    @Test func claudeLoginFlowReachesTheCodePromptOnTheLivePTY() async throws {
        // Runs the real login Flow against the live sprite up to the point
        // the native step UI appears (URL extracted from the headless PTY),
        // then declines. Completing the OAuth needs a human.
        let run = FlowRun(
            flow: Integrations.claudeCode.loginFlow(urlTimeout: .seconds(60)),
            platform: Self.platform, sprite: Self.sprite)

        let responder = Task { () -> URL? in
            guard case .openURLAndEnterCode(let url, _) = await run.nextPrompt() else { return nil }
            run.respond(.declined)
            return url
        }
        await run.start()
        let url = try #require(await responder.value, "flow never prompted; transcript: \(run.transcript.suffix(2000))")

        #expect(run.phase == .cancelled)
        #expect(url.absoluteString.contains("oauth"))
        // The marker-anchored URL must be the paste-code variant, not the
        // localhost-callback one from the earlier browser-open escape.
        #expect(!url.absoluteString.contains("localhost"))
    }

    @Test func checkpointCreateStreamsProgressAndLands() async throws {
        let platform = Self.platform
        var events: [CheckpointEvent] = []
        for try await event in try await platform.createCheckpoint(
            on: Self.sprite, comment: "live smoke")
        {
            events.append(event)
        }
        #expect(events.contains { $0.type == "complete" })

        let checkpoints = try await platform.checkpoints(on: Self.sprite)
        #expect(checkpoints.contains { $0.comment == "live smoke" })
    }
}
