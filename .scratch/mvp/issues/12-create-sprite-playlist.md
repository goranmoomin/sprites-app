# 12 — Create-sprite playlist

**What to build:** Creation becomes name + a skippable playlist of ordinary Flows: after the sprite exists, the wizard offers the coding-agent login Flows (Claude Code), then the control-plane setup Flows (T3 Code), every step skippable, each step the same Flow launchable from the detail screen. Interruption at any point (app killed, user bails) leaves a perfectly consistent sprite whose detail screen shows exactly which Flows remain available. No draft state, no rollback, no cleanup.

**Blocked by:** 03 — Create and delete a sprite; 08 — Claude Code login Flow; 10 — T3 Code setup Flow and Pairing.

**Status:** resolved

- [ ] Full happy path: name -> Claude login -> T3 setup -> pairing -> detail screen, in one guided run
- [ ] Every step is skippable; skipping lands on the detail screen with remaining Flows offered
- [ ] Killing the app mid-playlist leaves a sprite whose detail screen observes true partial state (fake test)
- [ ] The playlist reuses the identical Flow implementations the detail screen launches
- [ ] Control-plane steps whose dependencies are unmet (no agent logged in) explain why and offer the prerequisite Flow
