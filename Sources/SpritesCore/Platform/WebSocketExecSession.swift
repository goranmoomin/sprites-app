import Foundation
import Synchronization

/// A live exec session over the platform's WebSocket protocol. Binary frames
/// carry stream-ID-prefixed data in non-TTY mode and raw bytes in TTY mode;
/// text frames carry JSON control messages (session_info, exit).
final class WebSocketExecSession: ExecSession, Sendable {
    let events: AsyncStream<ExecEvent>

    private let task: URLSessionWebSocketTask
    private let tty: Bool
    private let continuation: AsyncStream<ExecEvent>.Continuation
    // Output frames can trail the exit frame, so exit is held back until
    // the server closes the connection (observed live; matches the SDKs).
    // Mutex, not receive-callback confinement: cancel() also reaches this
    // from the caller's isolation, racing the delegate queue.
    private let pendingExit = Mutex<Int?>(nil)

    convenience init(session: URLSession, request: URLRequest, tty: Bool) {
        self.init(task: session.webSocketTask(with: request), tty: tty)
    }

    init(task: URLSessionWebSocketTask, tty: Bool) {
        self.task = task
        self.tty = tty
        (events, continuation) = AsyncStream.makeStream(of: ExecEvent.self)
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
                        pendingExit.withLock { $0 = code }
                    } else {
                        continuation.yield(event)
                    }
                }
                receiveLoop()
            case .success(.string(let text)):
                if let message = try? JSONDecoder().decode(ControlMessage.self, from: Data(text.utf8)),
                    message.type == "exit"
                {
                    pendingExit.withLock { $0 = message.exit_code ?? 0 }
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
        // Atomic take: when a cancel races the socket-failure callback, only
        // one of the two concurrent finishes yields the exit event.
        if let code = pendingExit.withLock({ code in
            defer { code = nil }
            return code
        }) {
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
