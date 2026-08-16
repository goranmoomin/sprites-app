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
        /// A Requirement is unmet; `blockedReason` names the products.
        case blocked
    }

    public let flow: Flow
    public private(set) var phase: Phase = .idle
    public private(set) var currentStepIndex = 0
    public private(set) var currentPrompt: FlowPrompt?
    /// Raw CLI output of the current/failed step.
    public private(set) var transcript = ""
    public private(set) var failureMessage: String?
    public private(set) var blockedReason: String?

    private let platform: SpritesPlatform
    private let sprite: String
    private let integrations: [any Integration]
    private var responseContinuation: CheckedContinuation<FlowResponse, Never>?
    private var promptWaiters: [CheckedContinuation<FlowPrompt?, Never>] = []

    public init(
        flow: Flow, platform: SpritesPlatform, sprite: String,
        integrations: [any Integration] = Integrations.all
    ) {
        self.flow = flow
        self.platform = platform
        self.sprite = sprite
        self.integrations = integrations
    }

    public var currentStep: (any FlowStep)? {
        currentStepIndex < flow.steps.count ? flow.steps[currentStepIndex] : nil
    }

    public var isFinished: Bool {
        phase == .succeeded || phase == .failed || phase == .cancelled || phase == .blocked
    }

    public func start() async {
        guard phase == .idle else { return }
        await run(from: 0)
    }

    /// Re-runs the failed step (and the rest of the flow) after a derail,
    /// or re-checks the Requirements after a block.
    public func retry() async {
        switch phase {
        case .failed:
            failureMessage = nil
            await run(from: currentStepIndex)
        case .blocked:
            blockedReason = nil
            await run(from: 0)
        default:
            return
        }
    }

    /// Answers the currently displayed prompt. Clears the prompt right away
    /// so a nextPrompt() loop suspends instead of re-reading it.
    public func respond(_ response: FlowResponse) {
        guard let continuation = responseContinuation else { return }
        responseContinuation = nil
        currentPrompt = nil
        if phase == .waitingForInput { phase = .running }
        continuation.resume(returning: response)
    }

    /// Awaits the next prompt, or nil when the flow finishes without one.
    /// Test seams use this to drive the flow.
    public func nextPrompt() async -> FlowPrompt? {
        if let currentPrompt { return currentPrompt }
        if isFinished { return nil }
        return await withCheckedContinuation { promptWaiters.append($0) }
    }

    private func run(from index: Int) async {
        phase = .running
        // Requirements gate the flow's start only (ADR 0008); a retry after
        // a derail past the first step resumes without re-checking.
        if index == 0,
            let reason = await Integrations.unmetRequirementReason(
                of: flow, on: sprite, platform: platform, among: integrations)
        {
            blockedReason = reason
            phase = .blocked
            resolvePromptWaiters()
            return
        }
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
        return await withCheckedContinuation { responseContinuation = $0 }
    }

    private func resolvePromptWaiters() {
        for waiter in promptWaiters { waiter.resume(returning: nil) }
        promptWaiters = []
    }
}
