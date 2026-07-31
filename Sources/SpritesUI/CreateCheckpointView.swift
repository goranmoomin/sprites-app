import SwiftUI
import SpritesCore

#if os(iOS)
struct CreateCheckpointView: View {
    @Bindable var model: SpriteDetailModel
    @State private var comment = ""
    @State private var isCreating = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Comment", text: $comment)
                } footer: {
                    Text("Saves the sprite's filesystem so you can roll back after risky work.")
                }
                if isCreating {
                    Section("Progress") {
                        ForEach(Array(model.checkpointProgress.enumerated()), id: \.offset) { _, event in
                            Text(event.message ?? event.type)
                                .font(.caption.monospaced())
                        }
                    }
                }
            }
            .navigationTitle("New Checkpoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        isCreating = true
                        Task {
                            await model.createCheckpoint(comment: comment)
                            dismiss()
                        }
                    }
                    .disabled(isCreating)
                }
            }
        }
    }
}
#endif
