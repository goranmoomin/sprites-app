import Foundation

/// A setup-token saved for reuse across Sprites: the token plus its mint
/// date. The date is display-only; nothing is keyed off it. There is no
/// refresh chain, so no rotation or atomic-persist discipline applies.
public struct SavedClaudeLogin: Sendable, Equatable, Codable {
    public var token: String
    public var mintedAt: Date

    public init(token: String, mintedAt: Date) {
        self.token = token
        self.mintedAt = mintedAt
    }
}
