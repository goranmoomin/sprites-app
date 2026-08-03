import Foundation
import Observation

/// The general create-service Flow: a form mapping 1:1 to the platform
/// service definition. Arguments are an array, never a shell string.
@MainActor
@Observable
public final class CreateServiceModel {
    public var name = ""
    public var executable = ""
    public var arguments: [String] = []
    public var workingDirectory = ""
    public var environment: [String: String] = [:]
    public var httpPort: Int?
    public var needs: [String] = []

    public private(set) var progress: [ServiceUpsertEvent] = []
    public private(set) var isCreating = false
    public private(set) var errorMessage: String?

    private let platform: SpritesPlatform
    private let sprite: String

    public init(platform: SpritesPlatform, sprite: String) {
        self.platform = platform
        self.sprite = sprite
    }

    public var definition: ServiceDefinition {
        ServiceDefinition(
            cmd: executable,
            args: arguments,
            env: environment.isEmpty ? nil : environment,
            dir: workingDirectory.isEmpty ? nil : workingDirectory,
            needs: needs.isEmpty ? nil : needs,
            httpPort: httpPort
        )
    }

    /// Upserts the service, streaming NDJSON progress into `progress`.
    public func create() async -> Bool {
        guard !name.isEmpty, !executable.isEmpty else {
            errorMessage = "A service needs a name and an executable."
            return false
        }
        isCreating = true
        defer { isCreating = false }
        progress = []
        errorMessage = nil
        do {
            let events = try await platform.upsertService(
                on: sprite, named: name, definition: definition)
            for try await event in events {
                progress.append(event)
                if event.type == "error" {
                    errorMessage = event.message ?? "service creation failed"
                    return false
                }
            }
            return true
        } catch {
            errorMessage = String(describing: error)
            return false
        }
    }
}
