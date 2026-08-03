# 03 — Flows join the Integration protocol

**What to build:** Complete the CONTEXT.md sentence "offers Flows" in the type system. The Integration protocol gains a flows method taking the integration's observed context (services, observed status, sprite metadata) and returning the Flows it currently offers. The offering rules move out of the detail view into the integrations that own them: Claude Code offers its login Flow when not logged in; T3 Code offers setup when not ready and pair-again when a recognized service exists. The sprite detail model exposes the offered Flows computed from its injected integrations, so injecting fake integrations in tests or previews yields fake Flows: the view stops consulting the global registry. Cross-integration ordering is registry order; per-integration ordering is the integration's own. The create-sprite playlist keeps its curated entry list unchanged.

**Blocked by:** 02 — both reshape the Integration protocol; flows are written against the final capability-bearing protocol.

**Status:** resolved

- [x] The Integration protocol has a flows method; the detail view contains no per-integration flow conditions
- [x] The detail screen offers the same three Flows under the same conditions as before (login when not logged in, setup when not ready, pair-again when a t3 service is recognized)
- [x] Offered Flows come from the model's injected integrations; a fake integration's Flows appear when injected
- [x] Flow offering is covered by tests against the fake platform

## Answer

Implemented in commit 248147c. The protocol gains `flows(status:services:metadata:)`; Claude Code and T3 own their offering rules, `SpriteDetailModel.offeredFlows` collects them in registry order from the injected integrations, and the detail view renders that list (no registry consultation left in SpritesUI). Covered by `FlowOfferingTests`, including an injected fake integration.
