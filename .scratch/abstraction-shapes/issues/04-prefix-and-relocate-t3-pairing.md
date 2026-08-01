# 04 — Prefix and relocate T3's Pairing vocabulary

**What to build:** Keep FlowPrompt a closed enum of curated native screens (ADR 0002), but make integration-specific entries clearly prefixed and homed with their integration. `Pairing` is a T3-only term per CONTEXT.md, yet its type lives in the shared Flow vocabulary file and the prompt case is the unprefixed `.pairing`. Rename the struct to `T3Pairing` and define it in the T3 integration's files (same module, so the enum case still compiles); rename the case to `.t3Pairing(T3Pairing)`. The shared vocabulary file keeps only integration-neutral prompts (`.consent`, `.openURLAndEnterCode`) plus clearly prefixed integration cases. Future integrations follow the same convention: bespoke screens welcome, prefixed and homed with their owner. No rendering or behavior change.

**Blocked by:** 01 — rename lands first so this diff is clean.

**Status:** ready-for-agent

- [ ] `T3Pairing` is defined alongside the T3 integration; no `Pairing` type remains in the shared Flow vocabulary
- [ ] The prompt case is `.t3Pairing(T3Pairing)`; `.consent` and `.openURLAndEnterCode` are unchanged
- [ ] T3 setup and pair-again Flows render the pairing screen exactly as before
- [ ] Tests referencing the old names are updated and pass
