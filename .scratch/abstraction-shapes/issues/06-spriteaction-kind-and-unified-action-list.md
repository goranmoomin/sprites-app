# 06 — SpriteAction.Kind and the unified action list

**What to build:** Actions stay data (descriptions in core, execution at the layer that owns the capability, mirroring Flow vs FlowRun), but the data stops lying. `SpriteAction` moves out of the Integration file into the Actions area: it is app vocabulary that integrations happen to contribute to. Its optional URL is replaced by a closed kind enum, from this review:

```swift
public enum Kind: Sendable, Equatable {
    case openURL(URL)   // T3 handoff, future SSH
    case runCommand     // presents the exec sheet
}
```

The detail screen renders one uniform action list: integrations contribute `.openURL` actions (Open in T3 Code), and the app contributes the Run command action whose tap presents the existing one-shot exec sheet; the exec model stays the engine behind that screen, unchanged. CONTEXT.md's Action entry gains "Run command" as an example alongside Open in T3 Code and SSH.

**Blocked by:** 01 — rename lands first so this diff is clean.

**Status:** resolved

- [x] `SpriteAction` lives in the Actions area with a non-optional `Kind`; no optional URL remains
- [x] Open in T3 Code and Run command appear in the same action list on the detail screen
- [x] Tapping Run command presents the exec sheet with streaming output, exit code, and cancel, as before
- [x] CONTEXT.md's Action entry lists Run command as an example
- [x] Action contribution is covered by tests asserting on action data equality

## Answer

Implemented in commit 5f24ebe. `SpriteAction` moved to `Sources/SpritesCore/Actions/SpriteAction.swift` with a non-optional `Kind` (`.openURL(URL)`/`.runCommand`); the model appends the app's Run command entry so the detail screen renders one uniform list, with the exec sheet unchanged behind it. CONTEXT.md's Action entry lists Run command; recognition tests assert on action data equality.
