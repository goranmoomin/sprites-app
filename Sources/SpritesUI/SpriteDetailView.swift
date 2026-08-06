import SwiftUI
import SpritesCore

#if os(iOS)
public struct SpriteDetailView: View {
    @State private var model: SpriteDetailModel
    @State private var showingCreateService = false
    @State private var activeFlow: Flow?
    @State private var showingCreateCheckpoint = false
    @State private var checkpointToRestore: Checkpoint?
    /// Delete ownership lives with the sprite list model; this seam calls
    /// through to it and reports the failure, if any.
    private let deleteSprite: (String) async -> Error?
    @State private var confirmingDelete = false
    @State private var isDeletingSprite = false
    @State private var deleteError: Error?
    @Environment(\.dismiss) private var dismiss

    private let platform: SpritesPlatform

    public init(
        platform: SpritesPlatform, sprite: String, session: Session?,
        deleteSprite: @escaping (String) async -> Error?
    ) {
        self.platform = platform
        self.deleteSprite = deleteSprite
        _model = State(initialValue: SpriteDetailModel(
            platform: platform, sprite: sprite, session: session))
    }

    public var body: some View {
        List {
            statusSection
            if model.needsWakeToInspect {
                wakeSection
            } else {
                deepSections
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
                if isDeletingSprite {
                    HStack {
                        ProgressView()
                        Text("Deleting...")
                    }
                } else {
                    Button("Delete Sprite", role: .destructive) {
                        confirmingDelete = true
                    }
                    // Anchored to the button: iOS 26 presents this as a
                    // popover pointing at the source view.
                    .confirmationDialog(
                        "Delete \(model.sprite)?", isPresented: $confirmingDelete,
                        titleVisibility: .visible
                    ) {
                        Button("Delete Sprite", role: .destructive) {
                            Task { await runDelete() }
                        }
                    } message: {
                        Text("This permanently destroys its filesystem, services, and checkpoints.")
                    }
                }
                if let deleteError {
                    Text(String(describing: deleteError))
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(model.sprite)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refresh() }
        .refreshable { await model.refresh() }
        .sheet(isPresented: $showingCreateService) {
            CreateServiceView(platform: platform, sprite: model.sprite) {
                Task { await model.refresh() }
            }
        }
        .sheet(item: $activeFlow) { flow in
            FlowRunView(flow: flow, platform: platform, sprite: model.sprite) {
                Task { await model.refresh() }
            }
        }
        .sheet(isPresented: $showingCreateCheckpoint) {
            CreateCheckpointView(model: model)
        }
        .confirmationDialog(
            "Restore \(checkpointToRestore?.id ?? "checkpoint")?",
            isPresented: Binding(
                get: { checkpointToRestore != nil },
                set: { if !$0 { checkpointToRestore = nil } }
            ),
            titleVisibility: .visible,
            presenting: checkpointToRestore
        ) { checkpoint in
            Button("Restore Checkpoint", role: .destructive) {
                Task { await model.restoreCheckpoint(id: checkpoint.id) }
            }
        } message: { _ in
            Text("Restore is destructive: it rolls back agent logins, services, and pairing made after this checkpoint.")
        }
    }

    private func runDelete() async {
        isDeletingSprite = true
        defer { isDeletingSprite = false }
        deleteError = await deleteSprite(model.sprite)
        if deleteError == nil {
            dismiss()
        }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Status", value: model.metadata?.status.display ?? "...")
            if let url = model.metadata?.url {
                LabeledContent("URL") {
                    Text(url.absoluteString)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            LabeledContent("URL visibility", value: model.metadata?.urlVisibility.rawValue ?? "...")
        }
    }

    private var wakeSection: some View {
        Section {
            if model.isWaking {
                HStack {
                    ProgressView()
                    Text("Waking...")
                }
            } else {
                Button {
                    Task { await model.wakeToInspect() }
                } label: {
                    Label("Wake to inspect", systemImage: "sun.max")
                }
            }
        } footer: {
            Text("Inspecting services, tasks, and checkpoints wakes the sprite. Viewing this screen has not.")
        }
    }

    @Environment(\.openURL) private var openURL

    @ViewBuilder
    private var deepSections: some View {
        if let lines = model.integrationLines, !lines.isEmpty {
            Section("Integrations") {
                ForEach(lines) { line in
                    LabeledContent(line.title) {
                        HStack {
                            Text(line.summary)
                            Image(systemName: line.isReady ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(line.isReady ? Color.green : Color.secondary)
                        }
                    }
                }
                ForEach(model.offeredFlows ?? [], id: \.id) { flow in
                    Button(flow.title) {
                        activeFlow = flow
                    }
                }
            }
        }

        Section("Actions") {
            ForEach(model.actions ?? []) { action in
                switch action.kind {
                case .openURL(let url):
                    Button(action.title) {
                        openURL(url)
                    }
                case .runCommand:
                    NavigationLink {
                        ExecActionView(platform: platform, sprite: model.sprite)
                    } label: {
                        Text(action.title)
                    }
                }
            }
        }

        Section {
            if let services = model.services, !services.isEmpty {
                ForEach(services) { service in
                    NavigationLink {
                        ServiceDetailView(model: model, serviceName: service.name, platform: platform)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(service.name)
                            Text(([service.cmd] + service.args).joined(separator: " "))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if let state = service.state {
                                Text(state.status.display + (state.pid.map { " (pid \($0))" } ?? ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("No services")
                    .foregroundStyle(.secondary)
            }
            Button {
                showingCreateService = true
            } label: {
                Label("New service", systemImage: "plus")
            }
        } header: {
            Text("Services")
        }

        Section {
            if let tasks = model.tasks, !tasks.isEmpty {
                ForEach(tasks) { task in
                    LabeledContent(task.name) {
                        if let expires = task.expiresAt {
                            Text("expires \(expires.formatted(date: .omitted, time: .standard))")
                        }
                    }
                }
            } else {
                Text("No live tasks")
                    .foregroundStyle(.secondary)
            }
            if model.keepAliveTask == nil {
                Button("Keep active for an hour") {
                    Task { await model.keepActive() }
                }
            } else {
                Button("Extend keep-alive") {
                    Task { await model.keepActive() }
                }
                Button("Release keep-alive", role: .destructive) {
                    Task { await model.releaseKeepAlive() }
                }
            }
        } header: {
            Text("Tasks")
        } footer: {
            Text("A keep-alive is a named platform task this app holds to stop the sprite from pausing.")
        }

        Section {
            if model.manualCheckpoints.isEmpty {
                Text("No checkpoints")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.manualCheckpoints) { checkpoint in
                    LabeledContent(checkpoint.id, value: checkpoint.comment ?? "")
                        .swipeActions {
                            Button("Restore") {
                                checkpointToRestore = checkpoint
                            }
                            .tint(.orange)
                        }
                }
            }
            Button {
                showingCreateCheckpoint = true
            } label: {
                Label("New checkpoint", systemImage: "camera")
            }
            if !model.automaticCheckpoints.isEmpty {
                DisclosureGroup("Automatic checkpoints") {
                    ForEach(model.automaticCheckpoints) { checkpoint in
                        LabeledContent(checkpoint.id, value: checkpoint.comment ?? "")
                    }
                }
            }
        } header: {
            Text("Checkpoints")
        } footer: {
            Text("Swipe a checkpoint to restore it.")
        }

        if !model.checkpointProgress.isEmpty {
            Section("Checkpoint progress") {
                ForEach(Array(model.checkpointProgress.enumerated()), id: \.offset) { _, event in
                    Text(event.message ?? event.type)
                        .font(.caption.monospaced())
                }
            }
        }
    }
}
#endif
