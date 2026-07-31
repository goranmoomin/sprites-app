import SwiftUI
import SpritesCore

#if os(iOS)
/// The skippable playlist shown right after creating a sprite. Bailing at
/// any point is fine: the detail screen offers the same Flows later.
struct CreateSpritePlaylistView: View {
    @State private var playlist: CreateSpritePlaylist
    @State private var runPresented = false
    let spriteName: String
    let onDone: () -> Void

    init(platform: SpritesPlatform, spriteName: String, onDone: @escaping () -> Void) {
        _playlist = State(initialValue: CreateSpritePlaylist(platform: platform, sprite: spriteName))
        self.spriteName = spriteName
        self.onDone = onDone
    }

    var body: some View {
        List {
            Section {
                Label(spriteName, systemImage: "cube")
            } footer: {
                Text("Set up the sprite now, or skip any step and run it later from the sprite's screen.")
            }

            Section("Set up") {
                ForEach(playlist.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            statusIcon(entry.status)
                            Text(entry.flow.title)
                            Spacer()
                            if entry.status == .pending || isBlocked(entry.status) {
                                Button("Skip") { playlist.skip(entry.id) }
                                    .buttonStyle(.borderless)
                                Button("Start") { start(entry.id) }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        if case .blocked(let reason) = entry.status {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let prerequisite = playlist.prerequisiteEntryID(for: entry.id),
                                let prerequisiteEntry = playlist.entries.first(where: { $0.id == prerequisite })
                            {
                                Button("Run \"\(prerequisiteEntry.flow.title)\" first") {
                                    start(prerequisite)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }

            Section {
                Button(playlist.isFinished ? "Done" : "Finish later") {
                    onDone()
                }
            }
        }
        .navigationTitle("New Sprite")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $runPresented, onDismiss: { playlist.noteCurrentFinished() }) {
            if let run = playlist.currentRun {
                FlowRunView(run: run) {}
            }
        }
    }

    private func start(_ id: String) {
        Task {
            if await playlist.startEntry(id) != nil {
                runPresented = true
            }
        }
    }

    private func isBlocked(_ status: CreateSpritePlaylist.EntryStatus) -> Bool {
        if case .blocked = status { return true }
        return false
    }

    @ViewBuilder
    private func statusIcon(_ status: CreateSpritePlaylist.EntryStatus) -> some View {
        switch status {
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .skipped, .cancelled:
            Image(systemName: "arrow.right.circle").foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.small)
        case .pending, .blocked:
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }
}
#endif
