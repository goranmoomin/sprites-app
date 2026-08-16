import SwiftUI
import SpritesCore

#if os(iOS)
struct CreateSpriteView: View {
    @State private var model: CreateSpriteModel
    @State private var createdSprite: SpriteMetadata?
    @Environment(\.dismiss) private var dismiss
    let platform: SpritesPlatform
    let onCreated: (SpriteMetadata) -> Void
    let onFinished: (String) -> Void

    init(
        platform: SpritesPlatform,
        onCreated: @escaping (SpriteMetadata) -> Void,
        onFinished: @escaping (String) -> Void = { _ in }
    ) {
        self.platform = platform
        _model = State(initialValue: CreateSpriteModel(platform: platform))
        self.onCreated = onCreated
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            if let createdSprite {
                // Creation is non-transactional: the sprite already exists;
                // what follows is just the Board of ordinary Flows.
                CreateSpriteBoardView(platform: platform, sprite: createdSprite.name) {
                    dismiss()
                    onFinished(createdSprite.name)
                }
            } else {
                form
            }
        }
        .interactiveDismissDisabled(false)
    }

    private var form: some View {
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
                                createdSprite = created
                            }
                        }
                    }
                    .disabled(model.isCreating)
                }
            }
    }
}
#endif
