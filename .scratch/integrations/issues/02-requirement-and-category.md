# 02 - Requirement and Category replace Capability

**What to build:** A Flow declares what it needs as Requirements: sets of Integration ids, all sets needed, any ready member satisfying a set. Integrations declare only a display Category (coding agent, control plane, other). Launching a Flow whose Requirements are unmet ends blocked with a sentence naming the products ("needs Claude Code logged in on this sprite"), from one place, whether launched from the detail screen or the create path. `Capability`, `provides`, `requires` on Integration and the in-flow coding-agent check are gone (ADR-0008).

**Blocked by:** None - can start immediately.

**Status:** ready-for-agent

- [ ] `Flow` carries `requires: [Requirement]`; `Requirement` is an any-of set of Integration ids, exposed as static members by the integrations that own them (T3 Code's supported coding agents)
- [ ] `Integration` declares `category` and nothing about capabilities; `Capability` no longer exists
- [ ] `FlowRun` checks Requirements once at start; the blocked outcome names the products; `RequireCodingAgentStep` and the playlist's separate pre-check are removed
- [ ] The registry helper answers "first ready among these ids"
- [ ] Tests: any-of satisfaction, all-of across Requirements, blocked sentence wording, T3 setup blocked without a ready supported coding agent from both launch points
- [ ] Glossary terms Requirement and Category are used in code names and comments
