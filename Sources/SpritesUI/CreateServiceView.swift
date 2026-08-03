import SwiftUI
import SpritesCore

#if os(iOS)
/// The general create-service Flow. Arguments are entered one per line and
/// submitted as an array; there is no shell-string command input.
struct CreateServiceView: View {
    @State private var model: CreateServiceModel
    @State private var argumentsText = ""
    @State private var environmentText = ""
    @State private var httpPortText = ""
    @State private var needsText = ""
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void

    init(platform: SpritesPlatform, sprite: String, onCreated: @escaping () -> Void) {
        _model = State(initialValue: CreateServiceModel(platform: platform, sprite: sprite))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Service") {
                    TextField("Name", text: $model.name)
                    TextField("Executable path", text: $model.executable)
                        .font(.body.monospaced())
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Section {
                    TextField("Arguments", text: $argumentsText, axis: .vertical)
                        .font(.body.monospaced())
                        .lineLimit(3...6)
                } header: {
                    Text("Arguments (one per line)")
                }

                Section("Options") {
                    TextField("Working directory", text: $model.workingDirectory)
                        .font(.body.monospaced())
                    TextField("HTTP port", text: $httpPortText)
                        .keyboardType(.numberPad)
                    TextField("Needs (services, one per line)", text: $needsText, axis: .vertical)
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Section {
                    TextField("Environment", text: $environmentText, axis: .vertical)
                        .font(.body.monospaced())
                        .lineLimit(3...6)
                } header: {
                    Text("Environment (KEY=VALUE, one per line)")
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                if !model.progress.isEmpty {
                    Section("Progress") {
                        ForEach(Array(model.progress.enumerated()), id: \.offset) { _, event in
                            HStack {
                                Text(event.type)
                                    .font(.caption.bold())
                                Text(event.message ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let error = model.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        model.arguments = argumentsText
                            .split(separator: "\n").map(String.init)
                            .filter { !$0.isEmpty }
                        model.environment = Dictionary(
                            uniqueKeysWithValues: environmentText
                                .split(separator: "\n")
                                .compactMap { line -> (String, String)? in
                                    guard let eq = line.firstIndex(of: "=") else { return nil }
                                    return (String(line[..<eq]), String(line[line.index(after: eq)...]))
                                })
                        model.httpPort = Int(httpPortText)
                        model.needs = needsText.split(separator: "\n").map(String.init)
                            .filter { !$0.isEmpty }
                        Task {
                            if await model.create() {
                                onCreated()
                                dismiss()
                            }
                        }
                    }
                    .disabled(model.isCreating)
                }
            }
        }
    }
}
#endif
