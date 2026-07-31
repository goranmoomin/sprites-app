import SwiftUI
import SpritesCore

#if os(iOS)
public struct SpriteListView: View {
    @Bindable var session: Session
    let platform: SpritesPlatform
    @State private var model: SpriteListModel
    @State private var showingCreate = false
    @State private var spriteToDelete: SpriteMetadata?

    public init(session: Session, platform: SpritesPlatform) {
        self.session = session
        self.platform = platform
        _model = State(initialValue: SpriteListModel(platform: platform, session: session))
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let error = model.lastError {
                    ContentUnavailableView {
                        Label("Could not load sprites", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(String(describing: error))
                    } actions: {
                        Button("Retry") {
                            Task { await model.refresh() }
                        }
                    }
                } else if model.hasLoaded && model.sprites.isEmpty {
                    ContentUnavailableView {
                        Label("No sprites yet", systemImage: "cube")
                    } description: {
                        Text("Create a sprite to get a disposable coding environment.")
                    } actions: {
                        Button("Create Sprite") { showingCreate = true }
                    }
                } else {
                    List(model.sprites) { sprite in
                        SpriteRow(sprite: sprite)
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    spriteToDelete = sprite
                                }
                            }
                    }
                    .refreshable { await model.refresh() }
                }
            }
            .navigationTitle("Sprites")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create sprite")
                }
            }
            .task { await model.refresh() }
            .sheet(isPresented: $showingCreate) {
                CreateSpriteView(platform: platform) { _ in
                    Task { await model.refresh() }
                }
            }
            .confirmationDialog(
                "Delete \(spriteToDelete?.name ?? "sprite")?",
                isPresented: Binding(
                    get: { spriteToDelete != nil },
                    set: { if !$0 { spriteToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: spriteToDelete
            ) { sprite in
                Button("Delete Sprite", role: .destructive) {
                    Task { await model.delete(sprite.name) }
                }
            } message: { _ in
                Text("This permanently destroys its filesystem, services, and checkpoints.")
            }
        }
    }
}

struct SpriteRow: View {
    let sprite: SpriteMetadata

    var body: some View {
        HStack {
            Text(sprite.name)
            Spacer()
            Text(sprite.status.rawValue)
                .foregroundStyle(.secondary)
            Image(systemName: "circle.fill")
                .font(.caption2)
                .foregroundStyle(statusColor)
        }
    }

    private var statusColor: Color {
        switch sprite.status {
        case .cold: .gray
        case .warm: .orange
        case .running: .green
        }
    }
}
#endif
