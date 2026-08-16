# 01 - Remove logout Flows

**What to build:** No Integration offers a logout Flow or action any more, Claude Code included. The reversal for an unwanted or resurrected login is deleting the Sprite, and the app says so where it matters: the login Flow's save consent and the checkpoint copy note that a Checkpoint restore can bring a planted login back. Forgetting a saved login from the app menu is untouched.

**Blocked by:** None - can start immediately.

**Status:** ready-for-agent

- [ ] The Claude Code logout Flow, its step, and its offering are gone; the detail screen never lists it
- [ ] The Claude login save consent and the checkpoint copy mention that a restore can bring a login back and that deleting the Sprite is the reversal
- [ ] Logout tests are removed; flow-offering tests assert no logout Flow is offered on a logged-in Sprite
- [ ] ADR-0007 (already amended) matches the code
