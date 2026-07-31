import SwiftUI
import SpritesCore

#if os(iOS)
public struct SpriteListView: View {
    @Bindable var session: Session
    @State private var model: SpriteListModel

    public init(session: Session, platform: SpritesPlatform) {
        self.session = session
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
                    ContentUnavailableView(
                        "No sprites yet",
                        systemImage: "cube",
                        description: Text("Create a sprite to get a disposable coding environment.")
                    )
                } else {
                    List(model.sprites) { sprite in
                        SpriteRow(sprite: sprite)
                    }
                    .refreshable { await model.refresh() }
                }
            }
            .navigationTitle("Sprites")
            .task { await model.refresh() }
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
