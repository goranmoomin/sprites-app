import Foundation

extension TailscaleIntegration {
    /// Log in to Tailscale on the sprite: install, define the tailscaled
    /// Service, then join with the saved auth key, or paste one first.
    public func loginFlow() -> Flow {
        Flow(
            id: "tailscale-login",
            title: "Log in to Tailscale",
            steps: [
                InstallTailscaleStep(),
                DefineTailscaledServiceStep(),
                TailscaleUpStep(store: loginStore),
            ]
        )
    }
}

/// Installs the pinned static tarball into the user's bin. Not the
/// official script: that needs sudo, writes systemd units nothing reads,
/// and runs apt-get for ten seconds.
struct InstallTailscaleStep: FlowStep {
    let id = "tailscale-install"
    let title = "Install Tailscale"

    func run(in context: FlowContext) async throws {
        if try await context.platform.fileExists(on: context.sprite, path: TailscaleIntegration.tailscaledPath) {
            context.output("Tailscale already installed\n")
            return
        }
        let arch = try await context.platform.runCapturing(on: context.sprite, ["uname", "-m"])
        let goArch: String
        switch arch.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "x86_64": goArch = "amd64"
        case "aarch64": goArch = "arm64"
        case let other: throw FlowError.failed("Unsupported architecture \(other)")
        }
        let index = try await context.platform.runCapturing(
            on: context.sprite, ["curl", "-fsSL", TailscaleIntegration.releaseIndexURL])
        guard index.exitCode == 0,
            let object = try? JSONSerialization.jsonObject(with: index.stdout) as? [String: Any],
            let version = object["TarballsVersion"] as? String,
            let tarball = (object["Tarballs"] as? [String: String])?[goArch]
        else {
            context.output(index.stderrText)
            throw FlowError.failed("Could not resolve the current Tailscale release.")
        }
        context.output("Installing tailscale \(version) (\(tarball))\n")
        let install = try await context.platform.runCapturing(on: context.sprite, [
            "sh", "-c",
            "set -e; dir=$(mktemp -d); cd \"$dir\"; "
                + "curl -fsSL -o ts.tgz https://pkgs.tailscale.com/stable/\(tarball); "
                + "tar xzf ts.tgz; mkdir -p \(TailscaleIntegration.binDir); "
                + "cp tailscale_*/tailscale tailscale_*/tailscaled \(TailscaleIntegration.binDir)/; "
                + "cd /; rm -rf \"$dir\"",
        ])
        context.output(install.stdoutText + install.stderrText)
        guard install.exitCode == 0 else {
            throw FlowError.failed("Installing Tailscale failed with exit status \(install.exitCode).")
        }
    }
}

/// Defines `tailscaled` as a Service: no root, no flags, the default socket
/// (load-bearing: `tailscale serve` callers use plain `tailscale status`).
/// The sprite user's ambient capabilities give it a real tun device.
struct DefineTailscaledServiceStep: FlowStep {
    let id = "tailscale-define-service"
    let title = "Create the tailscaled service"

    func run(in context: FlowContext) async throws {
        let definition = ServiceDefinition(
            cmd: TailscaleIntegration.tailscaledPath, args: [], dir: "/home/sprite")
        let events = try await context.platform.upsertService(
            on: context.sprite, named: TailscaleIntegration.serviceName, definition: definition)
        for try await event in events {
            context.output("\(event.type): \(event.message ?? "")\n")
            if event.type == "error" {
                throw FlowError.failed(event.message ?? "creating the tailscaled service failed")
            }
        }
    }
}

/// Joins the tailnet with the saved auth key, pasting one first when none
/// is saved. Always the same complete flag set and never `--reset`: `up`
/// errors instead of logging in when a previously set flag is omitted, and
/// silently undoing the user's hand configuration is worse than surfacing
/// that error with the fix in it.
struct TailscaleUpStep: FlowStep {
    let id = "tailscale-up"
    let title = "Join the tailnet"
    let store: any SavedLoginStore

    static func upArgv(sprite: String) -> [String] {
        [
            TailscaleIntegration.tailscalePath, "up", "--json",
            "--auth-key=file:" + TailscaleIntegration.authKeyPath,
            "--hostname=" + sprite, "--timeout=60s",
        ]
    }

    func run(in context: FlowContext) async throws {
        try await waitForTailscaled(in: context)
        if let saved = store.load(SavedTailscaleLogin.self, for: TailscaleIntegration.id) {
            context.output("Using the saved Tailscale auth key\n")
            switch try await up(with: saved.authKey, in: context) {
            case .joined: return
            case .keyRejected(let reason):
                store.clear(for: TailscaleIntegration.id)
                context.output(
                    "The saved auth key was rejected (\(reason)); it has been forgotten. "
                        + "Paste a new one.\n")
            }
        }
        let key = try await pasteKey(in: context)
        switch try await up(with: key, in: context) {
        case .joined:
            break
        case .keyRejected(let reason):
            throw FlowError.failed("Tailscale rejected the auth key: \(reason)")
        }
        let save = await context.prompt(.consent(
            title: "Save the auth key?",
            message: "Saving lets the app join later Sprites to your tailnet with no browser. "
                + "The key stays in this app only; revoke it at Tailscale's admin console. "
                + "Auth keys expire after at most 90 days, and the app will ask for a new one then. "
                + "Do not checkpoint a Sprite after it joins: a restore brings back a stale node, "
                + "and the node stays listed in the admin console until you remove it there.",
            approveTitle: "Save for other Sprites"))
        if save == .approved {
            store.save(SavedTailscaleLogin(authKey: key, savedAt: Date()), for: TailscaleIntegration.id)
            context.output("Saved the auth key for reuse on other Sprites\n")
        }
        context.output(
            "Do not checkpoint this Sprite after joining: a restore would resurrect a stale node.\n")
    }

    /// tailscaled's socket is up well under a second after the Service
    /// starts (observed live); every call before that exits 1.
    private func waitForTailscaled(in context: FlowContext) async throws {
        for _ in 0..<20 {
            let probe = try await context.platform.runCapturing(
                on: context.sprite, [TailscaleIntegration.tailscalePath, "status", "--json"])
            if TailscaleStatus.parse(probe.stdout) != nil { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw FlowError.failed("tailscaled did not come up. Check the tailscaled service logs.")
    }

    private func pasteKey(in context: FlowContext) async throws -> String {
        let response = await context.prompt(.openURLAndEnterCode(
            url: TailscaleIntegration.adminKeysURL,
            instructions: "Generate an auth key in Tailscale's admin console (Reusable on, Ephemeral "
                + "off, no tags) and paste it here. Sprites go cold, so an ephemeral key would drop "
                + "them from the tailnet."))
        guard case .text(let key) = response else { throw FlowError.declined }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("tskey-auth-") else {
            throw FlowError.failed("That is not a Tailscale auth key (they start with tskey-auth-). Retry to paste again.")
        }
        return trimmed
    }

    enum Outcome {
        case joined
        case keyRejected(String)
    }

    /// One `up`, key over a 600 file that is removed afterwards. Not the
    /// key's fault, so no forgetting: the complete-set-of-flags error and
    /// a tailscaled that is not answering fail the step verbatim, and a
    /// tailnet that wants device approval (`NeedsMachineAuth`) asks for it
    /// in the admin console and polls. Everything else `up` refuses reads
    /// as a rejected key (the exact wordings for expired and revoked keys
    /// are still unmeasured).
    private func up(with key: String, in context: FlowContext) async throws -> Outcome {
        try await context.platform.writeFile(
            on: context.sprite, path: TailscaleIntegration.authKeyPath, content: key + "\n")
        _ = try await context.platform.runCapturing(
            on: context.sprite, ["chmod", "600", TailscaleIntegration.authKeyPath])
        let result: ExecResult
        do {
            result = try await context.platform.runCapturing(
                on: context.sprite, Self.upArgv(sprite: context.sprite))
        } catch {
            _ = try? await context.platform.runCapturing(
                on: context.sprite, ["rm", "-f", TailscaleIntegration.authKeyPath])
            throw error
        }
        _ = try? await context.platform.runCapturing(
            on: context.sprite, ["rm", "-f", TailscaleIntegration.authKeyPath])
        context.output(result.stderrText)
        let stderr = result.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode == 0 {
            let status = try await context.platform.runCapturing(
                on: context.sprite, [TailscaleIntegration.tailscalePath, "status", "--json"])
            if let parsed = TailscaleStatus.parse(status.stdout) {
                context.output("Joined as \(parsed.magicDNSName ?? context.sprite) "
                    + "(\(parsed.addresses.joined(separator: ", ")))\n")
            }
            return .joined
        }
        // The CLI wraps "requires mentioning all\nnon-default flags" over
        // two lines (observed live), so anchor on the first half.
        if stderr.contains("requires mentioning all") || stderr.contains("failed to connect") {
            throw FlowError.failed("tailscale up failed: " + stderr)
        }
        let after = try await context.platform.runCapturing(
            on: context.sprite, [TailscaleIntegration.tailscalePath, "status", "--json"])
        if TailscaleStatus.parse(after.stdout)?.backendState == "NeedsMachineAuth" {
            try await awaitDeviceApproval(in: context)
            return .joined
        }
        return .keyRejected(stderr.isEmpty ? "exit status \(result.exitCode)" : stderr)
    }

    /// The key was accepted but the tailnet approves devices by hand: an
    /// external precondition, fixed in the admin console.
    private func awaitDeviceApproval(in context: FlowContext) async throws {
        while true {
            let response = await context.prompt(.openURL(
                url: TailscaleIntegration.adminMachinesURL,
                instructions: "Your tailnet requires device approval. Approve \(context.sprite) on the "
                    + "Machines page, then come back."))
            guard response == .acknowledged else { throw FlowError.declined }
            for _ in 0..<12 {
                let status = try await context.platform.runCapturing(
                    on: context.sprite, [TailscaleIntegration.tailscalePath, "status", "--json"])
                if TailscaleStatus.parse(status.stdout)?.backendState == "Running" { return }
                try await Task.sleep(for: .seconds(1))
            }
        }
    }
}
