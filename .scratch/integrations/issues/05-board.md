# 05 - The Board on the create path and the detail screen

**What to build:** After naming a new Sprite, and in the detail screen's integrations section, the user sees the Board: rows for coding agents, control planes and other, one tile per Integration showing its observed status. Tapping a tile runs its offered Flow, or opens a chooser when it offers several (T3 Code: Connect first, then pairing over public URL, then pairing over tailnet, plus Pair again when a recognized Service exists). Coming back, the tile shows what the Sprite now reports. Nothing is ordered, remembered or marked done app-side; a tile whose Flow's Requirements are unmet shows the blocked reason. Statuses of all integrations load concurrently. The ordered playlist is gone.

**Blocked by:** 02 (Requirement and Category), 03 (Status details).

**Status:** resolved

- [x] A Board model built from the registry: rows in fixed Category order, tiles in registry order, each with the observed `IntegrationStatus` and the Flows the integration currently offers
- [x] The create-sprite second page and the detail screen integrations section both render the Board; `CreateSpritePlaylist` and its view are removed
- [x] Tile tap launches the single Flow or shows the chooser; after a Flow run finishes the Board re-observes
- [x] Blocked launches show the Requirement sentence on the tile
- [x] All integrations' `observeStatus` run concurrently; one integration throwing does not hide the others
- [x] Tests: rows by category, one tile per integration, chooser ordering for T3, state re-observed after a Flow, concurrent observation, create path ends with a consistent Sprite when the user leaves mid-way; playlist tests replaced
- [x] Glossary term Board is used in code names

## Answer

Done in 82327b5. `SpriteDetailModel.board` ([BoardRow] by Category, one `BoardTile` per integration with status and offered Flows), `blockedReason(for:)` from Board statuses, concurrent observation with per-integration failure isolation; `BoardSections` shared by `CreateSpriteBoardView` (takes the wake) and `SpriteDetailView`; playlist model, view and tests removed. Tile tap launches a lone Flow with no details, otherwise expands into details and Flow buttons.
