import SwiftUI
import SpritesCore

#if os(iOS)
public struct SpriteListView: View {
    @Bindable var session: Session
    let platform: SpritesPlatform
    @State private var model: SpriteListModel
    @State private var showingCreate = false
    @State private var spriteToDelete: SpriteMetadata?
    @State private var path: [String] = []

    public init(session: Session, platform: SpritesPlatform) {
        self.session = session
        self.platform = platform
        _model = State(initialValue: SpriteListModel(platform: platform, session: session))
    }

    public var body: some View {
        NavigationStack(path: $path) {
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
                        let isDeleting = model.deletingSprites.contains(sprite.name)
                        NavigationLink(value: sprite.name) {
                            SpriteRow(sprite: sprite, isDeleting: isDeleting)
                        }
                            .disabled(isDeleting)
                            .swipeActions {
                                if !isDeleting {
                                    Button("Delete", role: .destructive) {
                                        spriteToDelete = sprite
                                    }
                                }
                            }
                            // Anchored to the row: iOS 26 presents this as a
                            // popover pointing at the source view.
                            .confirmationDialog(
                                "Delete \(sprite.name)?",
                                isPresented: Binding(
                                    get: { spriteToDelete?.name == sprite.name },
                                    set: { if !$0 { spriteToDelete = nil } }
                                ),
                                titleVisibility: .visible
                            ) {
                                Button("Delete Sprite", role: .destructive) {
                                    model.delete(sprite.name)
                                }
                            } message: {
                                Text("This permanently destroys its filesystem, services, and checkpoints.")
                            }
                    }
                    .refreshable { await model.refresh() }
                }
            }
            .navigationTitle("Sprites")
            .navigationDestination(for: String.self) { name in
                SpriteDetailView(platform: platform, sprite: name, session: session) { doomed in
                    await model.delete(doomed).value
                }
            }
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
                } onFinished: { name in
                    // The playlist ends on the new sprite's detail screen.
                    path.append(name)
                }
            }
        }
    }
}

struct SpriteRow: View {
    let sprite: SpriteMetadata
    var isDeleting = false

    var body: some View {
        HStack {
            Text(sprite.name)
            Spacer()
            if isDeleting {
                Text("Deleting...")
                    .foregroundStyle(.secondary)
                ProgressView()
            } else {
                Text(sprite.status.display)
                    .foregroundStyle(.secondary)
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }
        }
        .opacity(isDeleting ? 0.5 : 1)
    }

    private var statusColor: Color {
        switch sprite.status {
        case .cold: .gray
        case .warm: .orange
        case .running: .green
        case .unknown: .secondary
        }
    }
}
#endif
