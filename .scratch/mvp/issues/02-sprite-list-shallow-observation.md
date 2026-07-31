# 02 — Sprite list with shallow observation

**What to build:** The logged-in user sees their sprites with name and platform status (cold/warm/running), refreshed on appear and pull-to-refresh. The list uses shallow observation only — control-plane metadata — and never wakes a sprite.

**Blocked by:** 01 — Log in with a Sprite token.

**Status:** resolved

- [ ] Sprites display name and cold/warm/running status from list metadata
- [ ] Pull-to-refresh re-observes
- [ ] The fake platform asserts no wake-inducing call is ever made from the list (ADR 0001)
- [ ] Empty state invites creating a sprite
