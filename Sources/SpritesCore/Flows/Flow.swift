import Foundation

/// A guided, possibly interactive, multi-step operation an Integration
/// offers on a Sprite. Steps prefer non-interactive exec; interactive steps
/// drive a PTY headlessly behind native UI (ADR 0002).
public struct Flow: Sendable, Identifiable {
    public let id: String
    public let title: String
    /// All must be met before the first step runs; checked once by FlowRun.
    public let requires: [Requirement]
    public let steps: [any FlowStep]

    public init(id: String, title: String, requires: [Requirement] = [], steps: [any FlowStep]) {
        self.id = id
        self.title = title
        self.requires = requires
        self.steps = steps
    }
}

public protocol FlowStep: Sendable {
    var id: String { get }
    var title: String { get }
    func run(in context: FlowContext) async throws
}

/// Native step UI requests. No terminal emulator exists; interactive CLI
/// dialogues surface as these prompts. Integration-neutral cases are
/// unprefixed; bespoke integration screens are welcome, prefixed and homed
/// with their owner (ADR 0002).
public enum FlowPrompt: Sendable, Equatable {
    /// Show an open-URL button and a code paste field.
    case openURLAndEnterCode(url: URL, instructions: String)
    /// The inverse: show an open-URL button and OUR code, prominent and
    /// copyable, for the user to type into that page (gh's device flow).
    /// The step keeps running underneath while this shows.
    case openURLAndShowCode(url: URL, code: String, instructions: String)
    /// Open a page, do something there, come back: an external
    /// precondition fixed in a web console (enable Serve or MagicDNS on a
    /// tailnet). The step re-checks on acknowledge.
    case openURL(url: URL, instructions: String)
    /// An explicit consent gate (e.g. making the sprite URL public).
    case consent(title: String, message: String, approveTitle: String)
    /// Show the T3 Pairing credential (defined with the T3 integration).
    case t3Pairing(T3Pairing)
    /// Show the minted Claude setup-token (homed with the Claude Code
    /// integration's login Flow).
    case claudeMintedToken(token: String)
}

public enum FlowResponse: Sendable, Equatable {
    case text(String)
    case approved
    case declined
    case acknowledged
    /// Ask the prompting step to mint a fresh credential and prompt again
    /// (a Pairing is single-use with a short TTL).
    case reissue
}

public enum FlowError: Error, Equatable {
    /// The step failed; the raw CLI output is surfaced by the run.
    case failed(String)
    /// The user declined a consent gate; the flow stops without failure noise.
    case declined
}

/// What a running step can do: talk to the platform, append raw output to
/// the failure surface, and ask the user through native step UI.
public struct FlowContext: Sendable {
    public let platform: SpritesPlatform
    public let sprite: String
    let emitOutput: @Sendable (String) -> Void
    let promptHandler: @Sendable (FlowPrompt) async -> FlowResponse

    /// Appends raw CLI output; shown as text if the step derails.
    public func output(_ text: String) {
        emitOutput(text)
    }

    public func prompt(_ prompt: FlowPrompt) async -> FlowResponse {
        await promptHandler(prompt)
    }
}
