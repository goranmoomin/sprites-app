import Foundation
import Testing
import SpritesCore

@MainActor
struct ExecActionTests {
    private func makeFake() async -> FakeSpritesPlatform {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "morning-cherry-1234", status: .running)
        return fake
    }

    @Test func runningACommandShowsDistinguishedOutputAndExitStatus() async throws {
        let fake = await makeFake()
        await fake.scriptExec(where: { $0.argv == ["sh", "-c", "ls /nope"] }) { _, io in
            io.stdout("some-file\n")
            io.stderr("ls: /nope: No such file or directory\n")
            io.exit(1)
        }
        let model = ExecActionModel(platform: fake, spriteName: "morning-cherry-1234")

        await model.run("ls /nope")

        #expect(model.output.map(\.isStderr) == [false, true])
        #expect(model.output.first?.text == "some-file\n")
        #expect(model.output.last?.text.contains("No such file") == true)
        #expect(model.exitCode == 1)
        #expect(!model.isRunning)
    }

    @Test func oneShotExecNeverUsesAPTY() async throws {
        // ADR 0002: non-TTY framed exec only.
        let fake = await makeFake()
        await fake.scriptExec(where: { _ in true }) { _, io in io.exit(0) }
        let model = ExecActionModel(platform: fake, spriteName: "morning-cherry-1234")

        await model.run("echo hi")

        #expect(await fake.execLog.allSatisfy { !$0.command.tty })
    }

    @Test func aRunCanBeCancelled() async throws {
        let fake = await makeFake()
        await fake.scriptExec(where: { _ in true }) { _, io in
            io.stdout("hanging...\n")
            try? await Task.sleep(for: .seconds(30))  // command hangs
            io.exit(0)
        }
        let model = ExecActionModel(platform: fake, spriteName: "morning-cherry-1234")

        let run = Task { await model.run("sleep 999") }
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.isRunning)

        await model.cancel()
        await run.value

        #expect(!model.isRunning)
        #expect(model.exitCode == nil)
        #expect(model.output.first?.text == "hanging...\n")
    }
}
