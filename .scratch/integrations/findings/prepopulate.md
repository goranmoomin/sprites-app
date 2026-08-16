# Prepopulate files, and run commands

Putting the user's own content onto every new Sprite - an `AGENTS.md`, a
`CLAUDE.md`, a real `.gitconfig` identity, a set of custom commands - so a
fresh Sprite starts in their preferred shape rather than the base image's.
Plus, separately, running arbitrary shell once per Sprite.

Evidence from live probes on `probe-integrations` (Ubuntu 26.04 base image,
2026-08-11), plus a read of the app's own persistence surfaces.

## Verdict

This fits the mint-once / plant-many mechanism better than any of the
credential integrations, for a reason none of them share: there is no
minting at all. The artifact is authored, not obtained, so the entire
interactive half of the Claude flow disappears and what remains is the half
that already works - an app-side saved artifact plus a silent per-Sprite
plant.

It also fits ADR-0001 better than the credential integrations, because a
planted file can be honestly re-observed. Hash what is on the Sprite,
compare against what the app holds, and you get three real states: absent,
matches, differs. Compare the credential integrations, whose best answer is
"the CLI claims it is logged in".

The awkward half is commands, which leave nothing observable behind.

## Two Flows, told apart by what they can claim

Decided with the user, 2026-08-12. "Run custom commands" means arbitrary
shell, not Claude's markdown custom commands.

Both halves are ordinary Flows - a Flow is the only way anything reaches a
Sprite. The difference is not delivery but what each can honestly say
afterwards:

1. A plant-files Flow. Writes an app-side saved set of files. Idempotent,
   re-appliable, and its artifact can be re-observed by content hash, so it
   can contribute a status and a readiness.
2. A run-commands Flow. Runs user-authored shell once. Its success is its
   exit code and nothing more. Nothing proves it ran, or that the effect
   survived, so it contributes no status at all and the next observation
   learns nothing from it.

Fusing them would have forced a choice between inventing state for commands
and dropping the file half to the same unobservable level. Keeping them
apart is what lets the file half obey ADR-0001.

Note that pointing the plant-files Flow at `~/.claude/commands/*.md` gives
Claude custom commands for free, since those are just markdown in a
directory. That is a target, not a separate feature.

## Probably not an Integration

CONTEXT.md defines an Integration as "First-party support for one
third-party capability on a Sprite". There is no third party here.

Current direction (user, 2026-08-12): this is not an Integration but a step
in the create-sprite path plus a detail-screen Action, with the exact shape
deferred rather than settled - worth revisiting once the three credential
integrations have shown what the registry actually needs.

Consequences if that holds: the two Flows never enter `Integrations.all`,
they contribute no capability and can never be a prerequisite, and the
hash-compare status described below needs somewhere other than
`IntegrationStatus` to live.

## Where the content goes

User-level, not project-level. The decisive fact is that a fresh Sprite has
no project directory at all - no `/workspace`, no `~/workspace`, just
`/home/sprite` - so a project-level `AGENTS.md` has nowhere to land until
the user clones something.

Free slots, verified absent on a fresh Sprite:

- `~/.claude/CLAUDE.md`, Claude Code user memory
- `~/AGENTS.md`, read by the installed Claude Code and by Codex
- `~/.claude/commands/*.md`
- `~/.claude/skills/*/SKILL.md`

Occupied by the platform, so they need a merge or append rule rather than a
write:

- `~/.gemini/GEMINI.md`, 1111 bytes, which itself opens with
  `@/.sprite/llm.txt` and `@/.sprite/llm-dev.txt` imports - so the platform
  already uses the import idiom and a user file can too
- `~/.cursor/rules/sprite.mdc`, 1199 bytes

And `~/.gitconfig`, which is the strongest single argument for this feature
existing: the base image ships `user.name = Sprite`, `user.email =
noreply@sprites.dev`, so every commit made on a Sprite is authored by
nobody. That composes directly with Log in to GitHub, which is the other
moment the app could fix it.

Supporting facts:

- The platform already does exactly this kind of fan-out itself:
  `~/.sprite-shared/skills/{sprite,sprite-api-gateway}/SKILL.md` is copied -
  not symlinked, verified with `ls -ld` and `readlink -f` - into
  `~/.claude/skills`, `~/.codex/skills`, `~/.cursor/skills` and
  `~/.gemini/skills`. There is precedent for one source landing in several
  per-agent locations.
- The installed `claude` 2.1.220 binary contains 7 occurrences of the string
  `AGENTS.md`, so it does read that file.

## Mechanics, verified

- Large plants are fine. 200,001 bytes written through the exact mechanism
  `HTTPSpritesPlatform.writeFile` uses (`sh -c 'mkdir -p DIR && cat > PATH'`
  with content on stdin) arrived intact; `wc -c` on the Sprite returned
  200001. No chunking needed at realistic sizes.
- Written files land mode 644, owner `sprite`, and `mkdir -p` creates
  intermediate directories. Content is not secret, so 644 is acceptable here
  - unlike the credential plants, which need an explicit chmod.
- `/usr/bin/sha256sum` and `/usr/bin/md5sum` are both present, so one exec
  can hash N planted paths and return all of them. Status stays a single
  deep call regardless of how many files a profile holds.
- The `sprite` user has passwordless sudo, so the run-commands Flow can do
  anything to the box, including to the app's own artifacts.

## Status model

Hash-compare gives three honest states: absent, matches, differs.

"Differs" is not an error. It is the normal result of the user editing the
file on the Sprite, or of editing the profile in the app afterwards. So the
status line has to distinguish "not applied here" from "applied, then
diverged", and re-applying has to be a deliberate act, because it overwrites
the Sprite's copy.

Checkpoint restore is benign here, unlike in the credential integrations: a
restore resurrects old content and the next observation reports `differs`,
which is the correct answer with no extra machinery. That is a point in
favour of content-hash observation generally.

## Problems this raises that the credential integrations do not

1. There is no app-side content store, and no authoring UI. The app persists
   exactly two things today, both secrets, both single-slot:
   `KeychainTokenStore` (the Sprite token) and `KeychainClaudeLoginStore`
   (the saved Claude login), wired in `App/SpritesApp.swift`. There is no
   `UserDefaults` usage anywhere in `Sources` or `App`. A profile of
   arbitrary files needs a new persistence surface, and content is not a
   secret, so the Keychain is the wrong home - unless a profile is allowed
   to carry secrets, which is itself a decision.

2. Authoring markdown on a phone is miserable. Realistic content sources, in
   ascending order of usefulness: paste into a text field; import from the
   Files app; share-sheet in; fetch from a git repo. The last is much the
   strongest and would make this mostly a thin wrapper over `git clone` plus
   Log in to GitHub for private dotfiles - worth considering explicitly
   rather than defaulting to building a text editor.

3. Path ownership collisions. The Claude integration owns
   `~/.claude/settings.json`: it plants the token into the `env` block and
   appends heartbeat hooks. A feature that writes user-chosen paths can
   silently destroy both. The plan needs an owned-path rule - refuse, warn,
   or merge - and refusing a small denylist is the cheapest honest answer.

4. Commands have no honest status, which is why they are a separate Flow.
   The alternative considered and rejected was a receipt file recording that
   we ran something; it is observable, but it records "we ran this" and
   would be read as "the effect is still present", which is a different and
   false claim.

5. Arbitrary shell with passwordless sudo needs consent copy that says so,
   and a decision about failure semantics - a partially-applied setup script
   leaves the Sprite in a state neither the app nor the user can describe.

## Open questions

- Whether a profile is a single blob applied wholesale, or a list of
  independently toggleable items.
- Whether one profile is enough (like the single saved Claude login) or the
  user wants several to pick between at create time.
- Whether profile content may contain secrets, which decides Keychain versus
  app container.
- Whether git-repo-backed profiles are in scope, which would make this
  depend on Log in to GitHub.
