import Foundation

/// The Sprite token shape as captured live from the Fly dashboard:
/// `<org-slug>/<number>/<32 hex>/<64 hex>`. The slug charset reflects what
/// Fly currently issues; widen only against a real counterexample.
public enum SpriteTokenFormat {
    public static func matches(_ candidate: String) -> Bool {
        candidate.wholeMatch(of: /[a-z0-9-]+\/[0-9]+\/[0-9a-f]{32}\/[0-9a-f]{64}/) != nil
    }
}
