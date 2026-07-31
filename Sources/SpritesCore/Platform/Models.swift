import Foundation

/// Platform status of a Sprite as reported by shallow observation.
public enum SpriteStatus: String, Sendable, Codable {
    case cold
    case warm
    case running
}

/// URL auth setting of a Sprite (private / public).
public enum URLVisibility: String, Sendable, Codable {
    case `private`
    case `public`
}

/// Control-plane metadata about a Sprite. Everything shallow observation returns.
public struct SpriteMetadata: Sendable, Equatable, Identifiable {
    public var name: String
    public var status: SpriteStatus
    public var url: URL?
    public var urlVisibility: URLVisibility

    public var id: String { name }

    public init(name: String, status: SpriteStatus, url: URL? = nil, urlVisibility: URLVisibility = .private) {
        self.name = name
        self.status = status
        self.url = url
        self.urlVisibility = urlVisibility
    }
}

/// Errors crossing the Sprites platform seam.
public enum PlatformError: Error, Equatable {
    /// The Sprite token is invalid or revoked.
    case unauthorized
    /// Any other API failure, with a human-readable message.
    case api(String)
    case notFound
}
