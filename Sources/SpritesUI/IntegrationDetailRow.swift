import SwiftUI
import SpritesCore

#if os(iOS)
import UIKit

/// One observed detail under an integration's status line; long-press
/// copies the value (MagicDNS names, accounts, addresses).
struct IntegrationDetailRow: View {
    let detail: IntegrationStatus.Detail
    @State private var copyCount = 0

    var body: some View {
        LabeledContent(detail.label) {
            Text(detail.value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = detail.value
                copyCount += 1
            }
        }
        .sensoryFeedback(.success, trigger: copyCount)
    }
}
#endif
