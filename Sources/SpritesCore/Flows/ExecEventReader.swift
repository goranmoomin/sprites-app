import Foundation

/// Sequential consumption of an exec session's events with per-read
/// timeouts, for scripted dialogues against CLI output.
public actor ExecEventReader {
    private var buffered: [ExecEvent] = []
    private var finished = false
    private var waiters: [(id: Int, continuation: CheckedContinuation<ExecEvent?, Never>)] = []
    private var nextWaiterID = 0

    public init(_ session: any ExecSession) {
        Task {
            for await event in session.events { await self.push(event) }
            await self.finish()
        }
    }

    private func push(_ event: ExecEvent) {
        if waiters.isEmpty {
            buffered.append(event)
        } else {
            waiters.removeFirst().continuation.resume(returning: event)
        }
    }

    private func finish() {
        finished = true
        for waiter in waiters { waiter.continuation.resume(returning: nil) }
        waiters = []
    }

    // The wait must resume on task cancellation, or the timeout race in
    // next(within:) would deadlock waiting for its losing child.
    private func nextBufferedOrWait() async -> ExecEvent? {
        if !buffered.isEmpty { return buffered.removeFirst() }
        if finished { return nil }
        let id = nextWaiterID
        nextWaiterID += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                } else {
                    waiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: Int) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: nil)
    }

    /// The next event, nil at end of stream. Throws FlowError.failed on
    /// timeout, carrying a diagnosis for the failure surface.
    public func next(within timeout: Duration) async throws -> ExecEvent? {
        enum Outcome: Sendable {
            case event(ExecEvent?)
            case timedOut
        }
        let outcome = await withTaskGroup(of: Outcome.self) { group in
            group.addTask { .event(await self.nextBufferedOrWait()) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timedOut
            }
            defer { group.cancelAll() }
            return await group.next()!
        }
        switch outcome {
        case .event(let event): return event
        case .timedOut: throw FlowError.failed("timed out waiting for command output")
        }
    }
}
