import SwiftUI
import SpritesCore

#if os(iOS)
/// Run a single command and see its captured output as plain text.
struct ExecActionView: View {
    @State private var model: ExecActionModel
    @State private var commandLine = ""

    init(platform: SpritesPlatform, sprite: String) {
        _model = State(initialValue: ExecActionModel(platform: platform, sprite: sprite))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.output) { chunk in
                        Text(chunk.text)
                            .font(.caption.monospaced())
                            .foregroundStyle(chunk.isStderr ? Color.red : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let code = model.exitCode {
                        Text("exit status \(code)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding()
                .textSelection(.enabled)
            }
            .defaultScrollAnchor(.bottom)

            Divider()

            HStack {
                TextField("Command", text: $commandLine)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(run)
                if model.isRunning {
                    Button("Cancel") {
                        Task { await model.cancel() }
                    }
                } else {
                    Button("Run", action: run)
                        .disabled(commandLine.isEmpty)
                }
            }
            .padding()
        }
        .navigationTitle("Run Command")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() {
        guard !commandLine.isEmpty, !model.isRunning else { return }
        let command = commandLine
        Task { await model.run(command) }
    }
}
#endif
