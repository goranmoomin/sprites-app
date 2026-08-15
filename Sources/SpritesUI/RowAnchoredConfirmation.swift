import SwiftUI

#if os(iOS)
/// Row bounds published by row id, read by `rowAnchoredConfirmation`.
struct RowAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publishes this row's bounds so a confirmation hosted on the enclosing
    /// List can point back at it.
    func rowAnchor(_ id: String) -> some View {
        anchorPreference(key: RowAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// A confirmation for a swipe action, hosted on the List and anchored at
    /// the row in `selection`. It cannot live on the row itself: closing the
    /// swipe reconfigures that cell, which tears down anything presented from
    /// inside it and writes the dismissal straight back into the binding.
    func rowAnchoredConfirmation<Actions: View>(
        selection: Binding<String?>,
        title: @escaping (String) -> String,
        message: String,
        @ViewBuilder actions: @escaping (String) -> Actions
    ) -> some View {
        overlayPreferenceValue(RowAnchorKey.self) { anchors in
            GeometryReader { proxy in
                let rect = selection.wrappedValue.flatMap { anchors[$0] }
                    .map { proxy[$0] } ?? .zero
                // The dialog attaches before .position: position fills its
                // parent, and the dialog would then anchor to the whole List.
                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .confirmationDialog(
                        selection.wrappedValue.map(title) ?? "",
                        isPresented: Binding(
                            get: { selection.wrappedValue != nil },
                            set: { if !$0 { selection.wrappedValue = nil } }
                        ),
                        titleVisibility: .visible
                    ) {
                        if let selected = selection.wrappedValue {
                            actions(selected)
                        }
                    } message: {
                        Text(message)
                    }
                    .position(x: rect.midX, y: rect.midY)
            }
            .allowsHitTesting(false)
        }
    }
}
#endif
