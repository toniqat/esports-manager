# Team Draft

Initial campaign step: the player picks one pilot per role (5 total) from
the **네임드 25인** pool. The displaced pilot from team-0 swaps with the picked
pilot's prior team — every team always has exactly one pilot per role.

**모브 파일럿 15명은 격자에 뜨지 않는다.** `pilot_skills.csv` 가 25개뿐이라
40명 중 15명은 고유 스킬이 없고(`players.is_mob = 1`), 그쪽은 초상화도 실루엣
컷인 "이름 없는 선수"다 — 플레이어가 뽑을 대상이 아니라 AI 팀의 머릿수를 채우는
배경이고, 적으로는 여전히 만난다. `get_pool_grid()` 가 그 필터의 유일한 지점이다.

**팀 0(플레이어 시작 팀)의 다섯 자리는 전부 네임드다.** `apply_draft` 의 맞교환이
네임드끼리만 일어나야 팀별 네임드 수가 드래프트로 흔들리지 않는다 — 네임드 25명은
팀 0 에 5명, 나머지 20명이 7개 AI 팀에 2~3명씩 흩어져 있다(`data/csv/players.csv`).

## Files
| File | Role |
|---|---|
| `TeamDraft.gd`     | `class_name TeamDraft extends Control` — data layer. Owns `validate_draft()`, `apply_draft()`, `get_pool_grid()`. Builds `TeamDraftView` lazily via `ensure_view()` (called by `SeasonHub` after `init_season`). |
| `TeamDraftView.gd` | `class_name TeamDraftView extends Control` — procedural UI (5×5 grid + summary row + confirm button). Lives as a child of the `TeamDraft` node. |
| `PilotCard.gd`     | `class_name PilotCard extends Button` — single-pilot card (name, role, team, 5 stat bars). Builds itself on first `setup(pilot, selected)`. Emits `card_tapped(pilot_id)` on press. |
| `PilotCard.tscn`   | Thin scene wrapper around `PilotCard.gd`. Instanced by `TeamDraftView` once per pool entry. |

## UI flow
1. `SeasonHub._show_draft()` calls `TeamDraft.ensure_view()` then sets `TeamDraft.visible = true`.
2. `TeamDraftView` instantiates 25 `PilotCard`s, laid out as 5 columns (role) × 5 rows (candidates ranked by total stats). 모브는 `get_pool_grid()` 가 이미 걸러 냈다.
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
| 280..1155 | 5×5 grid of PilotCards (each 200×175) — 예전 8행 시절에는 1680 까지 내려갔다 |
| 1720..1840 | Confirm button |
