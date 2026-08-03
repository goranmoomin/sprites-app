# 01 — Rename `spriteName` to `sprite` everywhere

**What to build:** One word for the Sprite handle across the codebase. The glossary decision: the app-side representation of a Sprite is its name string, and it is called `sprite`, never `spriteName`. The platform seam and Flow layer already say `sprite`; the observation models and views say `spriteName`. Rename the latter so every property, parameter, and initializer label agrees. Purely mechanical; no behavior change. Done first so every later ticket lands on the final naming.

**Blocked by:** None — can start immediately.

**Status:** resolved

- [x] No `spriteName` identifier remains in Sources or Tests
- [x] Core models and UI expose the handle as `sprite`
- [x] The full test suite passes unchanged in behavior

## Answer

Implemented in commit fc6cee1. Mechanical rename across Sources, Tests, and UI; no `spriteName` identifier remains and the suite passes unchanged.
