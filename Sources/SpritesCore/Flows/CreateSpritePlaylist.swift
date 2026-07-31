import Foundation
import Observation

/// The skippable playlist of ordinary Flows offered after creating a
/// sprite: coding-agent logins first, then control-plane setup. Every entry
/// is the identical Flow the detail screen launches; interrupting at any
/// point leaves a perfectly consistent sprite (no draft state, no cleanup).
@MainActor
@Observable
public final class CreateSpritePlaylist {
    public enum EntryStatus: Equatable {
        case pending
        case running
        case succeeded
        case failed
        case skipped
        case cancelled
        /// A declared dependency is unmet; the reason names the prerequisite.
        case blocked(String)
    }

    public struct Entry: Identifiable {
        public let flow: Flow
        public let integration: any Integration
        public var status: EntryStatus = .pending

        public var id: String { flow.id }
    }

    public private(set) var entries: [Entry]
    public private(set) var currentRun: FlowRun?

    private let platform: SpritesPlatform
    private let sprite: String
    private var currentEntryID: String?

    public init(platform: SpritesPlatform, sprite: String) {
        self.platform = platform
        self.sprite = sprite
        self.entries = [
            Entry(flow: Integrations.claudeCode.loginFlow(), integration: Integrations.claudeCode),
            Entry(flow: Integrations.t3Code.setupFlow(), integration: Integrations.t3Code),
        ]
    }

    public var nextPendingID: String? {
        entries.first {
            if case .blocked = $0.status { return true }
            return $0.status == .pending
        }?.id
    }

    public var isFinished: Bool {
        entries.allSatisfy { entry in
            switch entry.status {
            case .succeeded, .skipped, .failed, .cancelled: true
            case .pending, .running, .blocked: false
            }
        }
    }

    /// Starts an entry's flow, or blocks it when a declared dependency is
    /// unmet. The returned run is driven by the caller (the flow UI).
    public func startEntry(_ id: String) async -> FlowRun? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        if entries[index].integration.requirements.contains(.loggedInCodingAgent) {
            let anyReady = await codingAgentReady()
            guard anyReady else {
                entries[index].status = .blocked(
                    "This needs a logged-in coding agent on the sprite. "
                        + "Run the coding agent login first, or skip for now.")
                return nil
            }
        }
        entries[index].status = .running
        let run = FlowRun(flow: entries[index].flow, platform: platform, sprite: sprite)
        currentRun = run
        currentEntryID = id
        return run
    }

    /// Records the outcome of the current run once its UI is done with it.
    public func noteCurrentFinished() {
        guard let id = currentEntryID, let run = currentRun,
            let index = entries.firstIndex(where: { $0.id == id })
        else { return }
        entries[index].status =
            switch run.phase {
            case .succeeded: .succeeded
            case .cancelled: .cancelled
            case .failed: .failed
            default: .pending
            }
        currentRun = nil
        currentEntryID = nil
    }

    public func skip(_ id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = .skipped
    }

    /// The entry that satisfies a blocked entry's dependency, if any.
    public func prerequisiteEntryID(for id: String) -> String? {
        guard let entry = entries.first(where: { $0.id == id }),
            entry.integration.requirements.contains(.loggedInCodingAgent)
        else { return nil }
        return entries.first { $0.integration.role == .codingAgent }?.id
    }

    private func codingAgentReady() async -> Bool {
        for integration in Integrations.all where integration.role == .codingAgent {
            let status = try? await integration.observeStatus(
                on: sprite, services: [], platform: platform)
            if status?.isReady == true { return true }
        }
        return false
    }
}
