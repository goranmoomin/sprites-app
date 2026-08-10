# 05: Log out Claude Code sprite action

Spec: `.scratch/claude-setup-token/spec.md`

What to build: a "Log out Claude Code" action on the sprite detail screen,
offered while the integration observes logged in. It removes the planted
token from that Sprite: deletes the `CLAUDE_CODE_OAUTH_TOKEN` key from the
settings env block merge-preservingly (every other key and hook survives),
and best-effort removes the legacy `.credentials.json` to cover Sprites
logged in under the old interactive flow. Confirmation copy states that
this removes the login from this Sprite only: the token itself stays valid,
and stays saved in the app if it was saved.

This is also the remedy for Checkpoint restores resurrecting a previously
planted token. After the action, `auth status` genuinely flips, so the
detail screen agrees without special casing.

Blocked by: 02 (setup-token login replaces auth login).

Status: done (2026-08-10)

- [x] Action visible only when logged in; after running it the detail
      screen shows not logged in
- [x] Settings env edit preserves all other keys and the heartbeat hooks;
      legacy credentials file removed when present (fake-platform coverage)
- [x] Confirmation carries the does-not-revoke, stays-saved-in-app copy
