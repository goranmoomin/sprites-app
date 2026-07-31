import SwiftUI
import SpritesCore

#if os(iOS)
struct CreateSpriteView: View {
    @State private var model: CreateSpriteModel
    @Environment(\.dismiss) private var dismiss
    let onCreated: (SpriteMetadata) -> Void

    init(platform: SpritesPlatform, onCreated: @escaping (SpriteMetadata) -> Void) {
        _model = State(initialValue: CreateSpriteModel(platform: platform))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Name", text: $model.name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            model.suggestAnotherName()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Suggest another name")
                    }
                } footer: {
                    Text("Edit the suggested name or keep it.")
                }

                if let error = model.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Sprite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if let created = await model.create() {
                                onCreated(created)
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
