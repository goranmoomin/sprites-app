import SwiftUI
import SpritesCore

#if os(iOS)
/// Generic controls for one service: exactly start/stop/restart, logs, and
/// delete. Custom services get nothing more than this.
struct ServiceDetailView: View {
    @Bindable var model: SpriteDetailModel
    let serviceName: String
    let platform: SpritesPlatform
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    private var service: Service? {
        model.services?.first { $0.name == serviceName }
    }

    var body: some View {
        List {
            if let service {
                Section("Definition") {
                    LabeledContent("Command") {
                        Text(([service.cmd] + service.args).joined(separator: " "))
                            .font(.caption.monospaced())
                    }
                    if let dir = service.dir {
                        LabeledContent("Directory", value: dir)
                    }
                    if let port = service.httpPort {
                        LabeledContent("HTTP port", value: String(port))
                    }
                }

                if let state = service.state {
                    Section("State") {
                        LabeledContent("Status", value: state.status)
                        if let pid = state.pid {
                            LabeledContent("PID", value: String(pid))
                        }
                        if let error = state.error {
                            LabeledContent("Error", value: error)
                        }
                        if let count = state.restartCount {
                            LabeledContent("Restarts", value: String(count))
                        }
                        if let next = state.nextRestartAt {
                            LabeledContent("Next restart", value: next.formatted(date: .omitted, time: .standard))
                        }
                    }
                }

                Section {
                    if service.state?.status == "running" {
                        Button("Stop") {
                            Task { await model.stopService(serviceName) }
                        }
                        Button("Restart") {
                            Task { await model.restartService(serviceName) }
                        }
                    } else {
                        Button("Start") {
                            Task { await model.startService(serviceName) }
                        }
                    }
                    NavigationLink("View logs") {
                        ServiceLogsView(platform: platform, sprite: model.sprite, serviceName: serviceName)
                    }
                }

                Section {
                    Button("Delete Service", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            } else {
                Text("Service no longer exists.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(serviceName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete \(serviceName)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Service", role: .destructive) {
                Task {
                    await model.deleteService(serviceName)
                    dismiss()
                }
            }
        }
    }
}

struct ServiceLogsView: View {
    @State private var model: ServiceLogsModel

    init(platform: SpritesPlatform, sprite: String, serviceName: String) {
        _model = State(initialValue: ServiceLogsModel(
            platform: platform, sprite: sprite, serviceName: serviceName))
    }

    var body: some View {
        ScrollView {
            Text(model.logs ?? "Loading...")
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .defaultScrollAnchor(.bottom)
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}
#endif
