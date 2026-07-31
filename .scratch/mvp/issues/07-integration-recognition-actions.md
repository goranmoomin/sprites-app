# 07 — Integration recognition and Actions

**What to build:** The per-role integration architecture: each Integration contributes a command-match recognizer, observed status lines for the detail screen, and Actions. Observed services are classified by matching their cmd/args shape (verified available from the services API); anything unmatched is a Custom service. Demo path: a sprite with a service whose command matches `t3 serve` shows "T3 Code: service running" and an "Open in T3 Code" Action, regardless of who created the service or what it is named.

**Blocked by:** 04 — Sprite detail with deep observation.

**Status:** ready-for-agent

- [ ] Recognition is by command match on cmd/args; service names are ignored
- [ ] Multiple instances of one integration's services are all recognized
- [ ] Near-miss commands stay Custom
- [ ] Detail screen shows per-integration status lines (e.g. "T3 Code: service running")
- [ ] "Open in T3 Code" Action appears iff a T3-recognized service exists
- [ ] Cross-integration dependency declarations exist (T3 requires a logged-in coding agent) even if only surfaced later
