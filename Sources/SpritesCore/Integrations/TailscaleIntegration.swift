import Foundation

/// Log in to Tailscale on a Sprite: a static tailscale in the user's bin,
/// `tailscaled` as a Service, and the tailnet joined with a reusable auth
/// key pasted once and saved. "Connected" is observed from tailscale's own
/// `status --json`, never remembered app-side.
public struct TailscaleIntegration: Integration {
    public static let id = "tailscale"
    public var id: String { Self.id }
    public let displayName = "Tailscale"
    public let category = Category.other

    /// The static tarball lands here: no sudo, nothing outside the home dir.
    public static let binDir = "/home/sprite/.local/bin"
    public static let tailscalePath = binDir + "/tailscale"
    public static let tailscaledPath = binDir + "/tailscaled"
    public static let serviceName = "tailscaled"
    /// The pinned-version index: `TarballsVersion` plus per-arch filenames.
    public static let releaseIndexURL = "https://pkgs.tailscale.com/stable/?mode=json"
    public static let adminKeysURL = URL(string: "https://login.tailscale.com/admin/settings/keys")!
    public static let adminMachinesURL = URL(string: "https://login.tailscale.com/admin/machines")!
    /// Where the auth key sits for the one `up` call (600, then removed):
    /// argv leaks to `ps` and the exec-session list.
    public static let authKeyPath = "/home/sprite/.tailscale-authkey"

    /// The app-side saved auth key the login Flow plants.
    public let loginStore: any SavedLoginStore

    public init(loginStore: any SavedLoginStore = Integrations.savedLogins) {
        self.loginStore = loginStore
    }

    /// Recognized iff the command's basename is `tailscaled`, whoever
    /// created it.
    public func recognizes(_ service: Service) -> Bool {
        service.cmd.split(separator: "/").last == "tailscaled"
    }

    public func observeStatus(on sprite: String, services: [Service], platform: SpritesPlatform)
        async throws -> IntegrationStatus
    {
        let recognized = services.filter(recognizes)
        guard let service = recognized.first else {
            return IntegrationStatus(summary: "not set up", isReady: false)
        }
        let serviceState = service.state?.status.display ?? "not running"
        guard service.state?.status == .running else {
            return IntegrationStatus(
                summary: "service \(serviceState)", isReady: false,
                details: [IntegrationStatus.Detail("Service", serviceState)])
        }
        // One exec, only while the Service runs. Parse the JSON, never the
        // exit code (status exits 1 logged out, 0 with --json).
        let result = try await platform.runCapturing(
            on: sprite, [Self.tailscalePath, "status", "--json"])
        guard let status = TailscaleStatus.parse(result.stdout) else {
            return IntegrationStatus(
                summary: "tailscaled not answering", isReady: false,
                details: [IntegrationStatus.Detail("Service", serviceState)])
        }
        var details: [IntegrationStatus.Detail] = []
        if let name = status.magicDNSName { details.append(.init("MagicDNS name", name)) }
        if let tailnet = status.tailnet { details.append(.init("Tailnet", tailnet)) }
        if !status.addresses.isEmpty {
            details.append(.init("Addresses", status.addresses.joined(separator: ", ")))
        }
        details.append(.init("Service", serviceState))
        return IntegrationStatus(
            summary: status.summary, isReady: status.backendState == "Running", details: details)
    }

    public func actions(services: [Service], metadata: SpriteMetadata?) -> [SpriteAction] {
        []
    }

    public func flows(status: IntegrationStatus, services: [Service], metadata: SpriteMetadata?) -> [Flow] {
        status.isReady ? [] : [loginFlow()]
    }

    public func describeSavedLogin(in store: any SavedLoginStore) -> String? {
        guard let login = store.load(SavedTailscaleLogin.self, for: id) else { return nil }
        return "Auth key saved " + login.savedAt.formatted(date: .abbreviated, time: .omitted)
    }
}

extension Requirement {
    /// Flows that serve over the tailnet need Tailscale itself, not a
    /// generic network: they shell out to `tailscale serve` and use the
    /// MagicDNS name (ADR 0008).
    public static let tailscale = Requirement(anyOf: [TailscaleIntegration.id])
}

/// A reusable, non-ephemeral auth key pasted once from the admin console.
/// Auth keys cap at 90 days; an expired one is forgotten and re-pasted.
public struct SavedTailscaleLogin: Sendable, Equatable, Codable {
    public var authKey: String
    public var savedAt: Date

    public init(authKey: String, savedAt: Date) {
        self.authKey = authKey
        self.savedAt = savedAt
    }
}

/// The fields of `tailscale status --json` the app reads. `--json` is
/// documented as "format subject to change", so this is pinned by tests.
public struct TailscaleStatus: Equatable, Sendable {
    /// `NoState`, `NeedsLogin`, `NeedsMachineAuth`, `Stopped`, `Starting`,
    /// `Running`.
    public var backendState: String
    /// `Self.DNSName` with its trailing dot stripped.
    public var magicDNSName: String?
    public var tailnet: String?
    /// `TailscaleIPs` filtered to the CGNAT range (100.64.0.0/10), what T3
    /// does.
    public var addresses: [String]
    public var authURL: String?
    public var magicDNSEnabled: Bool

    public var summary: String {
        switch backendState {
        case "Running": "connected"
        case "NeedsLogin": "needs login"
        case "NeedsMachineAuth": "waiting for device approval"
        default: backendState.lowercased()
        }
    }

    public static func parse(_ data: Data) -> TailscaleStatus? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let backendState = object["BackendState"] as? String
        else { return nil }
        let selfNode = object["Self"] as? [String: Any]
        let dnsName = (selfNode?["DNSName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let tailnet = object["CurrentTailnet"] as? [String: Any]
        let ips = object["TailscaleIPs"] as? [String] ?? []
        return TailscaleStatus(
            backendState: backendState,
            magicDNSName: dnsName.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 },
            tailnet: tailnet?["Name"] as? String,
            addresses: ips.filter(isCGNAT),
            authURL: (object["AuthURL"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            magicDNSEnabled: tailnet?["MagicDNSEnabled"] as? Bool ?? false)
    }

    static func isCGNAT(_ address: String) -> Bool {
        let octets = address.split(separator: ".").compactMap { Int($0) }
        return octets.count == 4 && octets[0] == 100 && (64...127).contains(octets[1])
    }
}
