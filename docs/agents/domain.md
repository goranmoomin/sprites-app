# Domain Docs

This repository uses a single-context domain documentation layout.

## Before exploring

- Read `CONTEXT.md` at the repository root.
- Read ADRs under `docs/adr/` that affect the area being changed.
- If either is absent, proceed silently.

## File structure

- `CONTEXT.md`: domain language and concepts
- `docs/adr/`: architectural decisions
- `src/`: implementation

## Use the glossary vocabulary

When output names a domain concept, use the term defined in `CONTEXT.md`. Do not drift to synonyms that its glossary explicitly avoids.

If a needed concept is absent, reconsider whether the term belongs to the project or note the gap for the `domain-modeling` skill.

## Flag ADR conflicts

If proposed work contradicts an existing ADR, surface the conflict explicitly rather than silently overriding the decision.
