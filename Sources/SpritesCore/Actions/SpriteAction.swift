import Foundation

/// A one-tap operation on the sprite detail screen. App vocabulary that
/// integrations happen to contribute to: the description is data here,
/// execution lives at the layer owning the capability (mirroring Flow vs
/// FlowRun).
public struct SpriteAction: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case openURL(URL)  // T3 handoff, future SSH
        case runCommand  // presents the exec sheet
    }

    public var id: String
    public var title: String
    public var kind: Kind

    public init(id: String, title: String, kind: Kind) {
        self.id = id
        self.title = title
        self.kind = kind
    }
}
