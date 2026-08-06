import SwiftUI

#if os(iOS)
import UIKit

/// A labeled value that copies on tap: tapping pops a single Copy menu,
/// with haptic confirmation. The shared idiom for values like Host, Code,
/// and the sprite URL.
struct CopyableValueRow: View {
    let label: String
    let value: String
    var monospaced = false
    @State private var copyCount = 0

    var body: some View {
        Menu {
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = value
                copyCount += 1
            }
        } label: {
            LabeledContent(label) {
                Text(value)
                    .font(monospaced ? .body.monospaced() : .body)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .tint(.primary)
        .sensoryFeedback(.success, trigger: copyCount)
    }
}
#endif
