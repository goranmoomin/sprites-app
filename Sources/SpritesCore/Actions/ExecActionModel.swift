import Foundation
import Observation

/// One-shot exec: run a command, stream its captured output as plain text.
/// Non-TTY framed exec only; no terminal emulator (ADR 0002).
@MainActor
@Observable
public final class ExecActionModel {
    public struct Chunk: Sendable, Equatable, Identifiable {
        public let id: Int
        public let text: String
        public let isStderr: Bool
    }

    public private(set) var output: [Chunk] = []
    public private(set) var exitCode: Int?
    public private(set) var isRunning = false
    public private(set) var lastError: Error?

    private let platform: SpritesPlatform
    private let sprite: String
    private var session: (any ExecSession)?
    private var nextChunkID = 0

    public init(platform: SpritesPlatform, sprite: String) {
        self.platform = platform
        self.sprite = sprite
    }

    public func run(_ commandLine: String) async {
        guard !isRunning else { return }
        output = []
        exitCode = nil
        lastError = nil
        isRunning = true
        defer {
            isRunning = false
            session = nil
        }
        do {
            let session = try await platform.exec(
                on: sprite, command: ExecCommand(["sh", "-c", commandLine]))
            self.session = session
            try await session.sendEOF()
            for await event in session.events {
                switch event {
                case .stdout(let data):
                    append(String(decoding: data, as: UTF8.self), isStderr: false)
                case .stderr(let data):
                    append(String(decoding: data, as: UTF8.self), isStderr: true)
                case .exit(let code):
                    exitCode = code
                }
            }
        } catch {
            lastError = error
        }
    }

    public func cancel() async {
        await session?.cancel()
    }

    private func append(_ text: String, isStderr: Bool) {
        output.append(Chunk(id: nextChunkID, text: text, isStderr: isStderr))
        nextChunkID += 1
    }
}
