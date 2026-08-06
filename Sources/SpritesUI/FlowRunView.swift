import SwiftUI
import SpritesCore

#if os(iOS)
import UIKit

/// Generic native UI for a Flow run: step list, prompt UI (open-URL button,
/// code paste field, consent), and the raw-output failure surface with
/// retry. No terminal emulator (ADR 0002).
struct FlowRunView: View {
    @State var run: FlowRun
    @Environment(\.dismiss) private var dismiss
    let onFinished: () -> Void

    init(flow: Flow, platform: SpritesPlatform, sprite: String, onFinished: @escaping () -> Void) {
        _run = State(initialValue: FlowRun(flow: flow, platform: platform, sprite: sprite))
        self.onFinished = onFinished
    }

    /// Drives an externally created run (the create-sprite playlist).
    init(run: FlowRun, onFinished: @escaping () -> Void) {
        _run = State(initialValue: run)
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            List {
                stepsSection
                phaseSections
            }
            .navigationTitle(run.flow.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(run.isFinished ? "Done" : "Cancel") {
                        finish()
                    }
                }
            }
            .task { await run.start() }
            .interactiveDismissDisabled(!run.isFinished)
        }
    }

    private func finish() {
        onFinished()
        dismiss()
    }

    private var stepsSection: some View {
        Section("Steps") {
            ForEach(Array(run.flow.steps.enumerated()), id: \.offset) { index, step in
                HStack {
                    stepIcon(index)
                    Text(step.title)
                }
            }
        }
    }

    @ViewBuilder
    private func stepIcon(_ index: Int) -> some View {
        if index < run.currentStepIndex || run.phase == .succeeded {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if index == run.currentStepIndex {
            switch run.phase {
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .cancelled:
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
            default:
                ProgressView().controlSize(.small)
            }
        } else {
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var phaseSections: some View {
        switch run.phase {
        case .waitingForInput:
            if let prompt = run.currentPrompt {
                FlowPromptView(prompt: prompt) { run.respond($0) }
            }
        case .failed:
            Section("What went wrong") {
                if let message = run.failureMessage {
                    Text(message)
                }
                if !run.transcript.isEmpty {
                    ScrollView(.horizontal) {
                        Text(run.transcript)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                Button("Retry") {
                    Task { await run.retry() }
                }
            }
        case .succeeded:
            Section {
                Label("All done", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Done") { finish() }
            }
        case .cancelled:
            Section {
                Text("Stopped. Nothing was changed beyond completed steps.")
                    .foregroundStyle(.secondary)
            }
        case .idle, .running:
            EmptyView()
        }
    }
}

/// Native step UI for one prompt.
struct FlowPromptView: View {
    let prompt: FlowPrompt
    let respond: (FlowResponse) -> Void
    @State private var code = ""
    @State private var pasteboardCount = UIPasteboard.general.changeCount
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        switch prompt {
        case .openURLAndEnterCode(let url, let instructions):
            Section("Sign in") {
                Text(instructions)
                Link(destination: url) {
                    Label("Open sign-in page", systemImage: "safari")
                }
                TextField("Paste code", text: $code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button("Submit code") {
                    respond(.text(code))
                }
                .disabled(code.isEmpty)
            }
            // The sign-in link leaves the app; coming back with a freshly
            // copied code fills the field. The read shows the system paste
            // alert, and nothing is submitted without the button tap.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                let count = UIPasteboard.general.changeCount
                guard count != pasteboardCount else { return }
                pasteboardCount = count
                if let copied = UIPasteboard.general.string {
                    code = copied.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        case .consent(let title, let message, let approveTitle):
            Section(title) {
                Text(message)
                Button(approveTitle) { respond(.approved) }
                Button("Not now", role: .cancel) { respond(.declined) }
            }
        case .t3Pairing(let pairing):
            PairingSectionView(pairing: pairing, requestNewCode: { respond(.reissue) }) {
                respond(.acknowledged)
            }
        }
    }
}
#endif
