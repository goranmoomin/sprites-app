import SwiftUI
import SpritesCore

#if os(iOS)
public struct SpriteListView: View {
    @Bindable var session: Session
    let platform: SpritesPlatform
    @State private var model: SpriteListModel
    @State private var showingCreate = false
    @State private var spriteToDelete: String?
    @State private var path: [String] = []
    @Environment(\.scenePhase) private var scenePhase

    /// The app-side saved Claude login, re-read wherever the list itself
    /// refreshes (a login Flow may have saved one in the meantime).
    private let loginStore: any ClaudeLoginStore
    @State private var savedLogin: SavedClaudeLogin?
    @State private var confirmingForget = false

    public init(
        session: Session, platform: SpritesPlatform,
        loginStore: any ClaudeLoginStore = Integrations.claudeCode.loginStore
    ) {
        self.session = session
        self.platform = platform
        self.loginStore = loginStore
        _model = State(initialValue: SpriteListModel(platform: platform, session: session))
    }

    public var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let error = model.lastError {
                    refreshableUnavailable {
                        ContentUnavailableView {
                            Label("Could not load sprites", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(String(describing: error))
                        } actions: {
                            Button("Retry") {
                                Task { await model.refresh() }
                            }
                        }
                    }
                } else if model.hasLoaded && model.sprites.isEmpty {
                    refreshableUnavailable {
                        ContentUnavailableView {
                            Label("No sprites yet", systemImage: "cube")
                        } description: {
                            Text("Create a sprite to get a disposable coding environment.")
                        } actions: {
                            Button("Create Sprite") { showingCreate = true }
                        }
                    }
                } else {
                    List(model.sprites) { sprite in
                        let isDeleting = model.deletingSprites.contains(sprite.name)
                        NavigationLink(value: sprite.name) {
                            SpriteRow(sprite: sprite, isDeleting: isDeleting)
                        }
                            .disabled(isDeleting)
                            .rowAnchor(sprite.name)
                            .swipeActions {
                                if !isDeleting {
                                    Button("Delete", role: .destructive) {
                                        spriteToDelete = sprite.name
                                    }
                                }
                            }
                    }
                    .rowAnchoredConfirmation(
                        selection: $spriteToDelete,
                        title: { "Delete \($0)?" },
                        message: "This permanently destroys its filesystem, services, and checkpoints."
                    ) { sprite in
                        Button("Delete Sprite", role: .destructive) {
                            model.delete(sprite)
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
                ToolbarItem(placement: .secondaryAction) {
                    // The app's one app-level surface: the saved Claude
                    // login and its forget action.
                    Menu {
                        if let savedLogin {
                            Section("Saved Claude login from "
                                + savedLogin.mintedAt.formatted(date: .abbreviated, time: .omitted)) {
                                Button("Forget saved login", role: .destructive) {
                                    confirmingForget = true
                                }
                            }
                        } else {
                            Text("No saved Claude login")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("App options")
                }
            }
            .confirmationDialog(
                "Forget the saved Claude login?",
                isPresented: $confirmingForget, titleVisibility: .visible
            ) {
                Button("Forget", role: .destructive) {
                    loginStore.clear()
                    savedLogin = nil
                }
            } message: {
                Text("This removes the login from this app only. It does not revoke the "
                    + "token, and Sprites already using it stay logged in.")
            }
            .task {
                savedLogin = loginStore.load()
                await model.refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    savedLogin = loginStore.load()
                    Task { await model.refreshOnFocus() }
                }
            }
            .onChange(of: path) { old, new in
                savedLogin = loginStore.load()
                if new.count < old.count {
                    Task { await model.refreshOnFocus() }
                }
            }
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

    /// ContentUnavailableView is not scrollable on its own; wrapping keeps
    /// pull-to-refresh available on the error and empty branches too.
    private func refreshableUnavailable(@ViewBuilder content: () -> some View) -> some View {
        ScrollView {
            content()
                .containerRelativeFrame([.horizontal, .vertical])
        }
        .refreshable { await model.refresh() }
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
