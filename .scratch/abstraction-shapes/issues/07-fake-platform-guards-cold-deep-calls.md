# 07 — Fake platform guards deep calls on cold Sprites

**What to build:** Turn the ADR 0001 discipline into a failing test instead of a comment. The shallow/deep observation split stays enforced by convention at the single choke point (the detail model's refresh gate); this ticket adds the test-side tripwire: the in-memory fake platform asserts that no deep operation (services, tasks, checkpoints, exec, files, service lifecycle) is performed on a Sprite that is cold and was never explicitly woken. Legitimate knowing wakes (explicit wake, Keep-alive on a cold Sprite, Flows and Actions the user tapped) must still pass: the fake's rule mirrors the ADR, deep is allowed once the Sprite is running or an explicit wake happened, not "never while cold". A deliberate violation test proves the tripwire fires; the existing suite stays green.

**Blocked by:** None — can start immediately.

**Status:** resolved

- [x] The fake platform fails loudly when a deep call hits a cold, never-woken Sprite
- [x] Explicit wake and Keep-alive paths still pass; Flow and Action tests still pass
- [x] A test demonstrates the violation being caught
- [x] The full existing suite remains green

## Answer

Implemented in commit c9a0d99. `FakeSpritesPlatform.deepTouch` throws `ColdDeepCallViolation` when a deep call hits a cold sprite outside the `explicitlyWoken` set; `wake()` and task upserts (Keep-alive) register knowing wakes. `ColdDeepCallTripwireTests` proves the tripwire fires and that wake and Keep-alive paths still pass; the full suite stays green.
