# Manager (M9)

Manager growth and presets between runs. Contract: `docs/outgame_dev_plan.md` §12.

## Files
| File | Class | Role |
|---|---|---|
| `ManagerProgress.gd` | `class_name ManagerProgress extends RefCounted` (static) | Pure rules over the profile dict: levels (`manager_levels.csv`), removal / specialisation points, preset stats + validation, prestige. UI helpers: `level_progress`, `toggle_trait`, `preset_copy` / `store_preset` |
| `ManagerTab.tscn` + `.gd` | `class_name ManagerTab extends Control` | Lobby `감독` tab (header · presets · stats · traits, action bar). **Layout lives in the `.tscn`** (style = `OutgameTheme.tres` variations); built with `ManagerTab.create()` (not `.new()`) by `LobbyScreen._make_tab` |
| `ManagerStatRow.tscn` | — (no script) | Item scene: one 감독 스탯 row (`%Divider`, `%Key`, `%Parts`, `%Final`, `%Remove`, `%Minus` / `%Alloc` / `%Plus`), one per `StaffSystem.STATS`, instanced once in `ManagerTab._ready` |
| `TraitPickerView.gd` | `class_name TraitPickerView extends Control` | Trait block shared with the run setup `감독` step: bonus gauge, equipped slots, owned / locked trait rows. Draws + emits `trait_pressed(id)` only |
| `ManagerUi.gd` | `class_name ManagerUi extends RefCounted` (static) | Shared pieces: `add_preset_chips`, read-only `add_stat_cells`, `preset_name`, `signed`, `bonus_color`, `unlock_text` (§12.4 grammar → Korean) |

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
    ├ Presets (VBox 0): PresetsTitle (min h 52) · %PresetChips (slot) · %ResetBox (top 16, hidden)
    │   └ ResetCard (Panel, local red StyleBox, h 120): title · body · %Reset (PrimaryButton 26)
    ├ Stats (MarginContainer) ─ Bg (Card) + Pad (28 / 0 / 28 / 16) ─ VBox 0:
    │   Head (h 108): StatsTitle · %RemoveChip · %SpecChip (right) · %Formula │ %StatRows (6 × ManagerStatRow.tscn, h 92)
    └ %Traits (TraitPickerView node)
```
- **Code owns only data**: texts; chip pills (`_paint_chip`: `flat_style(bg, h / 2)` + text colour — data
  colours); `%ExpFill.anchor_right` = EXP ratio (min width = its height while > 0, hidden at 0); the
  `%Prestige` button's look (`PrimaryButton` 26 when `can_prestige` passes, else disabled `GhostButton` 24);
  `%Final` / `%Alloc` variation swaps (`AccentLabel` ↔ `BodyLabel` / `FaintLabel`); disabled states;
  `%ResetBox` visibility. `ManagerUi.add_preset_chips` and `TraitPickerView.build` stay code-built
  (shared with run setup) — they get the content width = tab width − `%Body` margins, and code sets
  the slot / node minimum height to the height they return.

Top to bottom:
1. **Header card** — `<type> 감독`, `Lv n`, EXP bar inside the level (`level_progress`; "최고 레벨" at
   max), `프레스티지 n회` chip, `프레스티지` button (primary when `can_prestige` passes, otherwise a
   disabled ghost `Lv25 프레스티지`).
2. **Preset chips** (`ManagerUi.add_preset_chips`, 5 per row): selected = amber frame; status line
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
