# Collection (M10)

Lobby `컬렉션` tab — owned pilots, levels, breakthroughs, level-up. Contract:
`docs/outgame_dev_plan.md` §12 (work D); tab contract: `features/meta/lobby/LobbyScreen.gd` header.

## Files
| File | Class | Role |
|---|---|---|
| `CollectionTab.gd` | `class_name CollectionTab extends Control` | The tab: summary card, role filter row, scrolling 4-column grid of the **25 named pilots**, opens the detail sheet. `bar_specs()` = `[]` (no action bar). |
| `CollectionCell.gd` | `class_name CollectionCell extends Button` | One grid cell (240×330): face + role badge (`PilotThumb` static helpers, read-only reuse) + rarity pill, name, `Lv N` + breakthrough pips. Unowned = dimmed face, `미보유` pill, "상점에서 영입". Static helpers `rarity_color` / `add_rarity_pill` / `add_pips` shared with the sheet. |
| `CollectionDetailSheet.tscn` + `.gd` | `class_name CollectionDetailSheet extends CanvasLayer` | Pilot detail modal (layer 20) + the 레벨업 action. **Layout lives in the `.tscn`** (style = `OutgameTheme.tres` variations). `create()` (not `.new()`), signal `leveled_up(pilot_id, new_level)`, static `fielded_copy(base, max_level, stage)`. |
| `CollectionStatChip.tscn` | — (no script) | Item scene: one 능력치 cell (`%Key` / `%Value` / `%Delta`), 7 instanced into `%StatGrid` once in `_ready`. |
| `CollectionBreakthroughRow.tscn` | — (no script) | Item scene: one 돌파 stage (`%Disc`/`%Num`, `%Kind`, `%Desc`, `%State`), instanced per row on every fill. |

Rules live elsewhere: `ProfileManager` (`max_level_of`, `breakthrough_of`, `pilot_exp_of`,
`level_up_cost`, `level_up_pilot`, `currency_of`), `RunRules` (`exp_required`, `apply_level`,
`breakthrough_rows`, `apply_breakthrough`, `salary_of`). This folder adds no rules and no const keys.

## Tab layout (local coordinates of the host's content rect)
| Block | Position |
|---|---|
| Summary card | y 20 .. 148 — `보유 선수 n / 25` + bar (left), `레벨업 재화` · `선수 파편` (right) |
| Filter row | 20 below — `전체` + lane order (`GameEnums.ROLE_DISPLAY_ORDER`, same labels as the lineup step) |
| Grid | 20 below the filter, down to the tab bottom; `OutgameTheme.add_vscroll` (DragScroll) |

- **Pool**: `GameManager.load_match_data()["players"]` once in `setup`, `is_mob == true` dropped.
  These Lv1 copies are never mutated.
- **Order**: owned first → rarity desc → lane seat (`GameEnums.role_seat`) → id. Recomputed in
  `on_shown()` (the profile may have changed in the shop / pass tab), together with every cell.
- Filtering reflows only the visible cells (no holes) and resets the scroll to the top.
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
    └ Sheet (Panel · SheetCard, offsets 24 / 48 / -24 / -16 = gaps to the safe lines)
      └ Margin (36 / 27 / 36 / 27) ─ VBox
        ├ ScrollSlot ─ %Scroll (offset_right 8: bar sits in the right padding; v-mode Reserve)
        │   ├ DragScroll (node)
        │   └ %Body (VBox, separation 32 = gap between sections)
        │     ├ Hero (HBox 28): %Bust (230×464, %BustPlate) │ Info VBox:
        │     │   TitleBlock (%Name, %RoleLine) · %Chips · gap · %ExpBlock (%ExpValue, %ExpTrack/%ExpFill)
        │     │   | %UnownedBlock · gap · SalaryRow (%SalaryTitle, %Salary) · %BonusRow (%Bonus)
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
