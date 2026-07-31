# 03 — Create and delete a sprite (name only)

**What to build:** A Create sprite button suggests a haikunator-style name (adjective-noun-token, reimplemented from flyctl's word lists), editable before creation; the new sprite appears in the list. Delete lives on the sprite and asks one concise destructive confirmation before calling the platform delete. No Flow playlist yet — that is ticket 12.

**Blocked by:** 02 — Sprite list with shallow observation.

**Status:** resolved

- [ ] Suggested names follow adjective-noun-token and regenerate on request
- [ ] The user can edit or replace the suggested name; creation failures (e.g. name taken) surface inline
- [ ] Created sprite appears in the list without manual refresh
- [ ] Delete requires one destructive confirmation and removes the sprite from the list
- [ ] No archive, soft-delete, or export anywhere
