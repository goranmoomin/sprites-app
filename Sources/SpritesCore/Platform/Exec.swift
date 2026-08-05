import Foundation

/// A command to run inside a Sprite. `tty: false` uses framed streams
/// (preferred); `tty: true` drives a PTY headlessly (ADR 0002).
public struct ExecCommand: Sendable, Equatable {
    public var argv: [String]
    public var tty: Bool
    public var env: [String: String]
    public var dir: String?
    /// PTY size (TTY mode only). The platform PTY starts 0x0 otherwise.
    public var rows: Int?
    public var cols: Int?

    public init(
        _ argv: [String], tty: Bool = false, env: [String: String] = [:], dir: String? = nil,
        rows: Int? = nil, cols: Int? = nil
    ) {
        self.argv = argv
        self.tty = tty
        self.env = env
        self.dir = dir
        self.rows = rows
        self.cols = cols
    }
}

public enum ExecEvent: Sendable, Equatable {
    /// Output. In TTY mode all output (a raw byte stream) arrives as stdout.
    case stdout(Data)
    case stderr(Data)
    case exit(Int)
}

/// A live exec session: an event stream plus stdin/keystrokes going back.
public protocol ExecSession: AnyObject, Sendable {
    var events: AsyncStream<ExecEvent> { get }
    /// The platform's identity for this session (a recyclable PID string,
    /// observed live), for attach-after-drop. Nil if the stream ends first.
    var sessionID: String? { get async }
    func send(_ data: Data) async throws
    func sendEOF() async throws
    func cancel() async
}

/// One entry of the platform's active-session list. `command` is the
/// resolved executable path plus args (observed live), so match by suffix.
public struct ExecSessionSummary: Sendable, Equatable {
    public var id: String
    public var command: String

    public init(id: String, command: String) {
        self.id = id
        self.command = command
    }
}

/// Captured output of a one-shot command.
public struct ExecResult: Sendable, Equatable {
    public var stdout: Data
    public var stderr: Data
    public var exitCode: Int

    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }

    public init(stdout: Data = Data(), stderr: Data = Data(), exitCode: Int) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

extension SpritesPlatform {
    /// Runs a one-shot non-TTY command and captures its output.
    public func runCapturing(
        on sprite: String, _ argv: [String],
        env: [String: String] = [:], dir: String? = nil
    ) async throws -> ExecResult {
        let session = try await exec(on: sprite, command: ExecCommand(argv, env: env, dir: dir))
        try await session.sendEOF()
        var result = ExecResult(exitCode: -1)
        for await event in session.events {
            switch event {
            case .stdout(let data): result.stdout.append(data)
            case .stderr(let data): result.stderr.append(data)
            case .exit(let code): result.exitCode = code
            }
        }
        return result
    }
}

/// The binary framing of the exec WebSocket protocol. In non-TTY mode each
/// frame is prefixed with a stream ID byte; TTY mode is raw bytes.
public enum ExecFrame {
    static let stdin: UInt8 = 0
    static let stdout: UInt8 = 1
    static let stderr: UInt8 = 2
    static let exit: UInt8 = 3
    static let stdinEOF: UInt8 = 4

    public static func decode(_ data: Data, tty: Bool) -> ExecEvent? {
        if tty { return .stdout(data) }
        guard let id = data.first else { return nil }
        let payload = data.dropFirst()
        switch id {
        case stdout: return .stdout(Data(payload))
        case stderr: return .stderr(Data(payload))
        case exit: return .exit(Int(payload.first ?? 0))
        default: return nil
        }
    }

    public static func encodeStdin(_ data: Data, tty: Bool) -> Data {
        if tty { return data }
        return Data([stdin]) + data
    }

    public static var encodedStdinEOF: Data { Data([stdinEOF]) }
}
