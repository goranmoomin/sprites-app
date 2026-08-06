import Testing
import SpritesCore

struct SpriteTokenFormatTests {
    static let hex32 = String(repeating: "0f", count: 16)
    static let hex64 = String(repeating: "0f", count: 32)

    @Test func acceptsTheCapturedDashboardShape() {
        #expect(SpriteTokenFormat.matches("sungbin-jo/35742/\(Self.hex32)/\(Self.hex64)"))
        #expect(SpriteTokenFormat.matches("a1/0/\(Self.hex32)/\(Self.hex64)"))
    }

    @Test func rejectsThingsPeopleCopyByAccident() {
        #expect(!SpriteTokenFormat.matches(""))
        #expect(!SpriteTokenFormat.matches("https://fly.io/dashboard/personal/sprites"))
        #expect(!SpriteTokenFormat.matches("some words from a web page"))
        // Truncated hex segments.
        #expect(!SpriteTokenFormat.matches("sungbin-jo/35742/abc123/def456"))
        // Whitespace anywhere disqualifies.
        #expect(!SpriteTokenFormat.matches("sungbin-jo/35742/\(Self.hex32)/\(Self.hex64) "))
        // Uppercase slug or hex is not what the dashboard issues.
        #expect(!SpriteTokenFormat.matches("Sungbin-Jo/35742/\(Self.hex32)/\(Self.hex64)"))
    }
}
