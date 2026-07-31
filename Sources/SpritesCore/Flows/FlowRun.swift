import Foundation
import Observation

/// Executes a Flow's steps in order, bridging step prompts to native UI and
/// surfacing failures as the raw output of the derailed step.
@MainActor
@Observable
public final class FlowRun {
    public enum Phase: Equatable {
        case idle
        case running
        case waitingForInput
        case failed
        case cancelled
        case succeeded
    }

    public let flow: Flow
    public private(set) var phase: Phase = .idle
    public private(set) var currentStepIndex = 0
    public private(set) var currentPrompt: FlowPrompt?
    /// Raw CLI output of the current/failed step.
    public private(set) var transcript = ""
    public private(set) var failureMessage: String?

    private let platform: SpritesPlatform
    private let sprite: String
    private var responseContinuation: CheckedContinuation<FlowResponse, Never>?
    private var promptWaiters: [CheckedContinuation<FlowPrompt?, Never>] = []

    public init(flow: Flow, platform: SpritesPlatform, sprite: String) {
        self.flow = flow
        self.platform = platform
        self.sprite = sprite
    }

    public var currentStep: (any FlowStep)? {
        currentStepIndex < flow.steps.count ? flow.steps[currentStepIndex] : nil
    }

    public var isFinished: Bool {
        phase == .succeeded || phase == .failed || phase == .cancelled
    }

    public func start() async {
        guard phase == .idle else { return }
        await run(from: 0)
    }

    /// Re-runs the failed step (and the rest of the flow) after a derail.
    public func retry() async {
        guard phase == .failed else { return }
        failureMessage = nil
        await run(from: currentStepIndex)
    }

    /// Answers the currently displayed prompt.
    public func respond(_ response: FlowResponse) {
        guard let continuation = responseContinuation else { return }
        responseContinuation = nil
        continuation.resume(returning: response)
    }

    /// Awaits the next prompt, or nil when the flow finishes without one.
    /// Test seams and playlist UIs use this to drive the flow.
    public func nextPrompt() async -> FlowPrompt? {
        if let currentPrompt { return currentPrompt }
        if isFinished { return nil }
        return await withCheckedContinuation { promptWaiters.append($0) }
    }

    private func run(from index: Int) async {
        phase = .running
        let context = FlowContext(
            platform: platform,
            sprite: sprite,
            emitOutput: { [weak self] text in
                Task { @MainActor [weak self] in self?.transcript += text }
            },
            promptHandler: { [weak self] prompt in
                await self?.ask(prompt) ?? .declined
            }
        )
        for stepIndex in index..<flow.steps.count {
            currentStepIndex = stepIndex
            transcript = ""
            do {
                try await flow.steps[stepIndex].run(in: context)
            } catch FlowError.declined {
                phase = .cancelled
                resolvePromptWaiters()
                return
            } catch FlowError.failed(let message) {
                failureMessage = message
                phase = .failed
                resolvePromptWaiters()
                return
            } catch {
                failureMessage = String(describing: error)
                phase = .failed
                resolvePromptWaiters()
                return
            }
        }
        phase = .succeeded
        resolvePromptWaiters()
    }

    private func ask(_ prompt: FlowPrompt) async -> FlowResponse {
        currentPrompt = prompt
        phase = .waitingForInput
        for waiter in promptWaiters { waiter.resume(returning: prompt) }
        promptWaiters = []
        let response = await withCheckedContinuation { responseContinuation = $0 }
        currentPrompt = nil
        if phase == .waitingForInput { phase = .running }
        return response
    }

    private func resolvePromptWaiters() {
        for waiter in promptWaiters { waiter.resume(returning: nil) }
        promptWaiters = []
    }
}
