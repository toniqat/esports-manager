# Team Draft

Initial campaign step: the player picks one pilot per role (5 total) from
the 40-pilot pool. The displaced pilot from team-0 swaps with the picked
pilot's prior team — every team always has exactly one pilot per role.

## Files
| File | Role |
|---|---|
| `TeamDraft.gd`     | `class_name TeamDraft extends Control` — data layer. Owns `validate_draft()`, `apply_draft()`, `get_pool_grid()`. Builds `TeamDraftView` lazily via `ensure_view()` (called by `SeasonHub` after `init_season`). |
| `TeamDraftView.gd` | `class_name TeamDraftView extends Control` — procedural UI (5×8 grid + summary row + confirm button). Lives as a child of the `TeamDraft` node. |
| `PilotCard.gd`     | `class_name PilotCard extends Button` — single-pilot card (name, role, team, 5 stat bars). Builds itself on first `setup(pilot, selected)`. Emits `card_tapped(pilot_id)` on press. |
| `PilotCard.tscn`   | Thin scene wrapper around `PilotCard.gd`. Instanced by `TeamDraftView` once per pool entry. |

## UI flow
1. `SeasonHub._show_draft()` calls `TeamDraft.ensure_view()` then sets `TeamDraft.visible = true`.
2. `TeamDraftView` instantiates 40 `PilotCard`s, laid out as 5 columns (role) × 8 rows (candidates ranked by total stats).
3. Tapping a card picks the pilot for its role; tapping the same card again unpicks; tapping a different card in the same role swaps the pick.
4. The top summary row shows the current 5-pick state (one slot per role).
5. The "드래프트 확정" button activates only when all five roles are filled.
6. Confirm → `TeamDraft.apply_draft()` rewires team rosters → `SeasonHub.goto(Screen.HUB)`.

## Layout (1080×1920 portrait)
| Y range   | Block |
|---|---|
| 0..68     | Title "TEAM DRAFT" |
| 76..104   | "내 팀 (X/5)" count label |
| 110..220  | 5 summary slot panels (role-colored borders) |
| 248..274  | Role column headers |
| 280..1680 | 5×8 grid of PilotCards (each 200×175) |
| 1720..1840 | Confirm button |
