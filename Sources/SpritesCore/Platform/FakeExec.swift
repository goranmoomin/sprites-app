import Foundation
import Synchronization

/// The script side of a fake exec session: emit output, read what the app
/// sends, and exit. Used to write canned CLI transcripts in tests.
public final class FakeExecIO: Sendable {
    private let record: FakeExecRecord

    init(record: FakeExecRecord) {
        self.record = record
    }

    public func stdout(_ text: String) {
        record.emit(.stdout(Data(text.utf8)))
    }

    public func stderr(_ text: String) {
        record.emit(.stderr(Data(text.utf8)))
    }

    public func exit(_ code: Int) {
        record.exit(code)
    }

    /// Severs the client's socket like iOS suspension killing the
    /// WebSocket: the stream finishes without an exit and sends throw. A
    /// TTY script lives on; a non-TTY one is killed, as on the platform.
    public func dropConnection() {
        record.dropClient()
    }

    /// The next chunk the app sends (stdin or keystrokes), or nil on EOF.
    public func read() async -> String? {
        await record.reader.read()
    }

    /// Reads until a newline or carriage return arrives (a "typed line").
    public func readLine() async -> String? {
        await record.reader.readLine()
    }
}

/// The platform side of a fake session: owns the transcript state and
/// outlives any one socket, like real TTY sessions do.
final class FakeExecRecord: Sendable {
    let id: String
    let sprite: String
    /// Resolved-path rendering, matching the live list endpoint.
    let command: String
    let tty: Bool
    let reader: FakeExecInputReader

    private let inputContinuation: AsyncStream<Data>.Continuation

    private struct State {
        var scrollback = Data()
        var client: FakeExecSession?
        var exitCode: Int?
    }

    private let state = Mutex<State>(State())

    init(id: String, sprite: String, argv: [String], tty: Bool) {
        self.id = id
        self.sprite = sprite
        self.command = "/usr/bin/" + argv.joined(separator: " ")
        self.tty = tty
        let (input, inputContinuation) = AsyncStream.makeStream(of: Data.self)
        self.inputContinuation = inputContinuation
        self.reader = FakeExecInputReader(input)
    }

    var isAlive: Bool {
        state.withLock { $0.exitCode == nil }
    }

    func emit(_ event: ExecEvent) {
        let client: FakeExecSession? = state.withLock { state in
            switch event {
            case .stdout(let data), .stderr(let data):
                state.scrollback.append(data)
            case .exit:
                break
            }
            return state.client
        }
        client?.deliver(event)
    }

    func exit(_ code: Int) {
        let client: FakeExecSession? = state.withLock { state in
            guard state.exitCode == nil else { return nil }
            state.exitCode = code
            defer { state.client = nil }
            return state.client
        }
        client?.deliver(.exit(code))
        client?.finishStream()
        inputContinuation.finish()
    }

    /// SIGTERM semantics: exit 143; a script blocked on read gets EOF.
    func kill() {
        exit(143)
    }

    func dropClient() {
        let client: FakeExecSession? = state.withLock { state in
            defer { state.client = nil }
            return state.client
        }
        client?.sever()
        if !tty { kill() }
    }

    /// Detach one handle (the app closed its socket); the session lives on.
    func detach(_ session: FakeExecSession) {
        state.withLock { state in
            if state.client === session { state.client = nil }
        }
        session.sever()
    }

    /// A new client socket; the scrollback replays first, as one stdout
    /// chunk before any live output (mirrors the server). A record whose
    /// script already exited settles the client immediately rather than
    /// stranding it with a never-finishing stream.
    func makeClient() -> FakeExecSession {
        let session = FakeExecSession(record: self)
        var previous: FakeExecSession?
        state.withLock { state in
            previous = state.client
            if !state.scrollback.isEmpty {
                session.deliver(.stdout(state.scrollback))
            }
            if let exitCode = state.exitCode {
                session.deliver(.exit(exitCode))
                session.finishStream()
            } else {
                state.client = session
            }
        }
        previous?.sever()
        return session
    }

    func sendInput(_ data: Data) {
        inputContinuation.yield(data)
    }

    func finishInput() {
        inputContinuation.finish()
    }
}

public final class FakeExecSession: ExecSession, Sendable {
    public let events: AsyncStream<ExecEvent>
    private let eventsContinuation: AsyncStream<ExecEvent>.Continuation
    private let record: FakeExecRecord
    private let severed = Mutex<Bool>(false)

    init(record: FakeExecRecord) {
        self.record = record
        (events, eventsContinuation) = AsyncStream.makeStream(of: ExecEvent.self)
    }

    public var sessionID: String? {
        get async { record.id }
    }

    func deliver(_ event: ExecEvent) {
        eventsContinuation.yield(event)
    }

    func finishStream() {
        eventsContinuation.finish()
    }

    /// The socket died: the stream ends without an exit and sends throw.
    func sever() {
        severed.withLock { $0 = true }
        eventsContinuation.finish()
    }

    public func send(_ data: Data) async throws {
        guard !severed.withLock({ $0 }) else {
            throw URLError(.networkConnectionLost)
        }
        record.sendInput(data)
    }

    public func sendEOF() async throws {
        record.finishInput()
    }

    public func cancel() async {
        record.detach(self)
    }
}

/// Buffers what the app sends so scripts can consume it line-by-line. Lives
/// on the record, not the socket, so it spans reattaches.
actor FakeExecInputReader {
    private var chunks: [Data] = []
    private var finished = false
    private var waiters: [CheckedContinuation<Data?, Never>] = []
    private var buffer = ""

    init(_ input: AsyncStream<Data>) {
        Task {
            for await chunk in input { await self.push(chunk) }
            await self.finishInput()
        }
    }

    private func push(_ chunk: Data) {
        if waiters.isEmpty {
            chunks.append(chunk)
        } else {
            waiters.removeFirst().resume(returning: chunk)
        }
    }

    private func finishInput() {
        finished = true
        for waiter in waiters { waiter.resume(returning: nil) }
        waiters = []
    }

    private func nextChunk() async -> Data? {
        if !chunks.isEmpty { return chunks.removeFirst() }
        if finished { return nil }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func read() async -> String? {
        if !buffer.isEmpty {
            defer { buffer = "" }
            return buffer
        }
        return await nextChunk().map { String(decoding: $0, as: UTF8.self) }
    }

    func readLine() async -> String? {
        while true {
            if let index = buffer.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
                let line = String(buffer[..<index])
                buffer = String(buffer[buffer.index(after: index)...])
                return line
            }
            guard let chunk = await nextChunk() else {
                // EOF: whatever is buffered is the final line.
                defer { buffer = "" }
                return buffer.isEmpty ? nil : buffer
            }
            buffer += String(decoding: chunk, as: UTF8.self)
        }
    }
}
