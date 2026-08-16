import Foundation

/// Log in to GitHub on a Sprite: gh's device-flow token, minted once and
/// planted many. "Logged in" is observed from gh's own hosts file on the
/// Sprite, never remembered app-side.
public struct GitHubIntegration: Integration {
    public static let id = "github"
    public var id: String { Self.id }
    public let displayName = "GitHub"
    public let category = Category.other

    /// gh's config tree. `config.yml` is load-bearing: without it gh
    /// attempts a multi-account migration on every call and hard fails.
    public static let configDir = "/home/sprite/.config/gh"
    public static let configPath = configDir + "/config.yml"
    public static let hostsPath = configDir + "/hosts.yml"
    /// The base image's git identity, "authored by nobody"; the login is
    /// the only moment the app knows who the user is.
    public static let baseImageEmail = "noreply@sprites.dev"
    /// The default device-flow scopes plus `workflow`, without which pushing
    /// a commit that touches `.github/workflows/` is rejected server-side.
    public static let scopes = ["repo", "read:org", "gist", "workflow"]

    /// The app-side saved login the branching login Flow reuses.
    public let loginStore: any SavedLoginStore

    public init(loginStore: any SavedLoginStore = Integrations.savedLogins) {
        self.loginStore = loginStore
    }

    public func recognizes(_ service: Service) -> Bool {
        // A GitHub login is not a Service; nothing to recognize.
        false
    }

    public func observeStatus(on sprite: String, services: [Service], platform: SpritesPlatform)
        async throws -> IntegrationStatus
    {
        // Presence of a token in gh's own hosts file. Existence alone is
        // wrong: gh's logout leaves the file behind as `{}`. This cannot see
        // a GH_TOKEN planted by someone else; the Flow's verify names it.
        guard let hosts = try await platform.readFile(on: sprite, path: Self.hostsPath),
            let hosts = GitHubHostsFile.parse(hosts)
        else {
            return IntegrationStatus(summary: "not logged in", isReady: false)
        }
        return IntegrationStatus(
            summary: "logged in", isReady: true,
            details: hosts.user.map { [IntegrationStatus.Detail("Account", $0)] } ?? [])
    }

    public func actions(services: [Service], metadata: SpriteMetadata?) -> [SpriteAction] {
        []
    }

    public func flows(status: IntegrationStatus, services: [Service], metadata: SpriteMetadata?) -> [Flow] {
        status.isReady ? [] : [loginFlow()]
    }

    public func describeSavedLogin(in store: any SavedLoginStore) -> String? {
        guard let login = store.load(SavedGitHubLogin.self, for: id) else { return nil }
        return "\(login.login), saved " + login.mintedAt.formatted(date: .abbreviated, time: .omitted)
    }
}

/// A device-flow token saved for reuse across Sprites, with the account it
/// belongs to: `hosts.yml` names the account, and the git identity is
/// derived from `id` and `login`. No refresh chain, so nothing rotates.
public struct SavedGitHubLogin: Sendable, Equatable, Codable {
    public var token: String
    public var login: String
    public var name: String
    public var id: Int
    public var scopes: [String]
    public var mintedAt: Date

    public init(token: String, login: String, name: String, id: Int, scopes: [String], mintedAt: Date) {
        self.token = token
        self.login = login
        self.name = name
        self.id = id
        self.scopes = scopes
        self.mintedAt = mintedAt
    }

    /// GitHub's noreply address for the account, derivable without any
    /// extra scope.
    public var noreplyEmail: String { "\(id)+\(login)@users.noreply.github.com" }
}

/// gh's `hosts.yml`, the shape verified end to end (observed live). Only
/// the top-level `oauth_token` is what gh reads; `user` names the account
/// and the `users:` map is what gh's own logout and switch enumerate.
public enum GitHubHostsFile {
    public struct Contents: Equatable {
        public var user: String?

        public init(user: String?) {
            self.user = user
        }
    }

    public static func render(login: String, token: String) -> String {
        """
        github.com:
            users:
                \(login):
                    oauth_token: \(token)
            git_protocol: https
            user: \(login)
            oauth_token: \(token)

        """
    }

    /// The account of a logged-in hosts file, or nil when no token line is
    /// present (a bare `{}` after gh's logout reads as logged out).
    public static func parse(_ text: String) -> Contents? {
        guard text.contains("oauth_token:") else { return nil }
        let user = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("user: ") }
            .map { String($0.dropFirst("user: ".count)) }
        return Contents(user: user)
    }
}
