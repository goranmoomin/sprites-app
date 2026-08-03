# 05 — Closed status enums with unknown-tolerance

**What to build:** Service and Sprite statuses become closed enums that cannot brick observation. `ServiceState.status` changes from a bare string to a `ServiceStatus` enum over the platform's documented set (`stopped`, `starting`, `running`, `stopping`, `failed`); `SpriteStatus` keeps `cold`/`warm`/`running`. Both gain unknown-tolerance: decoding an unrecognized wire value folds into an `unknown(String)` case that preserves and displays the raw string verbatim instead of throwing, so a platform-side status addition degrades to verbatim display rather than a failed decode of the whole sprite list or services response (ADR 0001 posture: show what was observed). Every `"running"`-style string literal comparison in production code and tests becomes an enum case.

**Blocked by:** 01 — rename lands first so this diff is clean.

**Status:** resolved

- [x] `ServiceStatus` covers the five documented values; `SpriteStatus` covers cold/warm/running; both have an `unknown(String)` case
- [x] Decoding a novel status value succeeds and surfaces the raw string verbatim in the UI
- [x] No string-literal status comparisons remain in Sources or Tests
- [x] Integration recognition, service controls, and detail-screen readiness behave exactly as before

## Answer

Implemented in commit 5653c1a. `ServiceStatus` (stopped/starting/running/stopping/failed) and `SpriteStatus` (cold/warm/running) both fold unrecognized wire values into `.unknown(String)` via `init(wire:)` and display them verbatim via `display`. A replay fixture with a novel "hibernating" status proves the decode survives; no string-literal status comparisons remain.
