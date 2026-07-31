import Foundation
import Observation

/// Recent logs of one service, viewed as plain text.
@MainActor
@Observable
public final class ServiceLogsModel {
    public private(set) var logs: String?
    public private(set) var lastError: Error?

    private let platform: SpritesPlatform
    private let spriteName: String
    private let serviceName: String

    public init(platform: SpritesPlatform, spriteName: String, serviceName: String) {
        self.platform = platform
        self.spriteName = spriteName
        self.serviceName = serviceName
    }

    public func load(lines: Int = 200) async {
        do {
            logs = try await platform.serviceLogs(on: spriteName, named: serviceName, lines: lines)
            lastError = nil
        } catch {
            lastError = error
        }
    }
}
