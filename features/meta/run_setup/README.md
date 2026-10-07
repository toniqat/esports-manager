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
| `RunSetupScreen.gd` (+ `scenes/RunSetup.tscn`) | `class_name RunSetupScreen extends Control` (scene root) | Orchestrator: step table `STEPS`, step header (`StepChip` per row), step views (into `%Steps`), builds `run_setup`, calls `GameManager.start_run`, launch fade. `content_top()` = where step bodies start (116). |
| `UI_Comp_StepChip.tscn` + `.gd` | `class_name StepChip extends Panel` | Item scene: one header pill. `create()`, `set_text`, `paint(bg, fg, border)` (state colours on a copy of the pill variation `StepChipPanel`). |
| `UI_View_ChoiceListView.tscn` + `.gd` | `class_name ChoiceListView extends Control` | Shared "pick one card" step: hint line → scrolling card list → bar `뒤로`(1) / `다음`(2). Subclasses fill `_items` / `_make_card(item) -> Button` / `_hint_text`. Signals `back_requested` / `next_requested`, value `selected_id`. **Nothing is pre-selected** — `다음` stays disabled until the player taps a card, so the rules (cap, team package) are read rather than skipped by tapping `다음` repeatedly. |
| `UI_View_ScenarioStepView.tscn` + `.gd` | `class_name ScenarioStepView extends ChoiceListView` | Step 1 — `RunRules.scenarios()` (`{id, name_key, salary_cap, desc_key}` — text fields are l10n keys) → one `ScenarioCard` each. Scene **inherits** `UI_View_ChoiceListView.tscn` (root script swapped). `create()`. |
| `UI_Comp_ScenarioCard.tscn` + `.gd` | `class_name ScenarioCard extends Button` | Item scene: name, salary-cap chip (`AccentChip` PanelContainer, 260×44), desc. Root variation `SelectableCardButton` (`...On` when chosen — `ChoiceListView._refresh`). `create()`, `fill(item)` — name / desc are `Loc.t` of the scenario's `name_key` / `desc_key` (`scenario.{id}.*`); F6 preview uses scenario 1's real keys. |
| `UI_View_TeamStepView.tscn` + `.gd` | `class_name TeamStepView extends ChoiceListView` | Step 2 — `RunRules.team_packages()` (8, `{id, name_key, short_name_key, budget, facility_level, manual_areas, desc_key}` — text fields are l10n keys) → one `TeamCard` each. Hint: higher budget = easier. Display / snapshot only — effects are M3 / M6. Scene inherits `UI_View_ChoiceListView.tscn`. `create()`. |
| `UI_Comp_TeamCard.tscn` + `.gd` | `class_name TeamCard extends Button` | Item scene: name · short name, budget (+ bar relative to the highest budget — `%Fill.anchor_right`), facility level, "직접 해야 하는 일" (`manual_areas` → `RunRules.area_label`, empty = "없음" in green), desc. Name / short / desc are `Loc.t` of the package's `name_key` · `short_name_key` · `desc_key`. `fill(item, max_budget)`. F6 preview uses team 3's real keys. |
| `UI_View_ManagerStepView.tscn` + `.gd` | `class_name ManagerStepView extends Control` | Step 3 감독 (M8/M9) — preset chips, the preset's six stats, `TraitPickerView` (from `../manager/`) with in-place trait swaps; `preset_idx`, `selected_traits()`, `validation_error()`. Signals `back_requested` / `next_requested`. `create()`. |
| `TeamDraft.gd` | `class_name TeamDraft extends Control` | Step 4 data layer: owned pool (`get_pool_grid()`), chosen levels (`levels`, `set_level`, `leveled()`), salary (`salary_of`, `lineup_salary`, `salary_cap` = `RunRules.salary_cap_with(scenario, trait_ids)`), `set_traits` / `cap_bonus()` (trait `salary_cap` Σ), `validate()` = `RunRules.validate_lineup(..., cap_bonus())`. Slot table `SLOT_ROLES` / `SLOT_NAMES` / `slot_of_role`, `skill_type_label`. Signals `back_requested`, `start_requested(pilot_ids)`. |
| `UI_View_TeamDraftView.tscn` + `.gd` | `class_name TeamDraftView extends Control` | Step 4 screen: salary gauge, 5 role-fixed `DraftSlot`s, role filter, scrolling thumbnail grid, PICK ↔ CONFIRM. Child of `TeamDraft` (`TeamDraftView.create()` in `ensure_view`). |
| `UI_Comp_DraftSlot.tscn` + `.gd` | `class_name DraftSlot extends VBoxContainer` | Item scene: one pick slot — bust art button (`%Frame`: mask + `%Art`, "선택 없음", `PositionBadge`) + `− Lv N +` stepper + salary / overall lines. Signals `art_pressed`, `level_step(delta)`; `set_role`, `show_empty()`, `show_pilot(p, role_color, lv, top, salary)`. Frame shape = variation `DraftSlotFrame` (code colours a copy), mask = `DraftSlotArtMask`. |
| `UI_Comp_PilotThumb.tscn` + `.gd` | `class_name PilotThumb extends Button` | Item scene: one grid cell — square face crop + top-left `PositionBadge` (`resources/`) + gold border / check when selected + bottom-right salary tag (`set_tag`). Frame = variation `SelectableCardButton` / `SelectableCardButtonOn` (radius 18); the face mask `ArtMask` (4px inset, variation `PilotThumbArtMask`) has radius 14 to follow it; check / tag = `PilotThumbCheck` / `PilotThumbTag`. `create()`, `setup(p, sel)`. Static helpers `add_rounded_art` / `add_role_badge` stay for code-built callers (`../collection/`). |
| `UI_View_DraftDetailPanel.tscn` + `.gd` | `class_name DraftDetailPanel extends CanvasLayer` | Pilot detail popup — **also used by ban/pick** (`features/match_flow/ban_pick/`). Layout lives in the `.tscn`; construct with `DraftDetailPanel.create()` (not `.new()`), then `open(p: PlayerData)` / `close()` / `is_open()`. See "DraftDetailPanel — scene" below. |
| `UI_Comp_DraftStatChip.tscn` + `.gd` | `class_name DraftStatChip extends PanelContainer` | Item scene: one stat chip of the detail popup (name over value, `SunkPanel`). `create()`, `fill(key, value, is_total)` — total swaps the value to `AccentLabel`. |
| `RunRoster.gd` | `class_name RunRoster` | AI roster distribution used by `GameManager.start_run` — owned by RunCore, see `features/season/README.md`. |

## F6 preview (standalone run)
Every scene in this folder except `RunSetup.tscn` shows dummy data when run on its own
(editor "Run Current Scene") — `_ready` → `UiPreview.is_standalone(self)` → `_fill_preview()` at the
bottom of each script (`resources/UiPreview.gd`). Nothing is saved.
- Item scenes (`StepChip`, `ScenarioCard`, `TeamCard`, `DraftStatChip`, `DraftSlot`,
  `PilotThumb`) — hand-written values (real pilot ids for the art), selected / filled state.
- `ChoiceListView` (base alone: three hand-written scenario cards) · `ScenarioStepView` · `TeamStepView`
  (real `RunRules` tables) — second card selected.
- `ManagerStepView` — real profile, active preset; `_preview` stops trait taps from saving the profile.
- `TeamDraftView` — no parent `TeamDraft`, so the branch runs **first** in `_ready` and injects one
  (game.db pool + real owned collection, first scenario), then seats the strongest five within the cap.
- `DraftDetailPanel` — opens the top-rated non-mob pilot with a skill (game.db), Lv 3.

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
preset chips (`ManagerPresetChips`, from `../manager/`) → stats card (`<type> 감독 · Lv n`, the preset's six stats via
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
The pick pane (`%PickPane`) sits before `%Bar` in the scene, so the exiting grid hides behind the bar.
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
- Thumbnails carry no name / stats lines — face, position badge, salary tag only.
- No position text or name under the illustration — the position badge stands even on an empty
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
header (name · position badge + original team, + breakthrough chips) → 6 stat chips + total → pilot skill (icon tile +
rich description) → the pilot's
**3 fixed pilot cards** (`GameManager.pilot_card_ids_for(pd)`, `CardDescBox.build(..., light = true)`).
The original-team short name is `GameManager.team_short_name(team_id)` — `season_state.team_meta`
keys, or — during run setup, before the season exists — the `RunRules.team_packages()` keys. The backing height follows the content
(stops where `%Column` — inside the device safe area — has no more room, then scrolls); the close
button follows that bottom edge and needs an
opaque style (it overlaps the bottom bar under the dim) — `GhostButton` is opaque white.

### DraftDetailPanel — scene (`UI_View_DraftDetailPanel.tscn`)
Moved from code-built to `.tscn` (`docs/ui_scene_migration.md`). `Root` carries
`resources/OutgameTheme.tres`; nodes pick theme variations. One instance per screen, reused:
`open` fills it and sets the layer `visible`, `close` hides it.
```
DraftDetailPanel (CanvasLayer 20 — 씬은 visible 로 저장, `create()` 가 숨김)
└ Root (full rect, theme)
  ├ %Dim            flat Button — tap outside closes
  ├ DimRect         Panel `DimPanel`
  ├ %ArtPlaceholder ColorRect (no art)          ┐ box: centre x 300, height 1400,
  ├ %Art            TextureRect keep-aspect     ┘ bottom 2010 (legs cut off-screen)
  └ %SafeArea       Control full rect — top / bottom offsets = device insets (`_fit_safe_area`, every `open`)
    └ %Column       VBox x 596 w 460, top 150, bottom anchored 80 above the safe bottom (grows down), sep 16
      ├ %PanelBox   Control, height set by code
      │ ├ Backdrop  Panel `Card`
      │ └ %Pad      MarginContainer 22 → %Scroll → %Body (VBox, sep 0)
      │     Header(%Name `HeadingLabel` 40, %PositionBadge_Position `PositionBadge` + %Sub `CaptionLabel`) · %BtRow(%BtChips) · Gap ·
      │     "선수 능력치" · %Stats (Grid 3 col, DraftStatChip ×7) · Gap · "파일럿 스킬" ·
      │     %SkillRow(%SkillTile slot, %SkillName `AccentLabel` 30, %SkillMeta) · %SkillDesc ·
      │     %NoSkill · Gap · "파일럿 카드" · %Cards (VBox sep 12) · BottomPad
      └ %Close      Button `GhostButton`, h 84
```
**Scene owns** positions, sizes, gaps, fonts, variations (layout edits go in the editor).
**Code owns** only the data-driven parts: the texts, the position badge (`set_role`), the art texture
and its width (`%Art` box narrowed to the art aspect around the scene's centre, so the art
samples on the same pixels as before), `%PanelBox` height (`%Body` minimum + `%Pad` margins,
capped at the `%Column` height − separation − `%Close` height, computed from the anchors because
`%Column.size` can stay inflated by the previous content's minimum), the `%SafeArea` insets (dim and art
stay full-screen — same as `MechDetailPanel`), and the widgets built by other modules into slots: breakthrough pills
(`OutgameTheme.add_chip` — per-chip colours), skill icon tile (`SkillImages.make_icon_tile`, size
= the `%SkillTile` slot), skill description (`StrategyIcon.make_rich_label`, width = `%Column`
width − `%Pad` margins) and pilot cards (`CardDescBox.build`). These are removed and rebuilt on
every `open`; the 7 stat chips are instantiated once in `_ready`.
- Card boxes get a **height-only** `custom_minimum_size` — a width minimum makes the
  ScrollContainer's minimum "content + scrollbar", which pushes `%Pad` 4px out of the panel
  the moment the bar appears and never shrinks back.
- Mobs (no skill) hide `%SkillRow` / `%SkillDesc` and show `%NoSkill`.

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
`DraftDetailPanel._fill_skill`: a 64px skill icon tile
(`SkillImages.make_icon_tile(sk.key, 64, OutgameTheme.RAIL, OutgameTheme.ACCENT, shadow)` —
rounded square with a soft drop shadow) sits at the left of the name row; the name is vertically
centred on the tile to its right, and the meta line (type · keyword) sits under the name in the
same column. The tile slot `%SkillTile` is inset 14px from the scroll body's left edge so the
`ScrollContainer` clip doesn't shave its shadow.

The description is a **RichTextLabel** (`_rich_paragraph` → `StrategyIcon.make_rich_label`), not a
plain Label — skill descriptions carry `\n` breaks, `{eul}` particle tags, keyword icons and
`[card name]` tokens. Colours follow the light `CardDescBox`: icon `ACCENT_TEXT`, knock = panel bg
(`SURFACE`), target `KeywordIcon.TARGET_ANY_COLOR` / `TARGET`, special
`KeywordIcon.SPECIAL_COLOR_LIGHT`; card costs (the cost ribbon before `[card name]`) come from
the description key's references (`CardData.ref_entries(description_key)`, `card_costs = true`).
Height is `StrategyIcon.rich_height(...)` with the same refs — never measured by hand.
Skill name / description are l10n keys (`name_key` · `description_key`) — `Loc.t`.

### Upper-body illustration — `PilotImages.bust_for`
An `AtlasTexture` crop of the upper part of `tall/N_tall.png` (`PilotImages.BUST_REGION`), whose
face scale is unified across pilots. Region ratio = `PilotImages.BUST_ASPECT` matches the slot cell
ratio (204 : 412) — change only one and faces get squashed.

## Scenes — what the `.tscn` owns vs what code owns
Moved from code-built to `.tscn` (`docs/ui_scene_migration.md` §4 #8). Every scene root carries
`resources/OutgameTheme.tres`; nodes pick variations. Construct with `Xxx.create()` (never `.new()`).
```
RunSetup (scenes/RunSetup.tscn — root offset_top = safe top inset, code)
├ %Background  ColorRect BG (code stretches it up into the notch: ScreenMetrics.extend_background)
├ %Header      HBox (24, 28) h 64, sep 12 — StepChip × STEPS (code)
├ %Steps       step views go here (code, one per STEPS row, built on first entry)
└ %ErrorLabel  load error line (`NegativeLabel` 26, drawn above the steps)

<step view> (ChoiceListView / ManagerStepView / TeamDraftView — same frame)
├ %Safe   full rect; code: offset_bottom = -bottom inset               ┐ OutgameTheme.fit_bottom_bar(%Bar, %Safe)
│ └ body, first block at y 116 (content_top)                           │
└ %Bar    HBox sep 0, bottom 128 — Back (BarGhostButton 30, stretch 1,   │
          Sep = BarSeparator Panel) / Next (BarPrimaryButton 38, stretch 2) │
          [/ Start] — code adds only the inset (rect + text lift)       ┘

ChoiceListView: %Hint (32,116) h 44 · %Scroll (24,168 → bottom -144, grows right only) → %List VBox sep 20, min w 1032
  UI_View_ScenarioStepView.tscn / UI_View_TeamStepView.tscn inherit it (+ one preview card under %List, cleared by code)
ManagerStepView: %Status · %Scroll → %Body VBox: %ManagerPresetChips_Chips (UI_Comp_ManagerPresetChips.tscn) · stats Card (%CardTitle, %CardNote, %Cells slot) · %TraitPickerView_Traits (UI_Comp_TraitPickerView.tscn)
TeamDraftView: Gauge Card (%GaugeTitle, %GaugeValue, track + %GaugeFill, %GaugeMsg) · %SlotRow HBox (DraftSlot ×5) ·
  %PickPane [%Filters HBox (6 SelectableTile buttons 26: 전체, then SLOT_ROLES order) · GridBack (`TeamDraftGridBack`) · %GridScroll → %Grid (5 cols, gap 8)]
```
**Scene owns** positions, sizes, gaps, fonts, variations and texts that never change (filter labels,
bar labels, "직접 해야 하는 일"). No local StyleBoxes — this folder's own looks are the screen variations
`DraftSlot*` · `PilotThumb*` · `StepChipPanel` · `TeamDraftGridBack`
(`resources/README.md` → Screen variations).
**Code owns** data and state: texts from tables, the per-device bottom inset
(`OutgameTheme.fit_bottom_bar` — the bar's square shape is the `Bar*` variations), selected / not
**variation names** (choice cards + thumbnails `SelectableCardButton` ↔ `SelectableCardButtonOn`,
filter buttons `SelectableTile` ↔ `SelectableTileOn`), step pill colours, role colours (badges, slot
frames), the gauge / budget bar fill ratio (`anchor_right`) and its over-cap colour, "없음"
(`BodyLabel` → `PositiveLabel`), the 감독 status line (`SubLabel` ↔ `NegativeLabel`) and stats-card note
(`FaintLabel` ↔ `AccentLabel`), the gauge message colour, the slot row y (PICK / CONFIRM, tweened) and the pick-pane slide, and content built by shared
modules into slots (`ManagerUi.add_stat_cells`); the shared `ManagerPresetChips` / `TraitPickerView` scenes are refilled (`fill`).
- Lists / grids are containers: hidden thumbnails are skipped by the `GridContainer` (filter = toggle
  `visible`); the bar's hidden `Next` / `Start` is skipped by the HBox.
- Label line heights exceed some boxes (38px name = 54, 26px = 37, 22px = 31): gaps in `ScenarioCard` /
  `TeamCard` are trimmed so text lands on the old pixels, and `DraftSlot`'s `Info` area is absolute because
  the stepper buttons (min 58) and the two lines overlap exactly like the old layout.
- Scrolls use `anchors_preset = -1` (grow right only): an anchors preset resets the grow direction to
  both, and the scroll bar's extra width would then push the content 4px left.

## Layout (1080×1920 portrait, Pattern B)
`RunSetupScreen` calls `ScreenMetrics.indent_to_safe_top(self)` + `ScreenMetrics.extend_background(%Background)`
once; step views must **not** indent again. Bottom-anchored blocks hang from `%Safe` (whose bottom code
lifts by the inset) — never from the viewport height.

| Block | Position |
|---|---|
| Step header | `HEADER_TOP` .. + `HEADER_H` |
| Choice steps | hint line at `content_top()`, card list down to `bottom_bar_top() - 16` (scrolls) |
| Lineup gauge card | `content_top()` .. + `GAUGE_H` |
| Lineup 5-pick block (PICK) | hangs above the filter row: `%Filters` top − 32 − slot row height (never above the gauge) — `_pick_row_y()` |
| Filter row / grid | grid hangs 12px above the bar (3.5 rows = 724), filter 16px above it — scene offsets from `%Safe` bottom |
| Lineup 5-pick block (CONFIRM) | vertical centre, clamped between gauge bottom and bar — `_confirm_row_y()` |
| Bottom bar | `%Bar` in each step scene — every step `뒤로`(1) / primary(2) |

Slot row height 538 = illustration (412) + info (126: stepper + salary + total lines). At 9:16 with no
insets the 5-pick block sits at y 406, the gauge ends at 280 — no overlap; on shorter safe areas
`_pick_row_y()` clamps below the gauge. Both y values are read from the scene nodes' rects.

## Scrolling — `DragScroll`
The grid and the choice lists scroll via `DragScroll` (`resources/DragScroll.gd`): mouse and touch
share one path, a 14px threshold starts a scroll and **cancels the press on the held
thumbnail / card**. Tap targets inside are `MOUSE_FILTER_PASS` (the press must reach the scroll).
