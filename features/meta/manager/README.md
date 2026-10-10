# Manager (M9)

Manager growth and presets between runs. Contract: `docs/outgame_dev_plan.md` §12.

표시 텍스트는 l10n key (`manager` 도메인 + 공유 `ui.*` · `term.*`) — `ManagerProgress` error strings are returned
already translated (`Loc.t`, never stored), stat names via `StaffSystem.stat_label`, trait rarity via
`GameEnums.rarity_label`. Scene nodes the scripts fill carry `auto_translate_mode = 2`; fixed captions are key literals.
Manager stats as a whole are `term.stat.manager` (key ref `{tx_…}` inside sentences, no "스탯"); one stat name is a ref to
`term.manager_stat.*`. The `전문화 +n` part label is `manager.tab.part_spec` (`ManagerUi.add_stat_cells`);
`manager.progress.stat_at_min` gets `{min}` = `StaffSystem.STAT_MIN`. Preset names (`manager.preset.name`, toasts) get
`{n}` = the Roman numeral the capsule shows (`ManagerUi.roman`). Keys of the old save bar / chip status / slot UI
(`manager.tab.{use_preset,save,…}`, `manager.preset.{in_use,…}`, `manager.trait_picker.{owned_title,…}`) are `deprecated`.

## Files
| File | Class | Role |
|---|---|---|
| `ManagerProgress.gd` | `class_name ManagerProgress extends RefCounted` (static) | Pure rules over the profile dict: levels (`manager_levels.csv`), removal / specialisation points, preset stats + validation, prestige. UI helpers: `level_progress`, `toggle_trait` (no count limit), `preset_copy` / `store_preset` |
| `UI_View_ManagerTab.tscn` + `.gd` | `class_name ManagerTab extends Control` | 감독 screen body (header · preset capsule · stats · traits). **Layout lives in the `.tscn`**; built with `ManagerTab.create()` (not `.new()`) by `ManagerPopup.open`. Every edit saves at once — see **감독 screen body** |
| `UI_View_ManagerPopup.tscn` + `ManagerPopup.gd` | `class_name ManagerPopup extends Control` | Lobby **감독 modal** (opened by the lobby's top-left level disc): a sheet dropping from the top edge (`ManagerPopupSheet`) holding one `ManagerTab`, floating close capsule bottom-right. It is the tab's host — see **ManagerPopup** below |
| `UI_Comp_ManagerStatCard.tscn` | — (no script) | Item scene: one 감독 능력치 card of the 6-column row (`%Icon`, `%Key`, bottom `%Adjust` strip: `%Minus` · `%Value` · `%Plus` — steppers use the compact `ManagerStatStep` ghost), one per `StaffSystem.STATS`, instanced once in `ManagerTab._ready` |
| `UI_Comp_TraitPickerView.tscn` + `.gd` | `class_name TraitPickerView extends VBoxContainer` | Trait block shared with the run setup `감독` step: head (`특성` · `보너스 점수 ±n` pill · `교체`), **equipped** trait cards. Owns a `TraitTooltip` and a `TraitSwapPopup`. `fill(equipped, owned, new_ids)`, `open_swap()`, signals `swap_requested` / `traits_applied(traits)`; static `sort_owned(owned)` |
| `UI_Comp_TraitCard.tscn` + `TraitCard.gd` | `class_name TraitCard extends Button` | One trait as a card: rarity-coloured rounded-square thumb + icon (`SkillImages.trait_icon_for`), score plate bottom-right, name. `fill(id, marked, is_new)`, `trait_id`; static `score_text` / `score_color` |
| `UI_Comp_TraitTooltip.tscn` + `TraitTooltip.gd` | `class_name TraitTooltip extends CanvasLayer` (25) | Effect tooltip beside a tapped card: name, rarity chip, `보너스 ±n`, description, optional action button. `show_for(card, id, action_text, primary)`, `hide_tip()`, signal `action_pressed(id)` |
| `UI_View_TraitSwapPopup.tscn` + `TraitSwapPopup.gd` | `class_name TraitSwapPopup extends CanvasLayer` (20) | 특성 교체 modal: top sheet, bonus gauge, `장착한 특성` grid + `보유 특성` grid (equipped = amber), tooltip with 장착 / 해제, floating close. `open(equipped, owned, new_ids)`, `request_close()`, signals `applied(traits)` / `closed` |
| `UI_Comp_ManagerPresetChips.tscn` + `.gd` | `class_name ManagerPresetChips extends HBoxContainer` | Preset **capsule** shared with the run setup `감독` step: right-aligned dark pill, one cell per preset (I, II, …), white selector sliding under the chosen one. `fill(profile, selected)`, signal `chip_pressed(idx)` |
| `UI_Comp_ManagerPresetChip.tscn` | — (no script) | Item scene: one capsule cell (flat Button 96 × 72, `ManagerPresetCell` / `…On`) |
| `ManagerUi.gd` | `class_name ManagerUi extends RefCounted` (static) | Shared pieces: read-only `add_stat_cells` (still code-built), `preset_name`, `roman`, `stat_icon` (`resources/images/ui/manager/stat_<key>.svg`), `signed`, `bonus_color`, `unlock_text` (§12.4 grammar → `manager.unlock.*` text) |

## F6 preview (standalone run)
Every scripted scene here shows dummy data when run on its own (editor "Run Current Scene") — `_ready` →
`UiPreview.is_standalone(self)` → `_fill_preview()` at the bottom of each script (`resources/UiPreview.gd`).
- `ManagerTab` / `ManagerPopup`: real profile, active preset. Skips `on_shown`'s NEW clearing in the tab preview;
  재설정 · 프레스티지 · 제거 확정 only print. **Preset taps, stat steps and trait swaps save the real profile at once** —
  don't press them in a preview. Toasts print (host-owned).
- `ManagerPresetChips`: real profile's presets, active one selected; a tap moves the selector only.
- `TraitPickerView`: hand-written equipped `[1, 3, 15]` / owned list, one NEW; 교체 opens the swap popup, applying
  refills in memory. `TraitSwapPopup`: the same lists; `applied` / `closed` only print.
- `TraitCard`: trait 2 with NEW. `TraitTooltip`: trait 2 beside a fake card, with an action button.

## Stat model
`base = type − removed × MANAGER_REMOVE_STAT_DROP` (≥ 1, removals permanent until prestige), `preset = base + alloc` (≤ `MANAGER_STAT_CAP`).
Each level-up = `MANAGER_REMOVE_PER_LEVEL` removal points; one removal = `MANAGER_SPEC_PER_REMOVAL` specialisation points (`spec_per_removal()`; the drop is `remove_stat_drop()`, both passed to `manager.tab.remove_body` / `removed_toast` as `{gain}` / `{drop}`);
`Σ alloc ≤ spec_points` per preset. Prestige at `PRESTIGE_LEVEL`: level / exp / removals reset, type
re-chosen, presets → `kind = "prestige"` (unusable until `reset_preset`), `PRESTIGE_NEW_PRESETS` normal presets (`{presets}` in `manager.tab.prestige_body`) (≤
`PRESET_MAX_COUNT`), `PRESTIGE_REWARD_*` currency. Mutators don't save — the screen calls `save_profile()`.

## ManagerPopup (lobby 감독 modal)
`LobbyScreen.open_manager()` (tap on the top-left level disc) creates one `ManagerPopup` lazily (a plain Control child
of the lobby, added after the bottom bars) and calls `open(lobby)`; the lobby fades its nav capsule out meanwhile.
```
ManagerPopup (Control, full rect, theme)
├ %DimRect (DimPanel) · %Dim (flat Button — tap = close)       both extended under the notch
├ %Sheet (Panel ManagerPopupSheet — square top, rounded bottom, shadow; drops from the top + fades in)
│ │      top offset = −notch (covers the notch band), bottom = 16 px above the close capsule (code)
│ └ %Content (top offset = notch height, code)
│   ├ Title (TitleLabel, `term.person.manager`)
│   └ %Body (y 104 .. −16, clip) ← ManagerTab, full rect, created on the first open
└ %FloatingCloseButton_Close (resources/UI_Comp_FloatingCloseButton.tscn) — bottom-right, lifted by the inset
```
- `_fit_safe_area` on every open: dim / sheet `extend_background`, `%Content.offset_top`, capsule via
  `UiHelpers.place_floating_close` (returns its top → sheet bottom). Open / close slide =
  `UiHelpers.slide_top_sheet` (the whole popup fades, the sheet drops from a quarter screen above).
- **Host services** for the tab (subset of `LobbyScreen`'s, header of `LobbyScreen.gd`): `show_toast` · `refresh_currency` ·
  `refresh_badges` · `set_tab_badge` · `open_confirm` are forwarded to the lobby. No action bar. The lobby `%Toast` (z 5)
  floats over the sheet; `ConfirmPopup`, the prestige `ManagerTypePopup` and the trait swap popup are CanvasLayers above it.
- `open` → `ManagerTab.on_shown()` every time (back on the active preset, NEW traits list, badge clear). `close()` emits
  `closed`; the lobby then shows its nav and refreshes the wallet / level disc / badges and the current tab.
- F6: opens without a lobby (toasts print).

## 감독 screen body (`ManagerTab`)
Scene-authored (`docs/ui_scene_migration.md`); every change refills the same nodes (`_rebuild`), so the
scroll position stays. Every tap target inside is a `MOUSE_FILTER_PASS` Button
(`docs/mobile_safe_area.md` §5).
```
ManagerTab (Control, theme = OutgameTheme.tres, preview 1080×1568 — ManagerPopup sets it full rect in %Body)
└ %Scroll (v-mode Never: no bar, DragScroll drags) ─ DragScroll · %Body (Margin 24 / 24 / 24 / 40)
  └ Sections (VBox, separation 28)
    ├ Header (MarginContainer, min h 168) ─ Bg (Panel · Card) + Pad (Margin 28 / 28) ─ Content (anchored):
    │   %Level (AccentLabel 34) · %PrestigeChip/%PrestigeChipText (beside it) ·
    │   ExpTrack (ProgressTrack, 0 .. −260) ─ %ExpFill · %ExpText · %Prestige (right, 230×72)
    ├ Presets (VBox 0): %ManagerPresetChips_PresetChips (capsule, right-aligned) · %ResetBox (top 16, hidden)
    │   └ ResetCard (Panel `ManagerDangerCard`, h 120): title (`NegativeLabel` 24) · body · %Reset (PrimaryButton 26)
    ├ Stats (MarginContainer) ─ Bg (Card) + Pad (28 / 0 / 28 / 28) ─ VBox 0:
    │   Head (h 84): StatsTitle · %SpecChip (right, spec mode) | %RemoveChip · %RemoveConfirm `확정` (removal mode)
    │   %StatCards (Grid 6 cols, h-sep 10) ─ 6 × UI_Comp_ManagerStatCard.tscn (~154 × 196)
    └ %TraitPickerView_Traits (UI_Comp_TraitPickerView.tscn instance)
```
Top to bottom:
1. **Header card** — `Lv n`, `프레스티지 n회` chip, EXP bar inside the level (`level_progress`; "최고 레벨" at max),
   `프레스티지` button (primary when `can_prestige` passes, otherwise a disabled ghost `Lv25 프레스티지`). No type title,
   no removal / specialisation info line.
2. **Preset capsule** (`ManagerPresetChips`) — I … X, selector on the selected preset. A prestige preset's numeral is
   red; selecting it shows the red reset card with `재설정` (`reset_preset`, saved at once).
3. **Stats card** — 6 cards in one row: icon (`ManagerUi.stat_icon`, dark tint) + name on top, adjust strip at the bottom
   (`− value +`; steppers, not sliders — the scroll would eat horizontal drags). **Steppers are shown only when the step
   is possible** (never dimmed). Two modes:
   - **Spec mode** (no removal points left): head chip `전문화 포인트 used / total`; value = the stat with specialisation
     included (amber when specialised); − / + = `alloc_step` on the selected preset (saved at once).
   - **Removal mode** (`removal_points_left > 0` — after a level-up, whatever preset is open): strips turn light green
     (`ManagerStatAdjustRemove`), head shows `제거 포인트 n` (points left after the placed ones) + `확정`. − places a
     removal on that stat (`_pending`; needs a point left and base − drop ≥ `STAT_MIN`), + takes one back; value = base
     after the placed removals (red while lowered). Nothing is saved until `확정` → danger confirm
     (`manager.tab.remove_batch_*`, one `remove_item` line per stat) → `remove_stat` per point → save → toast
     `removed_batch_toast`. Removals are profile-wide (every preset) and permanent until prestige. `_pending` is cleared
     on every `on_shown`.
4. **Traits** (`TraitPickerView`) — head pill `보너스 점수 ±n` (red pill below 0); the equipped cards only; tap = effect
   tooltip; `교체` = swap popup.

### Editing model — auto-save
- **Preset tap = use it**: `active_preset = idx` + `save_profile()` at once (haptic SELECT). A prestige preset is only
  selected (it can't be used until reset). `on_shown` returns to the active preset.
- **Spec steps** (`alloc_step`) and **trait swaps** (`traits_applied` from the popup) edit the selected preset's working
  copy, then `_store`: `validate_preset` → `store_preset` → `save_profile()`. A failing validation → red toast and the copy
  falls back to the saved preset (nothing invalid is ever stored). A trait swap shows `manager.tab.toast_saved`.
- A prestige preset is read-only: `교체` → `manager.tab.prestige_readonly` toast; steppers disabled.
- **Removal** is profile-wide and permanent: placed on the cards, committed by `확정` (see 3. above).
- **Prestige**: confirm (what resets + rewards) → `ManagerTypePopup.open(true, current_type)` (prestige
  mode, dismissible) → `ManagerProgress.prestige` → save → back on the new active preset → toast with the
  rewards → `host.refresh_currency()`.
- **NEW traits**: `on_shown` copies `profile.traits.unlocked_pending` into the screen's NEW list (kept while
  the lobby lives), clears the pending list, saves and calls `host.refresh_badges()`. NEW shows on the cards.

## Shared scenes — `ManagerPresetChips` · `TraitPickerView` (+ card · tooltip · swap popup)
Used by the lobby 감독 modal and the run setup `감독` step (`run_setup/UI_View_ManagerStepView.tscn` instances
`%ManagerPresetChips_Chips` · `%TraitPickerView_Traits`). Layout / style are the scenes; code fills texts, switches
variations by state and paints data colours. Every tap target is a `MOUSE_FILTER_PASS` Button (the hosts scroll with
`DragScroll`).
```
ManagerPresetChips (HBox, alignment end) ─ %Capsule (min = n × 96 + 16, 88 high)
  ├ Back (Panel ManagerPresetCapsule — dark pill)
  ├ %Selector (Panel ManagerPresetSelector — white pill, 96 × 72, tweened to x = 8 + i × 96)
  └ %Cells (HBox sep 0, 8 px inset) ─ n × UI_Comp_ManagerPresetChip.tscn (scene: 5 preview cells)

TraitPickerView (VBox, sep 0)
├ Head (HBox h 72): Title "특성" · %BonusPill (`TraitPickerBonusPill(Bad)`) ─ %BonusText · Spacer · %Swap (GhostButton 160 × 64, `교체`)
├ Gap 8 · %Cards (Grid 5 cols, 12 / 12) ─ TraitCard per equipped trait (scene: 3 previews) · %Empty (nothing equipped)
├ %TraitTooltip_Tip (CanvasLayer 25 — card tap, no action)
└ %TraitSwapPopup_Swap (CanvasLayer 20, hidden — `open_swap()`)

TraitCard (Button 180 × 236 min, h-expand) ─ %Thumb (148², TraitCardThumb copy, fill = rarity colour)
  ├ %Icon (white glyph, inset 24 / 20 / 24 / 28) · Score (PanelContainer TraitCardScore, bottom-right) ─ %ScoreText
  └ %New (TraitPickerNewChip, top-left) │ %Name (21, 2 lines, centred, under the thumb)

TraitTooltip (CanvasLayer 25) ─ %Root ─ %Catcher (full-rect flat Button: tap = close)
  └ %Card (PanelContainer TraitTooltipCard, 520 wide) ─ VBox: %Name · Meta (%Rarity chip · %Cost) · %Desc · %Action

TraitSwapPopup (CanvasLayer 20) ─ %Root (fades) ─ DimRect · %Dim · %Sheet (TraitSwapPopupSheet, drops from the top)
  └ %Content (top offset = notch) ─ Title `특성 교체` · %Gauge (Key · %Bonus · %Rule) · %Scroll (+ %DragScroll) ─ Body ─
      VBox: %EquippedTitle · %EquippedGrid (5 cols) · %EquippedEmpty · Gap · %OwnedTitle · %OwnedGrid (5 cols)
  · %FloatingCloseButton_Close (bottom-right) · %TraitTooltip_Tip (with 장착 / 해제)
```
- **Cards**: thumb fill = `TraitUi.rarity_color` (0 grey · 1 green · 2 blue · 3 purple · 4 amber); icon =
  `SkillImages.TRAIT_ICON` (trait id → `resources/images/skill/` file, none shared with pilot skills / mech passives);
  score plate `TraitCard.score_text` — "−n" for a `+` trait (consumes bonus points), "+n" for a `−` trait (provides),
  polarity colour lifted 30 % for the dark plate. No `보너스` word, no outgame / in-game chip, no effect text on the card.
- **Tooltip placement** (`TraitTooltip._place`, one frame after `show_for` so wrapped labels have their height): right of
  the card when its centre is on the left half of the screen, left of it otherwise; x clamped 16 px inside the screen, y =
  card top clamped between the safe top and the bottom inset. Card rects via `get_global_rect()` (all layers share the
  canvas coordinates).
- **Swap popup**: works on its own copy. Card tap → tooltip with `장착` (PrimaryButton) / `해제` (GhostButton) →
  `ManagerProgress.toggle_trait`. No count limit — bonus points are the only cap; below 0 the gauge turns red but the set
  can still be built. Close (capsule / dim): unchanged → close; changed and bonus ≥ 0 → `applied(traits)` + close;
  bonus < 0 → danger `ConfirmPopup` (layer 30) `버리고 닫기` / `계속 고르기` — an invalid set is never applied.
  Owned grid = `TraitPickerView.sort_owned` (positives first, then negatives, id order); locked traits are not listed.
- Hosts: the 감독 modal checks the prestige rule on `swap_requested` and stores on `traits_applied` (`ManagerTab`); the
  run setup step does the same (`ManagerStepView.set_traits`, saved when the preset validates).

| Piece | Variation in the scene / code | Code colour (data) |
|---|---|---|
| Capsule · selector | `ManagerPresetCapsule` · `ManagerPresetSelector` | — |
| Capsule cell | `ManagerPresetCell` ↔ `ManagerPresetCellOn` (selected) | `NEGATIVE` font (prestige preset) |
| Stat card · adjust strip | `ManagerStatCard` · `ManagerStatAdjust` ↔ `ManagerStatAdjustRemove` (removal mode, light green) | — |
| Bonus pill (picker head) | `TraitPickerBonusPill` ↔ `TraitPickerBonusPillBad` (bonus < 0); `%BonusText` Positive / Negative / Caption | — |
| Gauge (swap popup) | `TraitPickerGauge` ↔ `TraitPickerGaugeBad` (bonus < 0); `%Bonus` Positive / Negative / Caption | — |
| Card frame | `TraitCard` ↔ `TraitCardOn` (equipped, swap popup) | — |
| Card thumb · score plate · NEW | `TraitCardThumb` · `TraitCardScore` · `TraitPickerNewChip` | rarity colour · polarity colour |
| Tooltip card · rarity chip | `TraitTooltipCard` · `AccentChip` copy | rarity colour |
| Modal sheets | `ManagerPopupSheet` · `TraitSwapPopupSheet` | — |

All of these are screen variations in `OutgameTheme._add_screen_variations` (`resources/README.md`).
