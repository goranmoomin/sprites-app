# Abstraction shapes review

Tickets from the 2026-08 review of how CONTEXT.md language is represented in code. Decisions were grilled one-by-one; each ticket encodes an accepted decision.

- 01 — Rename `spriteName` to `sprite` everywhere (mechanical prefactor; blocks 02-06 for diff cleanliness only)
- 02 — Capabilities (`.codingAgent`, `.controlPlane`) replace IntegrationRole and IntegrationRequirement
- 03 — Flows join the Integration protocol; detail screen offers flows via the injected seam (blocked by 02)
- 04 — `T3Pairing` prefix; T3's prompt vocabulary homed with the integration
- 05 — Closed status enums (ServiceStatus, SpriteStatus) with `unknown(String)` tolerance
- 06 — `SpriteAction.Kind` (`openURL`/`runCommand`); unified action list; SpriteAction out of the Integration file
- 07 — Fake platform asserts no deep call on a cold, never-woken Sprite (parallel to everything)

Decisions deliberately not ticketed: Sprite handle stays a bare String (no newtype); the platform seam stays one protocol (no shallow/deep split); FlowPrompt stays a closed enum with integration-specific prefixed cases welcome; keep-alive/heartbeat left as-is (q7 dropped).
