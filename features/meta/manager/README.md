# Manager (M9)

Manager growth and presets between runs. Contract: `docs/outgame_dev_plan.md` §12.

## Files
| File | Class | Role |
|---|---|---|
| `ManagerProgress.gd` | `class_name ManagerProgress extends RefCounted` (static) | Pure rules over the profile dict: levels (`manager_levels.csv`), removal / specialisation points, preset stats + validation, prestige. UI helpers: `level_progress`, `toggle_trait`, `preset_copy` / `store_preset` |
| `ManagerTab.tscn` + `.gd` | `class_name ManagerTab extends Control` | Lobby `감독` tab (header · presets · stats · traits, action bar). **Layout lives in the `.tscn`** (style = `OutgameTheme.tres` variations); built with `ManagerTab.create()` (not `.new()`) by `LobbyScreen._make_tab` |
| `ManagerStatRow.tscn` | — (no script) | Item scene: one 감독 스탯 row (`%Divider`, `%Key`, `%Parts`, `%Final`, `%Remove`, `%Minus` / `%Alloc` / `%Plus`), one per `StaffSystem.STATS`, instanced once in `ManagerTab._ready` |
| `TraitPickerView.tscn` + `.gd` | `class_name TraitPickerView extends VBoxContainer` | Trait block shared with the run setup `감독` step: bonus gauge, equipped slots, owned / locked trait rows. `fill(equipped, owned, new_ids)`; emits `trait_pressed(id)` only (the host applies the rule). Placed as a scene instance (`%Traits`) in both hosts; `create()` for code |
| `TraitPickerSlot.tscn` | — (no script) | Item scene: one equip slot (`%Frame` button: `%Strip` · `%Name` · `%Cost`; `%Empty` "빈 칸"), equal widths in `%Slots` |
| `TraitPickerRow.tscn` | — (no script) | Item scene: one trait row (Button): `%Badge`/`%Sign`, Head HBox `%Name` + chips (`%Rarity`/`%RarityText`, `%LayerText`, `%New`), `%Desc`, `%Unlock` (locked), `%Cost`, `%Equipped` |
| `ManagerPresetChips.tscn` + `.gd` | `class_name ManagerPresetChips extends GridContainer` | Preset chip grid shared with the run setup `감독` step (5 columns, gap 12, equal widths): `fill(profile, selected)`, signal `chip_pressed(idx)`. Placed as a scene instance in both hosts |
| `ManagerPresetChip.tscn` | — (no script) | Item scene: one preset chip (Button, h 104): `%Name`, `%Status` |
| `ManagerUi.gd` | `class_name ManagerUi extends RefCounted` (static) | Shared pieces: read-only `add_stat_cells` (still code-built), `preset_name`, `signed`, `bonus_color`, `unlock_text` (§12.4 grammar → Korean) |

## F6 preview (standalone run)
`ManagerTab` shows dummy data when run on its own (editor "Run Current Scene") — `_ready` →
`UiPreview.is_standalone(self)` → `_fill_preview()` at the bottom of each script
(`resources/UiPreview.gd`). Nothing is saved: buttons that would save the profile are re-wired
to only print (`UiPreview.mute`).
- `ManagerTab`: real profile, active preset. Skips `on_shown` (it clears the NEW list and saves); 제거 · 재설정 ·
  프레스티지 only print. No action bar / toasts (host-owned).
- `ManagerPresetChips`: real profile's presets, active one selected; a tap moves the selection only.
- `TraitPickerView`: hand-written equipped `[1, 3, 15]` / owned list, one NEW; a tap toggles in memory.
- Item scenes without a script (`ManagerPresetChip`, `TraitPickerSlot`, `TraitPickerRow`) show their sample text.

## Stat model
`base = type − removed` (≥ 1, removals permanent until prestige), `preset = base + alloc` (≤ `MANAGER_STAT_CAP`).
Each level-up = `MANAGER_REMOVE_PER_LEVEL` removal points; one removal = one specialisation point;
`Σ alloc ≤ Σ removed` per preset. Prestige at `PRESTIGE_LEVEL`: level / exp / removals reset, type
re-chosen, presets → `kind = "prestige"` (unusable until `reset_preset`), +1 normal preset (≤
`PRESET_MAX_COUNT`), `PRESTIGE_REWARD_*` currency. Mutators don't save — the screen calls `save_profile()`.

## Lobby `감독` tab (`ManagerTab`)
Scene-authored (`docs/ui_scene_migration.md`); every change refills the same nodes (`_rebuild`), so the
scroll position stays. Every tap target inside is a `MOUSE_FILTER_PASS` Button
(`docs/mobile_safe_area.md` §5).
```
ManagerTab (Control, theme = OutgameTheme.tres, preview 1080×1568 — host sets position / size)
└ %Scroll (v-mode Never: no bar, DragScroll drags) ─ DragScroll · %Body (Margin 24 / 24 / 24 / 40)
  └ Sections (VBox, separation 28)
    ├ Header (MarginContainer, min h 236) ─ Bg (Panel · Card) + Pad (Margin 28 / 28) ─ Content (anchored):
    │   %TypeTitle (TitleLabel) · %PrestigeChip/%PrestigeChipText (right) · %Level (AccentLabel 34) ·
    │   ExpTrack (ProgressTrack, 150 .. −250) ─ %ExpFill · %ExpText · %Prestige (right, 230×72) · %Info (FaintLabel 20)
    ├ Presets (VBox 0): PresetsTitle (min h 52) · %PresetChips (ManagerPresetChips.tscn) · %ResetBox (top 16, hidden)
    │   └ ResetCard (Panel `ManagerDangerCard`, h 120): title (`NegativeLabel` 24) · body · %Reset (PrimaryButton 26)
    ├ Stats (MarginContainer) ─ Bg (Card) + Pad (28 / 0 / 28 / 16) ─ VBox 0:
    │   Head (h 108): StatsTitle · %RemoveChip · %SpecChip (right) · %Formula │ %StatRows (6 × ManagerStatRow.tscn, h 92)
    └ %Traits (TraitPickerView.tscn instance)
```
- **Code owns only data**: texts; chip pills (`_paint_chip`: `flat_style(bg, h / 2)` + text colour — data
  colours); `%ExpFill.anchor_right` = EXP ratio (min width = its height while > 0, hidden at 0); the
  `%Prestige` button's look (`PrimaryButton` 26 when `can_prestige` passes, else disabled `GhostButton` 24);
  `%Final` / `%Alloc` variation swaps (`AccentLabel` ↔ `BodyLabel` / `FaintLabel`); disabled states;
  `%ResetBox` visibility. The shared scenes size themselves: `%PresetChips.fill(profile, idx)` and
  `%Traits.fill(...)` on every `_rebuild`; their signals are connected once in `_ready`.

Top to bottom:
1. **Header card** — `<type> 감독`, `Lv n`, EXP bar inside the level (`level_progress`; "최고 레벨" at
   max), `프레스티지 n회` chip, `프레스티지` button (primary when `can_prestige` passes, otherwise a
   disabled ghost `Lv25 프레스티지`).
2. **Preset chips** (`ManagerPresetChips`, 5 per row): selected = amber frame; status line
   `● 사용 중` (active) / `재설정 필요` (prestige kind, red) / `특성 n`. A prestige preset shows a red
   card with `재설정` (`reset_preset`, saved at once) and is read-only until then.
3. **Stats card** — chips `제거 포인트 n` · `전문화 포인트 used / total`; per stat: label, breakdown
   `유형 n · 제거 −n · 전문화 +n`, final value (amber when specialised), `제거` (disabled when
   `can_remove` fails), `− n +` steppers (`alloc_step`; steppers, not sliders — the scroll would eat
   horizontal drags, same as finance).
4. **Traits** (`TraitPickerView`) — header `장착 n / TRAIT_SLOTS`; bonus gauge (`보너스 점수`, provided /
   consumed split; red card + "0 미만이면 저장 · 사용할 수 없습니다" when < 0); slot row (tap = unequip);
   `보유 특성` rows (positives first, tap = equip / unequip; polarity badge, rarity chip
   `TraitSystem.rarity_name` on `TraitUi.rarity_color`, layer chip, `NEW` chip, `보너스 ±n`, `장착 중`); `잠긴 특성` rows greyed
   with `해금 조건 · <ManagerUi.unlock_text>`.

### Editing model
- The selected preset is edited on a **draft copy**. Alloc steps and trait taps only touch the draft
  (`_dirty`). Over-budget trait sets are allowed on the draft (red gauge + toast) but never saved.
- Bar `bar_specs()`: `[이 프리셋 사용 / 저장 후 사용 / 사용 중 (ghost, 1) | 저장 / 저장됨 (primary, 1.4)]`.
  Both run `ManagerProgress.validate_preset`; a failure → `host.show_toast(..., true)` and nothing is
  stored. Success → `store_preset` (+ `active_preset` for use) → `ProfileManager.save_profile()`.
- Switching chips with unsaved edits → `host.open_confirm` ("버리고 이동").
- **Removal** is profile-wide and permanent: `host.open_confirm` (danger) → `remove_stat` → save at once.
- **Prestige**: confirm (what resets + rewards) → `ManagerTypePopup.open(true, current_type)` (prestige
  mode, dismissible) → `ManagerProgress.prestige` → save → draft = new active preset → toast with the
  rewards → `host.refresh_currency()`. Unsaved draft edits are dropped (the confirm says so).
- **NEW traits**: `on_shown` copies `profile.traits.unlocked_pending` into the tab's NEW list (kept while
  the lobby lives), clears the pending list, saves and calls `host.refresh_badges()`.

## Shared scenes — `ManagerPresetChips` · `TraitPickerView`
Both used by the lobby `감독` tab and the run setup `감독` step (`run_setup/ManagerStepView.tscn`
instances them as `%Chips` · `%Traits`). Layout / style are the scenes; code fills texts, switches
variations by state and paints data colours. Every tap target is a `MOUSE_FILTER_PASS` Button (the hosts
scroll with `DragScroll`).
```
ManagerPresetChips (GridContainer, 5 cols, h/v sep 12) ─ n × ManagerPresetChip.tscn (Button, min h 104, h-expand)
  └ %Name (y 14..50, centred) · %Status (y 56..86, font 20)

TraitPickerView (VBox, sep 0)
├ Head (h 44): Title "특성" (BodyLabel 30, left half) · %Count (right half, 24)
├ Gap 8 · %Gauge (Panel, h 104): Key · %Bonus (40) · %Note · %Rule (right-aligned, x 260 .. −24)
├ Gap 16 · %Slots (HBox, sep 12, h 112) ─ max(slot_count, equipped) × TraitPickerSlot.tscn
├ Gap 24 · OwnedHead (h 44) ─ %OwnedTitle · %OwnedRows (VBox, sep 10) ─ TraitPickerRow.tscn (h 112)
└ %Locked (VBox, hidden when none): Gap 24 · LockedHead ─ %LockedTitle · %LockedRows (sep 10) ─ rows h 140
```
| Piece | Variation in the scene / code | Code colour (data) |
|---|---|---|
| Preset chip frame | `ManagerPresetChip` ↔ `ManagerPresetChipOn` (selected) | — |
| Chip name / status | `SubLabel` ↔ `BodyLabel`; `FaintLabel` / `AccentLabel` (● 사용 중) / `NegativeLabel` (재설정 필요) | — |
| Gauge | `TraitPickerGauge` ↔ `TraitPickerGaugeBad` (bonus < 0); `%Bonus` Positive / Negative / Caption | — |
| Slot frame · empty | `TraitPickerSlot` ↔ `TraitPickerSlotOver` (past `slot_count`) · `TraitPickerSlotEmpty` | `%Strip` polarity |
| Row frame | `TraitPickerView.ROW_ON` / `ROW_OWNED` / `ROW_LOCKED` = `TraitPickerRowOn` / `TraitPickerRow` / `TraitPickerRowLocked` | — |
| Row badge · rarity chip | `AccentChip` shape (pill) | polarity colour (grey locked) · `TraitUi.rarity_color` |
| Layer chip · NEW · 장착 중 | `TraitPickerLayerChip` · `TraitPickerNewChip` · `TraitPickerEquippedChip` (`OnFillLabel` / `CaptionLabel` 18) | — |

All of these are screen variations in `OutgameTheme._add_screen_variations` (`resources/README.md`)
and reproduce the old code-built look; the only render difference is that chip / slot cells now
snap to whole pixels (old widths like 196.8).
