import SwiftUI
import SpritesCore

#if os(iOS)
public struct SpriteDetailView: View {
    @State private var model: SpriteDetailModel
    @State private var showingCreateService = false
    private let onDeleted: () -> Void
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    private let platform: SpritesPlatform

    public init(
        platform: SpritesPlatform, spriteName: String, session: Session?,
        onDeleted: @escaping () -> Void = {}
    ) {
        self.platform = platform
        self.onDeleted = onDeleted
        _model = State(initialValue: SpriteDetailModel(
            platform: platform, spriteName: spriteName, session: session))
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
                Button("Delete Sprite", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .navigationTitle(model.spriteName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refresh() }
        .refreshable { await model.refresh() }
        .sheet(isPresented: $showingCreateService) {
            CreateServiceView(platform: platform, spriteName: model.spriteName) {
                Task { await model.refresh() }
            }
        }
        .confirmationDialog(
            "Delete \(model.spriteName)?", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete Sprite", role: .destructive) {
                Task {
                    if await model.deleteSprite() {
                        onDeleted()
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This permanently destroys its filesystem, services, and checkpoints.")
        }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Status", value: model.metadata?.status.rawValue ?? "...")
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

    @ViewBuilder
    private var deepSections: some View {
        Section("Actions") {
            NavigationLink {
                ExecActionView(platform: platform, spriteName: model.spriteName)
            } label: {
                Label("Run command", systemImage: "terminal")
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
                                Text(state.status + (state.pid.map { " (pid \($0))" } ?? ""))
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

        Section("Tasks") {
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
        }

        Section("Checkpoints") {
            if let checkpoints = model.checkpoints, !checkpoints.isEmpty {
                ForEach(checkpoints) { checkpoint in
                    LabeledContent(checkpoint.id, value: checkpoint.comment ?? "")
                }
            } else {
                Text("No checkpoints")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
