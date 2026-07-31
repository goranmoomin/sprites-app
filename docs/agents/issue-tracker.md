# Issue tracker: Local Markdown

Issues and specs for this repo live as Markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The spec is `.scratch/<feature-slug>/spec.md`
- Implementation issues are stored individually at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01`
- Triage state is recorded as a `Status:` line near the top of each issue
- Comments and conversation history are appended under a `## Comments` heading

## Publishing to the issue tracker

Create a file under `.scratch/<feature-slug>/`, creating the directory if needed.

## Fetching a ticket

Read the referenced issue file. The user will normally provide its path or issue number.

## Wayfinding operations

- Map: `.scratch/<effort>/map.md`
- Child ticket: `.scratch/<effort>/issues/NN-<slug>.md`
- Blocking: a `Blocked by: NN, NN` line near the top
- Frontier: the first numbered issue that is open, unblocked, and unclaimed
- Claim: set `Status: claimed` before beginning work
- Resolve: append the answer under `## Answer`, set `Status: resolved`, then add a context pointer to the map
