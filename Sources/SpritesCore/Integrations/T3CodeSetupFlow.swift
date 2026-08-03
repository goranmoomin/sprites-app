import Foundation

extension T3CodeIntegration {
    /// T3 is installed once the way the base image installs its other npm
    /// agents (codex, gemini): a user-level global install with prefix
    /// ~/.local, giving a fixed binary path on PATH. The service runs that
    /// installed binary so cold-start boots need no network resolve. T3's
    /// data stays in its own default `~/.t3` (T3CODE_HOME: userdata/,
    /// caches/, worktrees/).
    public static let installPrefix = "/home/sprite/.local"
    public static let binaryPath = installPrefix + "/bin/t3"
    public static let packageJSONPath = installPrefix + "/lib/node_modules/t3/package.json"
    public static let serviceName = "t3"
    public static let servicePort = 3773
    /// Where provider sessions work (serve's cwd).
    public static let sessionsDirectory = "/home/sprite"

    public func setupFlow() -> Flow {
        Flow(
            id: "t3-setup",
            title: "Set up T3 Code",
            steps: [
                RequireCodingAgentStep(),
                InstallT3Step(),
                DefineT3ServiceStep(),
                PublicURLConsentStep(),
                CreatePairingStep(),
            ]
        )
    }

    /// Standalone recovery after a restore or an expired pairing.
    public func pairAgainFlow() -> Flow {
        Flow(id: "t3-pair-again", title: "Pair again", steps: [CreatePairingStep()])
    }

    /// The installed T3 version, observed from the runtime directory.
    public func installedVersion(on sprite: String, platform: SpritesPlatform) async throws -> String? {
        guard let json = try await platform.readFile(on: sprite, path: Self.packageJSONPath),
            let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        else { return nil }
        return object["version"] as? String
    }
}

/// T3 requires at least one logged-in coding agent (declared dependency).
struct RequireCodingAgentStep: FlowStep {
    let id = "t3-require-coding-agent"
    let title = "Check coding agent login"

    func run(in context: FlowContext) async throws {
        guard
            let ready = await Integrations.readyProvider(
                of: .codingAgent, on: context.sprite, services: [], platform: context.platform)
        else {
            throw FlowError.failed(
                "No coding agent is logged in on this sprite. Run the Claude Code login Flow first.")
        }
        context.output("\(ready.integration.displayName): \(ready.status.summary)\n")
    }
}

/// Installs the npm package `t3` once, resolving the then-current release,
/// and rebuilds the native modules npm blocks by default (node-pty,
/// msgpackr-extract ship no linux prebuilds).
struct InstallT3Step: FlowStep {
    let id = "t3-install"
    let title = "Install T3"

    func run(in context: FlowContext) async throws {
        if try await context.platform.fileExists(on: context.sprite, path: T3CodeIntegration.binaryPath) {
            let version = try? await Integrations.t3Code.installedVersion(
                on: context.sprite, platform: context.platform)
            context.output("T3 already installed\(version.flatMap { $0 }.map { " (v\($0))" } ?? "")\n")
            return
        }
        // --allow-scripts lets npm build node-pty's native module during the
        // install (no linux prebuilds; blocked by default). msgpackr-extract
        // is optional acceleration and t3 runs without its native part.
        let result = try await context.platform.runCapturing(on: context.sprite, [
            "npm", "install", "-g",
            "--prefix", T3CodeIntegration.installPrefix,
            "--allow-scripts=node-pty,msgpackr-extract",
            "t3",
        ])
        context.output(result.stdoutText + result.stderrText)
        guard result.exitCode == 0 else {
            throw FlowError.failed("Installing T3 failed with exit status \(result.exitCode).")
        }
    }
}

/// Defines the `t3 serve` service running the installed binary. Never npx:
/// cold-start boots must be deterministic and offline-safe.
struct DefineT3ServiceStep: FlowStep {
    let id = "t3-define-service"
    let title = "Create the t3 serve service"

    func run(in context: FlowContext) async throws {
        // No --base-dir: passing one relocates T3's whole data directory
        // (observed live: caches/ and worktrees/ sprayed into the home dir).
        // The service dir is serve's cwd, which provider sessions inherit.
        let definition = ServiceDefinition(
            cmd: T3CodeIntegration.binaryPath,
            args: [
                "serve",
                "--host", "0.0.0.0",
                "--port", String(T3CodeIntegration.servicePort),
                "--no-browser",
            ],
            dir: T3CodeIntegration.sessionsDirectory,
            httpPort: T3CodeIntegration.servicePort
        )
        let events = try await context.platform.upsertService(
            on: context.sprite, named: T3CodeIntegration.serviceName, definition: definition)
        for try await event in events {
            context.output("\(event.type): \(event.message ?? "")\n")
            if event.type == "error" {
                throw FlowError.failed(event.message ?? "creating the t3 service failed")
            }
        }
    }
}

/// Internet exposure is never silent: making the URL public is an explicit
/// consent step.
struct PublicURLConsentStep: FlowStep {
    let id = "t3-public-consent"
    let title = "Make the sprite URL public"

    func run(in context: FlowContext) async throws {
        let metadata = try await context.platform.getSprite(named: context.sprite)
        if metadata.urlVisibility == .public {
            context.output("URL is already public\n")
            return
        }
        let response = await context.prompt(.consent(
            title: "Make the sprite URL public?",
            message: "The T3 Code app connects through the sprite URL, so it must be public: "
                + "anyone with the URL can reach the t3 service over the internet. "
                + "T3's own pairing auth still protects your sessions.",
            approveTitle: "Make public"))
        guard response == .approved else { throw FlowError.declined }
        try await context.platform.setURLVisibility(sprite: context.sprite, .public)
        context.output("URL visibility set to public\n")
    }
}

/// The one-time credential the official T3 Code app uses to connect.
/// Pairing is a T3-only term (CONTEXT.md), so the type lives here.
public struct T3Pairing: Sendable, Equatable {
    public var host: String
    public var code: String
    public var pairURL: URL?
    public var expiresAt: Date?

    public init(host: String, code: String, pairURL: URL? = nil, expiresAt: Date? = nil) {
        self.host = host
        self.code = code
        self.pairURL = pairURL
        self.expiresAt = expiresAt
    }
}

/// Creates the Pairing credential non-interactively. The serve log's own
/// pairing URL carries a local IP, so this asks the CLI for one on the
/// public host instead.
struct CreatePairingStep: FlowStep {
    let id = "t3-create-pairing"
    let title = "Pair with the T3 Code app"

    func run(in context: FlowContext) async throws {
        let metadata = try await context.platform.getSprite(named: context.sprite)
        guard let url = metadata.url, let host = url.host() else {
            throw FlowError.failed("The sprite has no URL to pair against.")
        }
        let result = try await context.platform.runCapturing(on: context.sprite, [
            T3CodeIntegration.binaryPath, "auth", "pairing", "create",
            "--base-url", "https://\(host)",
            "--json",
        ])
        context.output(result.stdoutText + result.stderrText)
        guard result.exitCode == 0 else {
            throw FlowError.failed("t3 auth pairing create exited with status \(result.exitCode).")
        }
        guard let pairing = Self.parsePairing(result.stdoutText, host: host) else {
            throw FlowError.failed("Could not parse the pairing JSON from t3's output.")
        }
        _ = await context.prompt(.t3Pairing(pairing))
    }

    static func parsePairing(_ output: String, host: String) -> T3Pairing? {
        guard let jsonStart = output.firstIndex(of: "{"),
            let object = try? JSONSerialization.jsonObject(
                with: Data(output[jsonStart...].utf8)) as? [String: Any]
        else { return nil }
        let pairURL = (object["pairUrl"] as? String).flatMap(URL.init(string:))
        let expiresAt = (object["expiresAt"] as? String).flatMap {
            ISO8601DateFormatter().date(from: $0)
        }
        // The one-time code is the token, surfaced directly or in the pair
        // URL fragment.
        var code = object["token"] as? String ?? object["code"] as? String
        if code == nil, let fragment = pairURL?.fragment(),
            let match = fragment.firstMatch(of: /token=([^&]+)/)
        {
            code = String(match.1)
        }
        guard let code else { return nil }
        return T3Pairing(host: pairURL?.host() ?? host, code: code, pairURL: pairURL, expiresAt: expiresAt)
    }
}
