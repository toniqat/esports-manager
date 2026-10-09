# Collection (M10)

**표시 텍스트는 l10n key (`collection` 도메인 + 공유 `ui.*` · `term.*`)** — code uses `Loc.t(L.COLLECTION_…)`, stat names
`PlayerData.stat_label(i)`, the rank-row kind table `ROW_KIND_LABELS` holds keys (`collection.bt_kind.*`), row text uses
the kind templates `breakthrough.kind.*` (B1's domain) filled from the row `value`, a card_swap row names the new card
with `Loc.t(card_def.name_key)`. Scene nodes the script fills carry `auto_translate_mode = 2` (dummy text stays for
WYSIWYG); fixed captions are key literals.
Shared with other screens: origin team / stat total / load error reuse `run_setup.draft.origin_team` ·
`run_setup.stat_total` · `run_setup.load_failed`; summary titles are `term.pilot.owned` · `term.currency.levelup` ·
`term.currency.rank_stone`. Old breakthrough-era keys (`collection.detail.chip_max_level`, `…stats_title*`,
`…bt_after`, `…status_hint`, `collection.collection_cell.hint`, …) are `deprecated`.

Lobby `컬렉션` tab — owned pilots, their rank / level, level-up and rank-up. Contract:
`docs/outgame_dev_plan.md` §12 (work D); tab contract: `features/meta/lobby/LobbyScreen.gd` header.
Pilot progression rules (stars 등급 · rank 랭크 · breakthrough 돌파 · level) live in `ProfileManager` /
`RunRules` — `resources/README.md` + `autoloads/README.md`.

## Files
| File | Class | Role |
|---|---|---|
| `UI_View_CollectionTab.tscn` + `.gd` | `class_name CollectionTab extends Control` | The tab: summary card, role filter row, scrolling 4-column grid of the **owned pilots**, opens the detail sheet. `bar_specs()` = `[]` (no action bar). **Layout lives in the `.tscn`** (style = `OutgameTheme.tres` variations); built with `CollectionTab.create()` (not `.new()`) by `LobbyScreen._make_tab`. |
| `UI_Comp_CollectionCell.tscn` + `.gd` | `class_name CollectionCell extends Button` | Item scene: one grid cell (240×240): `%Face` in the rounded `ArtMask` + `%PositionBadge` top-left; inside the face (clipped by the mask) `LevelRibbon` / `%Level` bottom-left and `RankPlate` / `%Stars` bottom-right (template `%Star` duplicated up to the max rank). No name, no 등급 stars. `create()`; `setup(p, level, rank, max_rank)` / `refresh(level, rank, max_rank)`. Static helpers `stars_color` / `add_stars_pill` (등급 pill) shared with the sheet. F6 preview: Lv 7, rank 3 of max 4 (★★★ + one faint ★) |
| `UI_View_CollectionDetailSheet.tscn` + `.gd` | `class_name CollectionDetailSheet extends CanvasLayer` | Pilot detail modal (layer 20) + the 레벨업 / 랭크업 actions. **Layout lives in the `.tscn`** (style = `OutgameTheme.tres` variations). `create()` (not `.new()`), signals `leveled_up(pilot_id, new_level)` · `ranked_up(pilot_id, new_rank)`, static `fielded_copy(base, rank, level)`, static `preview_stage_pilots(pm, pool)` (F6 previews only). |
| `UI_Comp_CollectionStatChip.tscn` | — (no script) | Item scene: one 능력치 cell (`%Key` / `%Value` / `%Delta`), 7 instanced into `%StatGrid` once in `_ready`. |
| `UI_Comp_CollectionRankRow.tscn` | — (no script) | Item scene: one **rank** of the rank table (`%Disc`/`%Num`, `%Kind`, `%Desc`, `%State`), instanced per rank on every fill. One line per data row of that rank in `%Kind` / `%Desc` (same font size so the lines pair up); the sheet sets the height (44 + 32 × lines). |

Rules live elsewhere — this folder adds no rules and no const keys. Calls (B contract): `ProfileManager.owns_pilot` ·
`stars_of` · `rank_of` · `max_rank_of` · `breakthrough_of` · `breakthrough_cap_of` · `level_of` · `level_cap_of` ·
`pilot_exp_progress` · `level_up_cost` · `level_up_pilot` · `rank_up_cost` · `rank_up_block_reason` · `rank_up_pilot` ·
`currency_of` · `save_profile` (+ `grant_pilot` / `add_currency` in the F6 staging only); `RunRules.rank_rows` ·
`apply_rank` · `apply_level` · `rank_max` · `salary_of` · `team_short_name`.

## F6 preview (standalone run)
`CollectionTab`, `CollectionCell` and `CollectionDetailSheet` each shows dummy data when run on its own (editor
"Run Current Scene") — `_ready` → `UiPreview.is_standalone(self)` → `_fill_preview()` at the bottom of each script
(`resources/UiPreview.gd`). Nothing is saved: buttons that would save the profile are re-wired to only print
(`UiPreview.mute`).
- `CollectionTab` / `CollectionDetailSheet` — real profile, staged **in memory only** by
  `CollectionDetailSheet.preview_stage_pilots`: the highest-stars owned pilot gets one dupe (breakthrough → ★★★ + a
  faint ★), is leveled to its level cap and gets enough 승급석, so the grid shows a ★★★☆ cell and the sheet opens
  rank-up ready (the rank table shows reached · next · 돌파 필요 at once). The sheet's 레벨업 / 랭크업 only print.
- `CollectionCell` — hand-written values (Lv 7, rank 3 / max 4).

## Tab layout
Scene (`UI_View_CollectionTab.tscn`, scene-authored — `docs/ui_scene_migration.md`). The host sets the root's
position / size to its content rect; everything below follows by anchors / containers.
```
CollectionTab (Control, theme = OutgameTheme.tres, preview 1080×1696)
└ VBox (full rect, separation 20)
  ├ Top (Margin 24 / 20 / 24 / 0) ─ TopVBox (separation 20)
  │   ├ Summary (MarginContainer, min h 110) ─ Bg (Panel · Card) + Pad (Margin 28 / 0) ─ Content
  │   │     left:  OwnedTitle · %OwnedCount (BodyLabel 40)
  │   │     right (anchored): LevelupTitle · %Levelup (AccentLabel 40) │ RankStoneTitle · %RankStone (BodyLabel 40)
  │   └ %Filters (HBox 8, h 64) ─ 전체 · 탑 · 정글 · 미드 · 원딜 · 서폿 (`SelectableTile`, stretch)
  └ %Scroll (v-mode Never: no bar, DragScroll drags) ─ DragScroll · Body (VBox)
      ├ %LoadError (hidden; Margin 24 / 20) ─ %LoadErrorText (`NegativeLabel` 24)
      ├ %Empty (hidden; Margin 24 / 20) ─ EmptyText (`SubLabel`, "보유한 선수가 없습니다 …")
      └ GridPad (bottom 24) ─ %Grid (GridContainer 4 cols, 16 / 16, shrink-centre)
```
- **Code owns only data**: summary numbers (owned count — no `n / pool` progress since only owned pilots are listed;
  레벨업 재화; 승급석), the filter on / off state (variation name `SelectableTile` ↔ `SelectableTileOn` — the same tile
  pair as the run-setup and ban/pick filters; child i of `%Filters` = 전체 then `ROLE_DISPLAY_ORDER[i-1]`), one
  `UI_Comp_CollectionCell.tscn` item per owned pilot added to `%Grid` (`CollectionCell.create()`), the error / empty state.
- **Pool**: `GameManager.load_match_data()["players"]` once in `setup`, `is_mob == true` dropped. These CSV copies are
  never mutated. **Cells exist only for owned pilots** (`ProfileManager.owns_pilot`); `on_shown()` adds cells for pilots
  gained in another tab (gacha, pass) and drops cells of pilots no longer owned.
- **Order**: rank desc → level desc → stars (등급) desc → lane seat (`GameEnums.role_seat`) → id. Recomputed in
  `on_shown()` and after every level-up / rank-up (rank and level are sort keys).
- Filtering hides the other cells (the grid skips hidden children — no holes); sort order = child order
  (`move_child`). It resets the scroll to the top.
- Cells and the grid body are `MOUSE_FILTER_PASS` so a drag that starts on a cell still scrolls.
- After a sheet action (`leveled_up` / `ranked_up`): refresh that cell, re-sort, summary, `host.refresh_currency()`,
  `host.show_toast(...)` (`collection.tab.toast_level_up` / `toast_rank_up`).

## Detail sheet
Pattern C (`docs/mobile_safe_area.md`): dim = whole viewport (tap closes), sheet from
`top_y() + 48` to `bottom_y() - 16`, footer buttons end above the gesture zone. Body scrolls; the
status line and the footer (`닫기` 1 : `레벨업 · cost` 1.6 : `랭크업 · cost` 1.6) are fixed.

Scene (`UI_View_CollectionDetailSheet.tscn`, scene-authored — `docs/ui_scene_migration.md`):
```
CollectionDetailSheet (CanvasLayer 20 — 씬은 visible 로 저장, `create()` 가 숨김)
└ Root (full rect, theme = OutgameTheme.tres)
  ├ %Dim (flat Button, tap = close) · DimRect (DimPanel)
  └ %SafeArea (full rect; code sets top / bottom to the safe lines)
    └ Sheet (PanelContainer · SheetCard = padding 36 / 27, offsets 24 / 48 / -24 / -16 = gaps to the safe lines)
      └ VBox
        ├ ScrollSlot ─ %Scroll (offset_right 8: bar sits in the right padding; v-mode Reserve)
        │   ├ DragScroll (node)
        │   └ %Body (VBox, separation 32 = gap between sections)
        │     ├ Hero (HBox 28): %Bust (230×464, %BustPlate) │ Info VBox:
        │     │   TitleBlock (%Name, %RoleLine) · %Chips · gap · %ExpBlock (%ExpValue, %ExpTrack `ProgressTrack` / %ExpFill `ProgressFill`)
        │     │   · gap · SalaryRow (%SalaryTitle, %Salary) · %BonusRow (%Bonus `PositiveLabel` 30)
        │     ├ StatsSection: header (%StatsTitle + Divider) · %StatGrid (4 cols, 12) · %StatNote
        │     ├ RankSection: header (RankTitle + Divider) · %RankRows (VBox 10) · %RankAfter (%RankAfterLabel) | %RankEmpty
        │     └ CardsSection: header (%CardsTitle) · %Cards (VBox 12) · BottomPad 16
        ├ gap 6 · Divider · gap 5 · %Status (40) · gap 12
        └ Buttons (HBox 16): %Close (GhostButton, 1) · %LevelUp (PrimaryButton 32, 1.6) · %RankUp (PrimaryButton 32, 1.6)
```
- Text blocks whose labels overlap their nominal box (name 52 pt, salary value 30 pt) are plain
  `Control`s with a fixed minimum height and the labels placed by offsets inside — the VBox stacks the
  blocks, not the labels, so a label's font height never pushes the rows below.
- **Code owns only data**: role-tinted bust plate, the rounded bust art (`PilotThumb.add_rounded_art`,
  made once in `_ready`) + position badge (`PilotThumb.add_position_badge`; `%RoleLine` is only the home team), chip
  pills (sized to their text), EXP fill (`anchor_right` = ratio), stat-chip tints (`card_style(16, tint)`), rank row /
  disc styles (reached / next / locked), colours with no variation (`POSITIVE` / `NEGATIVE` deltas and status, disc
  number), label variation swaps for reached / next / locked rows, the `CardDescBox` panels, the safe-area offset.
- Open / close = layer `visible`; nodes are reused. `open(p)` refills and scrolls to the top; 레벨업 / 랭크업
  refill in place (scroll kept). Rows / cards are removed with `remove_child` + `queue_free` so the
  containers re-lay out in the same frame. `CardDescBox` measures text at a fixed width, so `%Cards`
  builds at its laid-out width and rebuilds on `resized` when that width changes (first layout pass).

- **Numbers = `fielded_copy(base, rank, level)`**: a duplicate of the pool pilot (own `pilot_cards` array) with
  `RunRules.apply_rank(rank)` then `RunRules.apply_level(level)` — the same calls run start makes, so the sheet shows
  what the pilot brings into a run today.
- Hero: bust (`PilotImages.bust_for`, width 230, ratio `BUST_ASPECT`) on a role-tinted plate; name, `원소속` team;
  chips **등급** stars (`add_stars_pill`, ★1 grey · ★2 blue · ★3 amber) / `랭크 n / max` / `돌파 n / cap` /
  `Lv n / cap`; **EXP toward the next level within the current rank** (`pilot_exp_progress` → `into / need → Lv n+1`,
  full bar + `레벨 상한 Lv {cap} 도달` at the cap); salary at the shown rank + level; `훈련 EXP 보너스 (랭크)` when
  `train_bonus_pct ≠ 0`.
- 능력치: six stats + 종합 (4 columns), each with the delta vs the raw data (rank 0 · Lv 0, green).
- **Rank table**: `RunRules.rank_rows` grouped by `rank` (several rows can share a rank) → one row per rank 1..5:
  reached (rank ≤ current) = amber row + `달성`; next (current + 1 and ≤ max rank) = `다음`; above the max rank =
  sunk / faint + `돌파 필요`. Desc = kind template `breakthrough.kind.<kind>` filled from `value` (`_row_desc`;
  `card_swap` appends `→ <card name>`). Note under it: dupes → breakthrough +1 = max rank +1 (cap).
- 파일럿 카드: `GameManager.pilot_card_ids_for(fielded)` as light `CardDescBox`es; the title says `랭크로 교체됨`
  only when a swap actually changed the list.
- **레벨업** (below the level cap): `ProfileManager.level_up_pilot` → `save_profile()` → status line + SUCCESS haptic
  → refill in place → `leveled_up`. Disabled with the reason on the status line: not owned / at the level cap
  (`at_level_cap`) / not enough `levelup` currency.
- **랭크업** (only at the level cap): enabled iff `rank_up_block_reason(pid) == ""` (rank < max rank and enough
  `rank_stone`); `rank_up_pilot` (rank +1, level 0, exp 0) → `save_profile()` → status `rank_up_done` → refill →
  `ranked_up`. Button text = `랭크업 · {rank_up_cost}`.
- **Status line** priority: last action's result (green / red) → below the cap: level-up reason (red) or
  `status_hint_level` → at the cap: `fully_grown` (rank = `RunRules.rank_max()`), else the rank-up block reason
  (red), else `status_hint_rank`.

## `UI_Comp_CollectionCell.tscn`
Fixed 240×240 item (absolute offsets inside the Button, frame `CollectionCellFrame`). The `ArtMask` (r12, inset 8)
clips the face and both corner tabs, so the tabs follow the rounded corners. Code fills data only: face texture,
position badge (`PositionBadge.set_role`), `Lv N` in the ribbon, and the stars: one `%Star` per rank up to the max
rank (stars + breakthrough), `CollectionCellStarOn` (amber) for ranks ≤ current, `CollectionCellStar` (faint white)
for unlocked-but-unreached ranks, nothing past the max rank.
Screen variations (`resources/README.md` → Screen variations): frame `CollectionCellFrame`, face mask
`CollectionCellArtMask`, ribbon `CollectionCellLevelRibbon`, star plate `CollectionCellRankPlate`, stars
`CollectionCellStar(On)`.
