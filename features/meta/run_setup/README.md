# Run setup

Everything between the lobby's `새 런` (New run) and the first season HUB —
`scenes/RunSetup.tscn`. White outgame theme (`OutgameTheme`), bottom action bar on every step.
Contract: `docs/outgame_dev_plan.md` §10 (M1). Replaces the old in-season DRAFT screen
(`features/season/draft/`, deleted — Season now always opens at HUB).

```
Lobby 새 런 ─▶ 1 시나리오 ─▶ 2 팀 ─▶ 3 감독 ─▶ 4 편성 (PICK ↔ CONFIRM) ── 게임 시작 ──▶ start_run ──▶ Season.tscn (HUB)
     ◀── 뒤로 ──┘   ◀── 뒤로 ──┘  ◀── 뒤로 ──┘  ◀── 뒤로 (PICK) ──┘
```

What `start_run` does with the result (validation, `run_seed`, AI roster distribution,
level application) is documented in `features/season/README.md` "Entry point"
(→ "Run start" and "AI roster distribution — `RunRoster.gd`").

## Files
| File | Class | Role |
|---|---|---|
| `RunSetupScreen.gd` | `class_name RunSetupScreen extends Control` (scene root) | Orchestrator: step table `STEPS`, step header, step views, builds `run_setup`, calls `GameManager.start_run`, launch fade. `content_top()` = where step bodies start. |
| `ChoiceListView.gd` | `class_name ChoiceListView extends Control` | Shared "pick one card" step: hint line → scrolling card list → bar `뒤로`(1) / `다음`(2). Subclasses fill `_items` / `_card_h` / `_fill_card` / `_hint_text`. Signals `back_requested` / `next_requested`, value `selected_id`. **Nothing is pre-selected** — `다음` stays disabled until the player taps a card, so the rules (cap, team package) are read rather than skipped by tapping `다음` repeatedly. |
| `ScenarioStepView.gd` | `class_name ScenarioStepView extends ChoiceListView` | Step 1 — `RunRules.scenarios()`: name, salary-cap chip, desc. |
| `TeamStepView.gd` | `class_name TeamStepView extends ChoiceListView` | Step 2 — `RunRules.team_packages()` (8): name · short name, budget (+ bar relative to the highest budget), facility level, "직접 해야 하는 일" (`manual_areas` → `RunRules.area_label`, empty = "없음"), desc. Hint: higher budget = easier. Display / snapshot only — effects are M3 / M6. |
| `ManagerStepView.gd` | `class_name ManagerStepView extends Control` | Step 3 감독 (M8/M9) — preset chips, the preset's six stats, `TraitPickerView` (from `../manager/`) with in-place trait swaps; `preset_idx`, `selected_traits()`, `validation_error()`. Signals `back_requested` / `next_requested`. |
| `TeamDraft.gd` | `class_name TeamDraft extends Control` | Step 4 data layer: owned pool (`get_pool_grid()`), chosen levels (`levels`, `set_level`, `leveled()`), salary (`salary_of`, `lineup_salary`, `salary_cap` = `RunRules.salary_cap_with(scenario, trait_ids)`), `set_traits` / `cap_bonus()` (trait `salary_cap` Σ), `validate()` = `RunRules.validate_lineup(..., cap_bonus())`. Slot table `SLOT_ROLES` / `SLOT_NAMES` / `slot_of_role`, `skill_type_label`. Signals `back_requested`, `start_requested(pilot_ids)`. |
| `TeamDraftView.gd` | `class_name TeamDraftView extends Control` | Step 4 screen: salary gauge, 5 role-fixed slots with level steppers, role filter, scrolling thumbnail grid, PICK ↔ CONFIRM. Child of `TeamDraft`. |
| `PilotThumb.gd` | `class_name PilotThumb extends Button` | One grid cell: square face crop + top-left role badge + gold border / check when selected + bottom-right salary tag (`set_tag`). Static helpers `add_rounded_art` / `add_role_badge` shared with the slot illustrations. |
| `DraftDetailPanel.gd` | `class_name DraftDetailPanel extends CanvasLayer` | Pilot detail popup — **also used by ban/pick** (`features/match_flow/ban_pick/`). `open(p: PlayerData)` only. |
| `RunRoster.gd` | `class_name RunRoster` | AI roster distribution used by `GameManager.start_run` — owned by RunCore, see `features/season/README.md`. |

## Steps — one table
`RunSetupScreen.STEPS` is the single list (`{id, label}`) the header and `뒤로` / `다음`
navigation read. **To add a step**: add one row and one branch in
`_make_step_view(id)` that builds the view and wires its back / next signals to
`_prev_step` / `_next_step`. Nothing else changes. Rows: `scenario` · `team` · `manager` · `lineup`.

- Each step view is built the first time it is entered and then only hidden / shown, so going
  back to the team step and forward again keeps the lineup picks and levels. Entering the
  lineup step calls `TeamDraft.set_scenario(scenario_id)` so a changed cap redraws the gauge.
- `뒤로` on step 1 → `Lobby.tscn`.
- Header: one pill per step — done = amber tint, current = amber fill, upcoming = white.
- The pilot pool is read **once** from `GameManager.load_match_data()["players"]` (Lv1 CSV
  copies) — `season_state` is not initialised yet during run setup. A load error is shown as a
  red line on the lineup step.

## Manager step (감독) — M8/M9, plan §12.0 / §12.2
`ManagerStepView`: status line at `content_top()`, then one `DragScroll` body down to the bar:
preset chips (`ManagerUi.add_preset_chips`) → stats card (`<type> 감독 · Lv n`, the preset's six stats via
`ManagerUi.add_stat_cells`, specialised part in amber, `manager_all` trait note) → `TraitPickerView`.
- **The active preset is preselected** — the "nothing preselected" rule is for the choice lists; a
  preset is a loadout already built in the lobby `감독` tab.
- Trait taps edit a draft copy of the chosen preset (`ManagerProgress.toggle_trait`). Whenever the
  draft is valid it is written back (`store_preset`) and the profile saved — the preset itself is
  edited. An invalid draft (bonus < 0) is never saved; switching chips drops it.
- `다음` is disabled while `ManagerProgress.validate_preset` fails; the reason replaces the status line
  (red). A prestige preset can't be edited here (reset it in the lobby tab).
- Specialisation (stat alloc) is not editable here — lobby tab only.
- `다음` → `RunSetupScreen.manager_preset = preset_idx`; `manager_traits()` feeds the lineup cap.

## Lineup step (편성) — the old draft, adapted
**Uma Musume–style character pick.** Bottom half: scrolling grid of owned pilots; above it
one row of role filters; above that the **upper-body illustrations** of the 5 picks with a
level stepper underneath; at the top the salary gauge.

### Grid = owned collection only
`TeamDraft.get_pool_grid()` is the single filter: pilots in `ProfileManager.owned_max_levels()`
(mobs are excluded as well — they are never collectible). Grid order is slot order, then overall
stat descending. Each thumbnail shows that pilot's salary **at the currently chosen level**.

### Levels
Under each filled slot: `−  Lv N  +` (1 … `ProfileManager.max_level_of(pid)`), then the
salary (`RunRules.salary_at`) and overall stat at that level. Buttons disable at the bounds
— with max level 1 both are disabled but the control still stands. Levels live only in
`TeamDraft.levels` (`{"<pilot_id>": int}`); the pool is never mutated — the slot numbers and
the detail popup read `TeamDraft.leveled(pid)`, a duplicate with `RunRules.apply_level`.

### Rules are visible while picking
The gauge card shows `<scenario> · 샐러리캡` (+ ` (특성 ±n)` when the preset's traits move the cap —
the cap is `RunRules.salary_cap_with`, re-read on every entry via `TeamDraft.set_traits`), `total / cap` and a bar; **over cap → red**
(even before all five are picked). The line below it is the rule state:
`포지션마다 1명씩 — n / 5명` → `샐러리캡 초과 …` (red) → any other `validate_lineup` error (red)
→ `편성 완료 — 남은 샐러리 n` (green). `다음` and `게임 시작` are disabled whenever
`RunRules.validate_lineup` fails — over-cap picks are allowed, not blocked, so the player sees why.

### PICK ↔ CONFIRM
PICK bar: `뒤로`(1, → team step) / `다음`(2). `다음` → CONFIRM: the pick pane (filter row +
grid + backplate) slides off the bottom and the 5-pick block drops to the vertical centre
(one tween, `MODE_ANIM_SEC`, cubic in-out); CONFIRM bar: `뒤로`(1, → PICK) / `게임 시작`(2).
The pick pane is attached before the bottom bar, so the exiting grid hides behind the bar.
While animating (`_busy`) all input is ignored.

### 게임 시작 → run start
1. The view re-validates **before the fade** (a start that would be rejected never covers
   the screen) and emits `TeamDraft.start_requested(pilot_ids)` in `GameEnums.Role` order.
2. `RunSetupScreen.build_run_setup` builds the §10.2 dictionary:
   `scenario`, `team_id`, `pilot_ids` (Role order), `pilot_levels` (String keys),
   `salary_cap` (`salary_cap_with` the preset's traits), `salary_total`, `preset` (§12.2 — the
   감독 step's index; `start_run` re-validates it and snapshots traits / stats).
3. `SceneFade.play` (fade to black → fake loading → fade in, a root `CanvasLayer` that
   survives the scene change). **At the moment the screen is covered**: close the detail
   popup, `GameManager.start_run(run_setup)`; `""` → `change_scene_to_file(Season.tscn)`
   (first HUB autosaves, `features/season/README.md` "Autosave triggers"); an error → the
   gauge line shows `시작 실패: …`, ERROR haptic, input re-enabled, and the fade lifts to reveal it.

The old `apply_draft` swap with team 0 is gone — the AI rosters are distributed by `start_run`.

### Things removed from the screen (kept from the draft)
- No title / head count — the five slots filling up already say it.
- Thumbnails carry no name / stats lines — face, role badge, salary tag only.
- No position text or name under the illustration — the role badge stands even on an empty
  slot; the name lives in the detail popup.
- Tapping the **illustration** opens the detail popup (emptying a slot = tapping the same
  thumbnail again in the grid, so there is no competing tap). The slot `Button` **must not be
  `flat`** — a flat button ignores the stylebox and the empty slot's frame vanishes.

### Role-fixed slots
Slot order is **MOBA lane order** from `GameEnums.ROLE_DISPLAY_ORDER` (탑 · 정글 · 미드 · 원딜 ·
서폿) via `TeamDraft.SLOT_ROLES`. Filter buttons and slots read the same table (filter `i = 0`
is "전체", then `SLOT_ROLES[i - 1]`). Free order isn't used because `validate_lineup` enforces
one per role.

## DraftDetailPanel — shared by two screens
The only outgame place to inspect one pilot: opened from the lineup slots (with the leveled
copy) and from the **assignment step of ban/pick** (both teams' portraits). It needs only a
`PlayerData` and the `GameManager` autoload. Left full-body art / right scrolling info panel:
header (name · slot · role · original team, + breakthrough chips) → 6 stat chips + total → pilot skill (icon tile +
rich description) → the pilot's
**3 fixed pilot cards** (`GameManager.pilot_card_ids_for(pd)`, `CardDescBox.build(..., light = true)`).
The original-team short name comes from `season_state.team_meta`, or — during run setup, before
the season exists — from `RunRules.team_packages()`. The backing height follows the content
(stops at `PANEL_BOTTOM`, then scrolls); the close button follows that bottom edge and needs an
opaque style (it overlaps the bottom bar under the dim).

Candidate-card pools per role (`pilot_card_slots_for_role` …) were deleted long ago and are not
revived — the single source of cards is `GameManager.pilot_card_ids_for`.

### Breakthrough (M10)
The panel never applies breakthroughs itself — the `PlayerData` it receives already carries them
(run setup pool: `RunRules.apply_breakthroughs(_pool, owned_breakthroughs())` in
`RunSetupScreen`; ban/pick: the run copies from `GameManager.start_run`), so stats, salary and the
`card_swap`-ed pilot card shown are already the broken-through ones. When `pd.breakthrough > 0` a
chip row under the header names it: `돌파 n` (amber) and, if `train_bonus_pct ≠ 0`,
`훈련 EXP +n%`. The full breakthrough table lives in the lobby collection sheet
(`features/meta/collection/`).

### Skill block — icon tile + rich description
`DraftDetailPanel._build_skill_block`: a 64px skill icon tile
(`SkillImages.make_icon_tile(sk.key, 64, OutgameTheme.RAIL, OutgameTheme.ACCENT, shadow)` —
rounded square with a soft drop shadow) sits at the left of the name row; the name is vertically
centred on the tile to its right, and the meta line (type · keyword) sits under the name in the
same column. The tile is inset `SKILL_TILE_X` from the scroll body's left edge so the
`ScrollContainer` clip doesn't shave its shadow.

The description is a **RichTextLabel** (`_rich_paragraph` → `StrategyIcon.make_rich_label`), not a
plain Label — skill descriptions carry `\n` breaks, `{eul}` particle tags, keyword icons and
`[card name]` tokens. Colours follow the light `CardDescBox`: icon `ACCENT_TEXT`, knock = panel bg
(`SURFACE`), target `KeywordIcon.TARGET_ANY_COLOR` / `TARGET`, special
`KeywordIcon.SPECIAL_COLOR_LIGHT`; card costs (the cost ribbon before `[card name]`) come from
`GameManager.card_costs_by_name()`. Height is `StrategyIcon.rich_height(...)` with the same
costs — never measured by hand.

### Upper-body illustration — `PilotImages.bust_for`
An `AtlasTexture` crop of the upper part of `tall/N_tall.png` (`PilotImages.BUST_REGION`), whose
face scale is unified across pilots. Region ratio = `PilotImages.BUST_ASPECT` matches the slot cell
ratio (204 : 412) — change only one and faces get squashed.

## Layout (1080×1920 portrait, Pattern B)
`RunSetupScreen` calls `ScreenMetrics.indent_to_safe_top(self)` + `OutgameTheme.add_background`
once; step views must **not** indent again. All y values derive from `content_top()` (top) and
`OutgameTheme.bottom_bar_top()` (bottom), never from the viewport height.

| Block | Position |
|---|---|
| Step header | `HEADER_TOP` .. + `HEADER_H` |
| Choice steps | hint line at `content_top()`, card list down to `bottom_bar_top() - 16` (scrolls) |
| Lineup gauge card | `content_top()` .. + `GAUGE_H` |
| Lineup 5-pick block (PICK) | hangs above the filter row: `filter_y() - 32 - SLOT_ROW_H` (never above the gauge) |
| Filter row / grid | grid hangs from the bar (`grid_y()`, 3.5 rows), filter above it |
| Lineup 5-pick block (CONFIRM) | vertical centre, clamped between gauge bottom and bar |
| Bottom bar | `OutgameTheme.add_bottom_bar` — every step `뒤로`(1) / primary(2) |

`SLOT_ROW_H` = illustration (412) + stepper + salary + total lines. At 9:16 with no insets the
5-pick block sits at ≈ y 406, the gauge ends at ≈ 280 — no overlap; on shorter safe areas
`pick_row_y()` clamps below the gauge.

## Scrolling — `DragScroll`
The grid and the choice lists scroll via `DragScroll` (`resources/DragScroll.gd`): mouse and touch
share one path, a 14px threshold starts a scroll and **cancels the press on the held
thumbnail / card**. Tap targets inside are `MOUSE_FILTER_PASS` (the press must reach the scroll).
