import SwiftUI
import SpritesCore

#if os(iOS)
/// The create-sprite second page: the same Board the detail screen shows,
/// on the just-created sprite. Bailing at any point is fine: nothing here
/// is ordered or remembered, and the detail screen offers the same Flows.
struct CreateSpriteBoardView: View {
    @State private var model: SpriteDetailModel
    @State private var activeFlow: Flow?
    let platform: SpritesPlatform
    let onDone: () -> Void

    init(platform: SpritesPlatform, sprite: String, onDone: @escaping () -> Void) {
        self.platform = platform
        _model = State(initialValue: SpriteDetailModel(platform: platform, sprite: sprite))
        self.onDone = onDone
    }

    var body: some View {
        List {
            Section {
                Label(model.sprite, systemImage: "cube")
            } footer: {
                Text("Set up the sprite now, or later from the sprite's screen. Tap an integration to see what it offers.")
            }

            if let board = model.board {
                BoardSections(board: board, blockedReason: model.blockedReason(for:)) { flow in
                    activeFlow = flow
                }
            } else if model.isWaking {
                Section {
                    HStack {
                        ProgressView()
                        Text("Waking...")
                    }
                }
            }

            if let error = model.lastError {
                Section {
                    Text(String(describing: error))
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await model.refresh() }
                    }
                }
            }

            Section {
                Button("Done") { onDone() }
            }
        }
        .navigationTitle("New Sprite")
        .navigationBarTitleDisplayMode(.inline)
        // Setting up a sprite the user just created is a knowing wake:
        // the Board needs deep observation to show tile state.
        .task {
            await model.refresh()
            if model.needsWakeToInspect { await model.wakeToInspect() }
        }
        .sheet(item: $activeFlow) { flow in
            FlowRunView(flow: flow, platform: platform, sprite: model.sprite) {
                Task { await model.refresh() }
            }
        }
    }
}
#endif
