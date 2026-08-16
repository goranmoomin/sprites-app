import Foundation

extension T3CodeIntegration {
    /// The tailnet-wide settings the tailnet pairing needs, fixed in
    /// Tailscale's admin console (the app cannot): MagicDNS plus HTTPS
    /// certificates on the DNS page, and Serve, whose enable link the CLI
    /// prints itself.
    public static let tailscaleDNSSettingsURL = URL(string: "https://login.tailscale.com/admin/dns")!

    /// Set up T3 Code over Tailscale: the shared install and Service steps,
    /// then serve the local port over HTTPS on the MagicDNS name and pair
    /// against that URL, so the sprite never has to be public. Requires
    /// Tailscale itself: it shells out to `tailscale serve` (ADR 0008).
    public func tailnetSetupFlow(certificateProbeInterval: Duration = .seconds(5)) -> Flow {
        Flow(
            id: "t3-setup-tailscale",
            title: "Set up T3 Code over Tailscale",
            requires: [T3CodeIntegration.supportedCodingAgents, .tailscale],
            steps: [
                InstallT3Step(),
                DefineT3ServiceStep(),
                TailnetServeStep(certificateProbeInterval: certificateProbeInterval),
                CreatePairingStep(host: .magicDNS),
            ]
        )
    }
}

/// Serves the t3 port over HTTPS on the tailnet. Two preconditions live in
/// the admin console: MagicDNS (read from `status --json`) and Serve
/// enablement (only detectable by trying, whose refusal prints the enable
/// URL). Each is an `.openURL` prompt that re-checks on acknowledge; the
/// step fails with the same ask on retry.
struct TailnetServeStep: FlowStep {
    let id = "t3-tailnet-serve"
    let title = "Serve t3 over the tailnet"
    let certificateProbeInterval: Duration

    static var serveArgv: [String] {
        [
            // Bounded: without Serve enabled the command hangs rather than
            // failing fast (observed live).
            "timeout", "20", TailscaleIntegration.tailscalePath, "serve", "--bg", "--https=443",
            "http://127.0.0.1:\(T3CodeIntegration.servicePort)",
        ]
    }

    func run(in context: FlowContext) async throws {
        let name = try await requireMagicDNS(in: context)
        try await requireServe(in: context)
        context.output("Serving https://\(name)/ -> http://127.0.0.1:\(T3CodeIntegration.servicePort)\n")
        await warmCertificate(host: name, in: context)
    }

    private func requireMagicDNS(in context: FlowContext) async throws -> String {
        while true {
            let status = try await context.platform.runCapturing(
                on: context.sprite, [TailscaleIntegration.tailscalePath, "status", "--json"])
            guard let parsed = TailscaleStatus.parse(status.stdout), parsed.backendState == "Running" else {
                throw FlowError.failed("Tailscale is not connected on this sprite. Log in to Tailscale first.")
            }
            if parsed.magicDNSEnabled, let name = parsed.magicDNSName { return name }
            let response = await context.prompt(.openURL(
                url: T3CodeIntegration.tailscaleDNSSettingsURL,
                instructions: "Turn on MagicDNS and HTTPS certificates for your tailnet on Tailscale's "
                    + "DNS settings page, then come back."))
            guard response == .acknowledged else { throw FlowError.declined }
        }
    }

    private func requireServe(in context: FlowContext) async throws {
        while true {
            let serve = try await context.platform.runCapturing(on: context.sprite, Self.serveArgv)
            let text = serve.stdoutText + serve.stderrText
            context.output(text)
            if serve.exitCode == 0 { return }
            guard let enableURL = TailscaleServeOutputParser.extractEnableURL(from: text) else {
                throw FlowError.failed("tailscale serve failed with exit status \(serve.exitCode).")
            }
            let response = await context.prompt(.openURL(
                url: enableURL,
                instructions: "Serve is off for your tailnet. Enable it on this page, then come back."))
            guard response == .acknowledged else { throw FlowError.declined }
        }
    }

    /// Certificates provision lazily on the first HTTPS request. Warming
    /// one here keeps the T3 Code app's first connection from timing out.
    /// Best-effort: the budget below is provisional until measured live
    /// (findings), and a slow cert is a note, not a failure.
    private func warmCertificate(host: String, in context: FlowContext) async {
        for _ in 0..<6 {
            let probe = try? await context.platform.runCapturing(on: context.sprite, [
                "curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "20",
                "https://\(host)/",
            ])
            if let probe, probe.exitCode == 0 {
                context.output("HTTPS certificate ready (HTTP \(probe.stdoutText))\n")
                return
            }
            try? await Task.sleep(for: certificateProbeInterval)
        }
        context.output("The HTTPS certificate is still provisioning; the first connection may take a minute.\n")
    }
}

/// Anchors into `tailscale serve`'s refusal (observed live):
///
///     Serve is not enabled on your tailnet.
///     To enable, visit:
///
///              https://login.tailscale.com/f/serve?node=...
///
/// Anchored on the wording so a reworded CLI fails visibly.
public enum TailscaleServeOutputParser {
    public static let serveDisabledMarker = "Serve is not enabled"

    public static func extractEnableURL(from raw: String) -> URL? {
        guard let range = raw.range(of: serveDisabledMarker),
            let match = raw[range.upperBound...].firstMatch(of: /https:\/\/\S+/)
        else { return nil }
        return URL(string: String(match.0))
    }
}
