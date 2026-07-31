import Foundation
import Observation

/// Creating a sprite: a suggested, editable haikunator name and one POST.
/// The Flow playlist that follows creation is ticket 12.
@MainActor
@Observable
public final class CreateSpriteModel {
    public var name: String
    public private(set) var errorMessage: String?
    public private(set) var isCreating = false

    private let platform: SpritesPlatform

    public init(platform: SpritesPlatform) {
        self.platform = platform
        self.name = Haikunator.suggestName()
    }

    public func suggestAnotherName() {
        name = Haikunator.suggestName()
    }

    /// Returns the created sprite, or nil with `errorMessage` set.
    public func create() async -> SpriteMetadata? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Name a sprite before creating it."
            return nil
        }
        isCreating = true
        defer { isCreating = false }
        errorMessage = nil
        do {
            return try await platform.createSprite(named: name)
        } catch {
            errorMessage = String(describing: error)
            return nil
        }
    }
}
