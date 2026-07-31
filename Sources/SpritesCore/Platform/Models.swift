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

/// The observed state of a Service's supervised process.
public struct ServiceState: Sendable, Equatable {
    public var status: String
    public var pid: Int?
    public var startedAt: Date?
    public var error: String?
    public var restartCount: Int?
    public var nextRestartAt: Date?

    public init(
        status: String, pid: Int? = nil, startedAt: Date? = nil, error: String? = nil,
        restartCount: Int? = nil, nextRestartAt: Date? = nil
    ) {
        self.status = status
        self.pid = pid
        self.startedAt = startedAt
        self.error = error
        self.restartCount = restartCount
        self.nextRestartAt = nextRestartAt
    }
}

/// A Sprites-managed supervised long-running process on a Sprite.
public struct Service: Sendable, Equatable, Identifiable {
    public var name: String
    public var cmd: String
    public var args: [String]
    public var dir: String?
    public var env: [String: String]?
    public var httpPort: Int?
    public var needs: [String]?
    public var state: ServiceState?

    public var id: String { name }

    public init(
        name: String, cmd: String, args: [String], dir: String? = nil,
        env: [String: String]? = nil, httpPort: Int? = nil, needs: [String]? = nil,
        state: ServiceState? = nil
    ) {
        self.name = name
        self.cmd = cmd
        self.args = args
        self.dir = dir
        self.env = env
        self.httpPort = httpPort
        self.needs = needs
        self.state = state
    }
}

/// What the create-service Flow submits: maps 1:1 to the platform service
/// definition. Arguments are always an array, never a shell string.
public struct ServiceDefinition: Sendable, Equatable {
    public var cmd: String
    public var args: [String]
    public var env: [String: String]?
    public var dir: String?
    public var needs: [String]?
    public var httpPort: Int?

    public init(
        cmd: String, args: [String] = [], env: [String: String]? = nil, dir: String? = nil,
        needs: [String]? = nil, httpPort: Int? = nil
    ) {
        self.cmd = cmd
        self.args = args
        self.env = env
        self.dir = dir
        self.needs = needs
        self.httpPort = httpPort
    }
}

/// One NDJSON progress event streamed by a service upsert.
public struct ServiceUpsertEvent: Sendable, Equatable {
    public var type: String
    public var message: String?

    public init(type: String, message: String? = nil) {
        self.type = type
        self.message = message
    }
}

/// A live platform task holding a Sprite awake (Keep-alive, Heartbeat, ...).
public struct PlatformTask: Sendable, Equatable, Identifiable {
    public var name: String
    public var startedAt: Date?
    public var expiresAt: Date?

    public var id: String { name }

    public init(name: String, startedAt: Date? = nil, expiresAt: Date? = nil) {
        self.name = name
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }
}

/// One NDJSON progress event streamed by checkpoint create/restore:
/// `{type: "info"|"complete", data, time}` with human-readable strings.
public struct CheckpointEvent: Sendable, Equatable {
    public var type: String
    public var message: String?

    public init(type: String, message: String? = nil) {
        self.type = type
        self.message = message
    }
}

/// A deliberate snapshot of a Sprite's writable filesystem.
public struct Checkpoint: Sendable, Equatable, Identifiable {
    public var id: String
    public var createTime: Date?
    public var comment: String?
    public var isAuto: Bool

    public init(id: String, createTime: Date? = nil, comment: String? = nil, isAuto: Bool = false) {
        self.id = id
        self.createTime = createTime
        self.comment = comment
        self.isAuto = isAuto
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
