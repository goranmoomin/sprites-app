import Foundation

/// A live exec session over the platform's WebSocket protocol. Binary frames
/// carry stream-ID-prefixed data in non-TTY mode and raw bytes in TTY mode;
/// text frames carry JSON control messages (session_info, exit).
final class WebSocketExecSession: NSObject, ExecSession, @unchecked Sendable {
    let events: AsyncStream<ExecEvent>

    private let task: URLSessionWebSocketTask
    private let tty: Bool
    private let continuation: AsyncStream<ExecEvent>.Continuation
    // Output frames can trail the exit frame, so exit is held back until
    // the server closes the connection (observed live; matches the SDKs).
    private var pendingExit: Int?

    convenience init(session: URLSession, request: URLRequest, tty: Bool) {
        self.init(task: session.webSocketTask(with: request), tty: tty)
    }

    init(task: URLSessionWebSocketTask, tty: Bool) {
        self.task = task
        self.tty = tty
        (events, continuation) = AsyncStream.makeStream(of: ExecEvent.self)
        super.init()
        task.resume()
        receiveLoop()
    }

    private func receiveLoop() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.data(let data)):
                if let event = ExecFrame.decode(data, tty: tty) {
                    if case .exit(let code) = event {
                        pendingExit = code
                    } else {
                        continuation.yield(event)
                    }
                }
                receiveLoop()
            case .success(.string(let text)):
                if let message = try? JSONDecoder().decode(ControlMessage.self, from: Data(text.utf8)),
                    message.type == "exit"
                {
                    pendingExit = message.exit_code ?? 0
                }
                receiveLoop()
            case .success:
                receiveLoop()
            case .failure:
                finish()
            }
        }
    }

    private func finish() {
        if let code = pendingExit {
            pendingExit = nil
            continuation.yield(.exit(code))
        }
        continuation.finish()
        task.cancel(with: .normalClosure, reason: nil)
    }

    private struct ControlMessage: Decodable {
        var type: String
        var exit_code: Int?
    }

    func send(_ data: Data) async throws {
        try await task.send(.data(ExecFrame.encodeStdin(data, tty: tty)))
    }

    func sendEOF() async throws {
        guard !tty else { return }
        // Best-effort: a fast command can exit and close the socket before
        // the EOF frame lands (observed live); that is not a failure.
        try? await task.send(.data(ExecFrame.encodedStdinEOF))
    }

    func cancel() async {
        finish()
    }
}
