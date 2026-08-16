import SwiftUI
import SpritesCore

#if os(iOS)
/// The Board: one List section per Category row, a horizontally scrolling
/// tile per Integration, the tapped tile expanded into its observed
/// details and the Flows it offers. Shared by the create path and the
/// detail screen; tile state is whatever the model last observed.
struct BoardSections: View {
    let board: [SpriteDetailModel.BoardRow]
    let blockedReason: (Flow) -> String?
    let launch: (Flow) -> Void
    @State private var expandedTileID: String?

    var body: some View {
        ForEach(board) { row in
            Section(row.category.displayName) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(row.tiles) { tile in
                            tileButton(tile)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if let tile = row.tiles.first(where: { $0.id == expandedTileID }) {
                    ForEach(tile.status.details) { detail in
                        IntegrationDetailRow(detail: detail)
                    }
                    ForEach(tile.flows, id: \.id) { flow in
                        flowRow(flow)
                    }
                }
            }
        }
    }

    private func tileButton(_ tile: SpriteDetailModel.BoardTile) -> some View {
        Button {
            // A tile with nothing to expand into launches its one Flow.
            if tile.flows.count == 1, tile.status.details.isEmpty, expandedTileID != tile.id {
                launch(tile.flows[0])
            } else {
                expandedTileID = expandedTileID == tile.id ? nil : tile.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tile.title)
                        .font(.headline)
                    Spacer(minLength: 0)
                    Image(systemName: tile.status.isReady ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(tile.status.isReady ? Color.green : Color.secondary)
                }
                Text(tile.status.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(width: 160, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(expandedTileID == tile.id ? Color.accentColor.opacity(0.15) : Color(.secondarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tile.title), \(tile.status.summary)")
    }

    private func flowRow(_ flow: Flow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(flow.title) { launch(flow) }
            if let reason = blockedReason(flow) {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
