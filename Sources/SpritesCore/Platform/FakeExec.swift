import Foundation

/// The script side of a fake exec session: emit output, read what the app
/// sends, and exit. Used to write canned CLI transcripts in tests.
public final class FakeExecIO: Sendable {
    private let eventsContinuation: AsyncStream<ExecEvent>.Continuation
    private let reader: InputReader

    init(
        eventsContinuation: AsyncStream<ExecEvent>.Continuation,
        input: AsyncStream<Data>
    ) {
        self.eventsContinuation = eventsContinuation
        self.reader = InputReader(input)
    }

    public func stdout(_ text: String) {
        eventsContinuation.yield(.stdout(Data(text.utf8)))
    }

    public func stderr(_ text: String) {
        eventsContinuation.yield(.stderr(Data(text.utf8)))
    }

    public func exit(_ code: Int) {
        eventsContinuation.yield(.exit(code))
        eventsContinuation.finish()
    }

    /// The next chunk the app sends (stdin or keystrokes), or nil on EOF.
    public func read() async -> String? {
        await reader.read()
    }

    /// Reads until a newline or carriage return arrives (a "typed line").
    public func readLine() async -> String? {
        await reader.readLine()
    }

    private actor InputReader {
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
}

public final class FakeExecSession: ExecSession, @unchecked Sendable {
    public let events: AsyncStream<ExecEvent>
    private let inputContinuation: AsyncStream<Data>.Continuation
    private let eventsContinuation: AsyncStream<ExecEvent>.Continuation

    init(script: @escaping @Sendable (FakeExecIO) async -> Void) {
        let (events, eventsContinuation) = AsyncStream.makeStream(of: ExecEvent.self)
        let (input, inputContinuation) = AsyncStream.makeStream(of: Data.self)
        self.events = events
        self.eventsContinuation = eventsContinuation
        self.inputContinuation = inputContinuation
        let io = FakeExecIO(eventsContinuation: eventsContinuation, input: input)
        Task { await script(io) }
    }

    public func send(_ data: Data) async throws {
        inputContinuation.yield(data)
    }

    public func sendEOF() async throws {
        inputContinuation.finish()
    }

    public func cancel() async {
        eventsContinuation.finish()
        inputContinuation.finish()
    }
}
