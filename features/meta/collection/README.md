# Collection (M10)

Lobby `컬렉션` tab — owned pilots, levels, breakthroughs, level-up. Contract:
`docs/outgame_dev_plan.md` §12 (work D); tab contract: `features/meta/lobby/LobbyScreen.gd` header.

## Files
| File | Class | Role |
|---|---|---|
| `CollectionTab.tscn` + `.gd` | `class_name CollectionTab extends Control` | The tab: summary card, role filter row, scrolling 4-column grid of the **25 named pilots**, opens the detail sheet. `bar_specs()` = `[]` (no action bar). **Layout lives in the `.tscn`** (style = `OutgameTheme.tres` variations); built with `CollectionTab.create()` (not `.new()`) by `LobbyScreen._make_tab`. |
| `CollectionCell.tscn` + `.gd` | `class_name CollectionCell extends Button` | Item scene: one grid cell (240×330): `%ArtMask`/`%Face` + `%RoleBadge` (`RoleBadge.tscn`) + `%Rarity` pill, `%Name`, `%Level` + `%Pips` (template `%Pip` duplicated to `RunRules.breakthrough_max()`). Unowned = dimmed face, `%Unowned` pill, `%Hint`. `create()`; `setup(p, max_level, breakthrough)` / `refresh(...)`. Static helpers `rarity_color` / `add_rarity_pill` / `set_rarity` / `rarity_pill_w` shared with the sheet. F6 preview: owned Lv 7, 돌파 3 |
| `CollectionDetailSheet.tscn` + `.gd` | `class_name CollectionDetailSheet extends CanvasLayer` | Pilot detail modal (layer 20) + the 레벨업 action. **Layout lives in the `.tscn`** (style = `OutgameTheme.tres` variations). `create()` (not `.new()`), signal `leveled_up(pilot_id, new_level)`, static `fielded_copy(base, max_level, stage)`. |
| `CollectionStatChip.tscn` | — (no script) | Item scene: one 능력치 cell (`%Key` / `%Value` / `%Delta`), 7 instanced into `%StatGrid` once in `_ready`. |
| `CollectionBreakthroughRow.tscn` | — (no script) | Item scene: one 돌파 stage (`%Disc`/`%Num`, `%Kind`, `%Desc`, `%State`), instanced per row on every fill. |

Rules live elsewhere: `ProfileManager` (`max_level_of`, `breakthrough_of`, `pilot_exp_of`,
`level_up_cost`, `level_up_pilot`, `currency_of`), `RunRules` (`exp_required`, `apply_level`,
`breakthrough_rows`, `apply_breakthrough`, `salary_of`). This folder adds no rules and no const keys.

## F6 preview (standalone run)
`CollectionTab` and `CollectionDetailSheet` each shows dummy data when run on its own (editor "Run Current Scene") — `_ready` →
`UiPreview.is_standalone(self)` → `_fill_preview()` at the bottom of each script
(`resources/UiPreview.gd`). Nothing is saved: buttons that would save the profile are re-wired
to only print (`UiPreview.mute`).
- `CollectionTab` — real profile, full 25-pilot grid; the sheet's 레벨업 only prints.
- `CollectionDetailSheet` — opens the most-developed owned pilot of the real profile.

## Tab layout
Scene (`CollectionTab.tscn`, scene-authored — `docs/ui_scene_migration.md`). The host sets the root's
position / size to its content rect; everything below follows by anchors / containers.
```
CollectionTab (Control, theme = OutgameTheme.tres, preview 1080×1696)
└ VBox (full rect, separation 20)
  ├ Top (Margin 24 / 20 / 24 / 0) ─ TopVBox (separation 20)
  │   ├ Summary (MarginContainer, min h 128) ─ Bg (Panel · Card) + Pad (Margin 28 / 28) ─ Content
  │   │     left:  OwnedTitle · %OwnedCount (BodyLabel 40) · OwnedTrack (ProgressTrack 300×10) ─ %OwnedFill
  │   │     right (anchored): LevelupTitle · %Levelup (AccentLabel 40) │ ShardTitle · %Shards (BodyLabel 40)
  │   └ %Filters (HBox 8, h 64) ─ 전체 · 탑 · 정글 · 미드 · 원딜 · 서폿 (`SelectableTile`, stretch)
  └ %Scroll (v-mode Never: no bar, DragScroll drags) ─ DragScroll · Body (VBox)
      ├ %LoadError (hidden; Margin 24 / 20) ─ %LoadErrorText (`NegativeLabel` 24)
      └ GridPad (bottom 24) ─ %Grid (GridContainer 4 cols, 16 / 16, shrink-centre)
```
- **Code owns only data**: summary numbers, `%OwnedFill.anchor_right` = owned ratio, the filter on / off
  state (variation name `SelectableTile` ↔ `SelectableTileOn` — the same tile pair as the run-setup and
  ban/pick filters; child i of `%Filters` = 전체 then `ROLE_DISPLAY_ORDER[i-1]`),
  one `CollectionCell.tscn` item per pilot added to `%Grid` (`CollectionCell.create()`), the error text.

- **Pool**: `GameManager.load_match_data()["players"]` once in `setup`, `is_mob == true` dropped.
  These Lv1 copies are never mutated.
- **Order**: owned first → rarity desc → lane seat (`GameEnums.role_seat`) → id. Recomputed in
  `on_shown()` (the profile may have changed in the shop / pass tab), together with every cell.
- Filtering hides the other cells (the grid skips hidden children — no holes); sort order = child
  order (`move_child`). It resets the scroll to the top.
- Cells and the grid body are `MOUSE_FILTER_PASS` so a drag that starts on a cell still scrolls
  (verified with emulated touch: drag scrolls, no sheet opens; a tap opens the sheet).

## Detail sheet
Pattern C (`docs/mobile_safe_area.md`): dim = whole viewport (tap closes), sheet from
`top_y() + 48` to `bottom_y() - 16`, footer buttons end above the gesture zone. Body scrolls; the
status line and the footer (`닫기` 1 : `레벨업 · cost` 2) are fixed.

Scene (`CollectionDetailSheet.tscn`, scene-authored — `docs/ui_scene_migration.md`):
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
        │     │   | %UnownedBlock · gap · SalaryRow (%SalaryTitle, %Salary) · %BonusRow (%Bonus `PositiveLabel` 30)
        │     ├ StatsSection: header (%StatsTitle + Divider) · %StatGrid (4 cols, 12) · %StatNote
        │     ├ BtSection: header · %BtRows (VBox 10) · %BtAfter (%BtAfterLabel) | %BtEmpty
        │     └ CardsSection: header (%CardsTitle) · %Cards (VBox 12) · BottomPad 16
        ├ gap 6 · Divider · gap 5 · %Status (40) · gap 12
        └ Buttons (HBox 16): %Close (GhostButton, 1) · %LevelUp (PrimaryButton 32, 2)
```
- Text blocks whose labels overlap their nominal box (name 52 pt, salary value 30 pt) are plain
  `Control`s with a fixed minimum height and the labels placed by offsets inside — the VBox stacks the
  blocks, not the labels, so a label's font height never pushes the rows below.
- **Code owns only data**: role-tinted bust plate, the rounded bust art (`PilotThumb.add_rounded_art`,
  made once in `_ready`) + role badge, chip pills (sized to their text), EXP fill (`anchor_right` =
  ratio), stat-chip tints (`card_style(16, tint)`), 돌파 row / disc styles, colours with no variation
  (role line, `POSITIVE` / `NEGATIVE` deltas and status, disc number), `AccentLabel` ↔ `CaptionLabel` /
  `BodyLabel` ↔ `SubLabel` swaps for reached / next rows, the `CardDescBox` panels, the safe-area offset.
- Open / close = layer `visible`; nodes are reused. `open(p)` refills and scrolls to the top; 레벨업
  refills in place (scroll kept). Rows / cards are removed with `remove_child` + `queue_free` so the
  containers re-lay out in the same frame. `CardDescBox` measures text at a fixed width, so `%Cards`
  builds at its laid-out width and rebuilds on `resized` when that width changes (first layout pass).

- **Numbers = `fielded_copy`**: a duplicate of the pool pilot (own `pilot_cards` array) with
  `RunRules.apply_level(max_level)` then `RunRules.apply_breakthrough(stage)` — the same calls run
  start makes, so the sheet shows what the pilot brings into a run at its max level. Unowned →
  Lv1, stage 0 ("영입 시").
- Hero: bust (`PilotImages.bust_for`, width 230, ratio `BUST_ASPECT`) on a role-tinted plate;
  name, `lane · ROLE · 원소속` (same words as `DraftDetailPanel`), chips rarity / `최대 Lv` /
  `돌파 n / 5` / `중복 n`; **EXP to the next automatic level** (`pilot_exp_of` vs
  `exp_required(max_level + 1)`, bar from `exp_required(max_level)`; bought levels are never taken
  back, so the bar can sit at 0); salary at the shown level; `훈련 EXP 보너스` when
  `train_bonus_pct ≠ 0`.
- 능력치: six stats + 종합 (4 columns), each with the delta vs the Lv1 / stage-0 base (green).
- 돌파 table: `RunRules.breakthrough_rows` — 5 rows, reached = amber row + `달성`, next = `다음`;
  `card_swap` rows append `→ <card name>` (`GameManager.card_def`).
- 파일럿 카드: `GameManager.pilot_card_ids_for(fielded)` as light `CardDescBox`es; the title says
  `돌파로 교체됨` only when a swap actually changed the list.
- **레벨업**: `ProfileManager.level_up_pilot` → `save_profile()` → status line + SUCCESS haptic →
  sheet rebuilds in place (scroll kept) → `leveled_up` → the tab refreshes that cell and the
  summary, `host.refresh_currency()`, `host.show_toast(...)`. Disabled with the reason on the
  status line: not owned / max level (`RunRules.max_level()`) / not enough `levelup` currency.

## `CollectionCell.tscn`
Fixed 240×330 item (absolute offsets inside the Button). Code fills data only: face texture, role
badge (`RoleBadge.set_role`), rarity pill (`set_rarity`: stars, rarity colour on an `AccentChip` copy,
width = `rarity_pill_w`, right edge kept), owned state — frame variation `FRAME_OWNED` /
`FRAME_UNOWNED`, `%Name` `BodyLabel` ↔ `SubLabel`, `%ArtMask` modulate `UNOWNED_MODULATE`, level row ↔
hint — and the pips (`CollectionCellPipOn` = reached, `CollectionCellPip` = not).
Screen variations (`resources/README.md` → Screen variations): frame `CollectionCellFrame` /
`CollectionCellFrameUnowned`, face mask `CollectionCellArtMask` (r12 = frame r16 − 8 inset / 2),
pips `CollectionCellPip(On)`, 미보유 pill `CollectionCellUnownedPill`. Renders pixel-identical to the
old code-built cell.
