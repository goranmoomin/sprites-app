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

    private struct State {
        // Output frames can trail the exit frame, so exit is held back until
        // the server closes the connection (observed live; matches the SDKs).
        var pendingExit: Int?
        // session_info is the first frame on connect and attach (observed
        // live); resolution also flips at stream end so waiters never hang.
        var idResolved = false
        var id: String?
        var idWaiters: [CheckedContinuation<String?, Never>] = []
    }

    // Mutex, not receive-callback confinement: cancel() and sessionID reach
    // this from the caller's isolation, racing the delegate queue.
    private let state = Mutex<State>(State())

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

    var sessionID: String? {
        get async {
            await withCheckedContinuation { waiter in
                enum Answer {
                    case now(String?)
                    case later
                }
                let answer: Answer = state.withLock { state in
                    if state.idResolved { return .now(state.id) }
                    state.idWaiters.append(waiter)
                    return .later
                }
                if case .now(let id) = answer {
                    waiter.resume(returning: id)
                }
            }
        }
    }

    private func receiveLoop() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.data(let data)):
                if let event = ExecFrame.decode(data, tty: tty) {
                    if case .exit(let code) = event {
                        state.withLock { $0.pendingExit = code }
                    } else {
                        continuation.yield(event)
                    }
                }
                receiveLoop()
            case .success(.string(let text)):
                if let message = try? JSONDecoder().decode(ControlMessage.self, from: Data(text.utf8)) {
                    handle(message)
                }
                receiveLoop()
            case .success:
                receiveLoop()
            case .failure:
                finish()
            }
        }
    }

    private func handle(_ message: ControlMessage) {
        switch message.type {
        case "exit":
            state.withLock { $0.pendingExit = message.exit_code ?? 0 }
        case "session_info":
            let waiters = state.withLock { state in
                state.idResolved = true
                state.id = message.session_id
                defer { state.idWaiters = [] }
                return state.idWaiters
            }
            for waiter in waiters { waiter.resume(returning: message.session_id) }
        default:
            break
        }
    }

    private func finish() {
        // Atomic take: when a cancel races the socket-failure callback, only
        // one of the two concurrent finishes yields the exit event.
        let (exit, waiters, id) = state.withLock { state in
            defer {
                state.pendingExit = nil
                state.idResolved = true
                state.idWaiters = []
            }
            return (state.pendingExit, state.idWaiters, state.id)
        }
        if let exit {
            continuation.yield(.exit(exit))
        }
        for waiter in waiters { waiter.resume(returning: id) }
        continuation.finish()
        task.cancel(with: .normalClosure, reason: nil)
    }

    private struct ControlMessage: Decodable {
        var type: String
        var exit_code: Int?
        var session_id: String?
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
