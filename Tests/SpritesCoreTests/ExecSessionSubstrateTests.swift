import Foundation
import Testing
import SpritesCore

/// The detach/attach/list/kill substrate (claude-login-reattach ticket 02):
/// fake sessions must outlive their sockets and replay scrollback exactly
/// like the live platform was observed to.
struct ExecSessionSubstrateTests {
    @Test func detachedSessionSurvivesReplaysAndDies() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "probe", status: .running)
        await fake.scriptExec(where: { $0.argv.first == "bash" }) { _, io in
            io.stdout("prompt$ ")
            guard let line = await io.readLine() else {
                io.exit(1)
                return
            }
            io.stdout("echoed:\(line)\r\n")
            _ = await io.readLine()  // parked until killed
            io.exit(0)
        }

        let session = try await fake.exec(on: "probe", command: ExecCommand(["bash"], tty: true))
        let id = try #require(await session.sessionID)
        var reader = ExecEventReader(session)
        #expect(try await reader.next(within: .seconds(2)) == .stdout(Data("prompt$ ".utf8)))

        // Closing the socket detaches; the session stays listed, alive,
        // with the resolved-path command rendering the sweep matches on.
        await session.cancel()
        let listed = try await fake.listExecSessions(on: "probe")
        #expect(listed.map(\.id) == [id])
        #expect(listed.first?.command == "/usr/bin/bash")
        await #expect(throws: (any Error).self) {
            try await session.send(Data("dead\n".utf8))
        }

        // Attach replays scrollback first, then stdin reaches the process.
        let attached = try await fake.attachExec(on: "probe", sessionID: id)
        #expect(await attached.sessionID == id)
        reader = ExecEventReader(attached)
        #expect(try await reader.next(within: .seconds(2)) == .stdout(Data("prompt$ ".utf8)))
        try await attached.send(Data("hello\n".utf8))
        #expect(try await reader.next(within: .seconds(2)) == .stdout(Data("echoed:hello\r\n".utf8)))

        // Kill: SIGTERM semantics on the attached socket, then gone.
        try await fake.killExecSession(on: "probe", sessionID: id)
        #expect(try await reader.next(within: .seconds(2)) == .exit(143))
        #expect(try await fake.listExecSessions(on: "probe").isEmpty)
        await #expect(throws: (any Error).self) {
            _ = try await fake.attachExec(on: "probe", sessionID: id)
        }
    }

    @Test func naturallyExitedSessionVanishes() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "probe", status: .running)
        await fake.scriptExec(where: { $0.argv == ["true"] }) { _, io in
            io.exit(0)
        }

        let session = try await fake.exec(on: "probe", command: ExecCommand(["true"]))
        let id = try #require(await session.sessionID)
        for await _ in session.events {}  // drain to completion

        #expect(try await fake.listExecSessions(on: "probe").isEmpty)
        await #expect(throws: (any Error).self) {
            _ = try await fake.attachExec(on: "probe", sessionID: id)
        }
        await #expect(throws: (any Error).self) {
            try await fake.killExecSession(on: "probe", sessionID: id)
        }
    }

    @Test func oneShotCapturingRunsAreUnaffected() async throws {
        let fake = FakeSpritesPlatform()
        await fake.addSprite(name: "probe", status: .running)
        await fake.scriptExec(where: { $0.argv.first == "echo" }) { command, io in
            io.stdout(command.argv.dropFirst().joined(separator: " ") + "\n")
            io.exit(0)
        }

        let result = try await fake.runCapturing(on: "probe", ["echo", "hi"])
        #expect(result.exitCode == 0)
        #expect(result.stdoutText == "hi\n")
    }
}
