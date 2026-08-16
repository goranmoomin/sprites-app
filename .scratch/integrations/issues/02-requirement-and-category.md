# 02 - Requirement and Category replace Capability

**What to build:** A Flow declares what it needs as Requirements: sets of Integration ids, all sets needed, any ready member satisfying a set. Integrations declare only a display Category (coding agent, control plane, other). Launching a Flow whose Requirements are unmet ends blocked with a sentence naming the products ("needs Claude Code logged in on this sprite"), from one place, whether launched from the detail screen or the create path. `Capability`, `provides`, `requires` on Integration and the in-flow coding-agent check are gone (ADR-0008).

**Blocked by:** None - can start immediately.

**Status:** resolved

- [x] `Flow` carries `requires: [Requirement]`; `Requirement` is an any-of set of Integration ids, exposed as static members by the integrations that own them (T3 Code's supported coding agents)
- [x] `Integration` declares `category` and nothing about capabilities; `Capability` no longer exists
- [x] `FlowRun` checks Requirements once at start; the blocked outcome names the products; `RequireCodingAgentStep` and the playlist's separate pre-check are removed
- [x] The registry helper answers "first ready among these ids"
- [x] Tests: any-of satisfaction, all-of across Requirements, blocked sentence wording, T3 setup blocked without a ready supported coding agent from both launch points
- [x] Glossary terms Requirement and Category are used in code names and comments

## Answer

Done in 9ab7bfc. `Requirement(anyOf:)` on `Flow.requires`, checked once at the start of `FlowRun` (new `.blocked` phase with `blockedReason`, retry re-checks); `Integration.category`; `Capability`, `provides`, `requires` and `RequireCodingAgentStep` removed. Follow-up in ab8824b: the check reads the sprite's Services once so daemon-backed providers observe honestly.
