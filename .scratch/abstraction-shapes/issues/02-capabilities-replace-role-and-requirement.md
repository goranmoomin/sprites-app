# 02 — Capabilities replace IntegrationRole and IntegrationRequirement

**What to build:** Unify the two closed enums on the Integration protocol into one capability vocabulary. A closed `Capability` enum names the integration categories from CONTEXT.md (`.codingAgent`, `.controlPlane`, extensible by adding cases). Each Integration declares `provides: [Capability]` and `requires: [Capability]`: Claude Code provides `.codingAgent`; T3 Code provides `.controlPlane` and requires `.codingAgent`. Requirements stay declared data, not opaque checks, because the create-sprite playlist uses them to point the user at the blocking entry. Satisfaction is computed in exactly one place in core: a required capability is met when some integration providing it is observed ready (deep observation, never app-side memory). The playlist's prerequisite ordering and the coding-agent guard step inside the T3 setup Flow re-derive their queries from provides. `IntegrationRole` and `IntegrationRequirement` are deleted. CONTEXT.md's coding agent and control plane entries note that the categories are capability-derived.

**Blocked by:** 01 — rename lands first so this diff is clean.

**Status:** ready-for-agent

- [ ] `Capability` is a closed enum; `IntegrationRole` and `IntegrationRequirement` no longer exist
- [ ] Integrations declare provides/requires; satisfaction ("some provider observed ready") lives in one core function
- [ ] The playlist still refuses to start the T3 entry before a coding agent is ready and still points at the Claude entry as the prerequisite
- [ ] The T3 setup Flow's guard step still fails cleanly when no coding agent is logged in
- [ ] CONTEXT.md reflects the capability-derived categories
- [ ] Existing playlist and integration tests pass, rewritten only where they named the old enums
