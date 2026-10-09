# mastery/ — mech mastery (M4, reworked §15 A)

Display text is l10n keys (`mastery` domain); the level label is `mastery.level` ("Lv{n}") via
`MechMastery.level_name(l)`; mech upgrade lines are `mastery.upgrade.<id>.desc` (data column of
`mech_upgrades.csv`, see `features/battle_sim/mech/README.md` "Mech upgrades").

Contract: `docs/outgame_dev_plan.md` §11 + **§15 A**. Run-scoped state, string keys only (JSON round-trips
them; numbers come back as floats, so every read goes through `int()`):

| Key | Shape |
|---|---|
| `season_state.mech_mastery` | `{"<pilot_id>": {"<mech_id>": int 0..MASTERY_MAX}}` — all 60 pilots (league 40 + INTL 20) × all mechs |
| `season_state.mastery_research` | `{"<pilot_id>": mech_id}` — my pilots' weekly research mech (absent = none) |

| File | Role |
|---|---|
| `MechMastery.gd` | `class_name MechMastery` (static). Init (rank deal), points → level / progress, level %, apply, `mech_levels_ctx`, gains, research, week close. Reads the mech table (`mechs`) and `players` / `intl_players` `mech_pref` from game.db itself — `all_mechs` rows are `{id, name_key, role}`; `mech_name(id)` = `Loc.t(name_key)`. |
| `MasteryPanel.gd` + `UI_View_MasteryPanel.tscn` | Hub manage card 「메크 연구」 + its `HubSheet` body (research picker, next mech upgrade per pilot). |
| `UI_Comp_MasteryPilotRow.tscn` · `UI_Comp_MasteryMechChip.tscn` · `UI_Comp_MasteryQuirkLine.tscn` | Item scenes of the sheet (no script): one pilot card · one own-role mech chip · one quirk line. |

All tuning numbers are `MASTERY_*` keys in `data/csv/const.csv` — none are written here.

## Rules
- **Points → level** (like trust, `MentalSystem.trust_level`): `level_for_value(v)` / `level_of(state, pid, mech)`
  = how many of `MASTERY_LV_1..5` (20 / 40 / 60 / 80 / 100) the points reached, 0..5 (`LEVEL_MAX`).
  `value_progress(v)` / `level_progress(...)` = 0..1 inside the current level (1.0 at Lv5) — the chip bar.
  The old tiers (미숙 / 보통 / 능숙 / 마스터, `MASTERY_TIER_*` / `MASTERY_BONUS_*`) are gone.
- **Initial value** (`init_run`, called by `GameManager.start_run` after ranks are applied): the pilot's
  `run_rank(pd, intl)` — my five = collection rank, named AI = stars (both are `PlayerData.rank` after
  `RunRules.apply_progress`), mobs = 1, INTL pilots (no stars) = `MASTERY_INTL_RANK` — picks the counts
  `MASTERY_RANK<r>_L3` / `_L2` / `_L1`, dealt from the front of `mech_pref(pd)` (players.csv /
  intl_players.csv `mech_pref`, best first: Lv3s, then Lv2s, then Lv1s). A dealt mech starts at its level's
  threshold (Lv1 20, Lv2 40, Lv3 60); every other mech is 0 (Lv0). Defaults: rank 1 = Lv1 ×2 · rank 2 = Lv2 ×1
  + Lv1 ×2 · rank 3 = Lv3 ×1 + Lv2 ×2 + Lv1 ×2 · rank 4 = Lv3 ×2 + Lv2 ×2 + Lv1 ×5 · rank 5 = Lv3 ×3 + Lv2 ×3 + Lv1 ×5.
  Empty `mech_pref` falls back to main mechs → own-role mechs.
- **`mech_pref`** was generated once (§15 A) by a script: `main_mechs` → the other own-role mechs → other
  roles, shuffled deterministically per pilot id, 11 ids. Designers edit the column directly afterwards.
- **Effect** (`stat_pct` / `apply_to`): while riding that mech the four stats `PCT_STAT_KEYS`
  (field_hit · field_eva · engage_hit · engage_eva — not the growth stats) × (1 + `MASTERY_PCT_<level>` %):
  Lv0 −20 · Lv1 0 · Lv2 +5 · Lv3 +10 · Lv4 +15 · Lv5 +20 (rounded, floor `PlayerData.STAT_MIN`). Applied only by
  `MatchFlow._finalize_rosters` on roster **copies** — `all_pilots` is never touched. `is_enabled(state)` is
  false outside a run → 0 %, UI hidden. Labels: `pct_text(l)` ("+10%" / "±0%" / "-20%"), `level_color(l)`
  (Lv0 `NEGATIVE`, Lv1–2 `TEXT_SUB`, Lv3–4 `POSITIVE`, Lv5 `ACCENT_TEXT`).
- **Mech upgrades** (돌파형): Lv3 / Lv4 / Lv5 on a mech unlock one step each (`MechUpgrades`,
  `features/battle_sim/mech/`). `mech_levels_ctx(state, [p_roster, e_roster])` → `match_ctx.mech_levels`
  (`{"<pilot_id>": level}` on the assigned mech, both teams; written by `MatchFlow._finalize_rosters`).
- **Gains** — all through `gain(state, pid, mech, amount)` (also the §15 D Saturday story):
  - **matches give nothing** (§15 — `MASTERY_GAIN_MATCH` / `record_match` were removed).
  - research: `settle_week` — `MASTERY_GAIN_RESEARCH` to each of my pilots' research mech.
    The same pass rolls `QUIRK_RESEARCH_CHANCE`% per pilot with a research mech →
    `QuirkSystem.gain_random` (`_research_quirk_roll`, seeded per run · week · pilot; §14 T1,
    `features/season/quirk/README.md`).
  - training tile `M`: `add_training_exp(state, pid, amount)` (called by the training board) —
    `amount × MASTERY_TRAIN_SCALE` to the research mech, or to the coach's choice if none is set.
  - Multiplier, **my pilots only**: `knowledge_mult` (`MASTERY_KNOW_BASE + MASTERY_KNOW_PER ×
    StaffSystem.effective("knowledge")`) × `FinanceSystem.mastery_mult` × trait `mastery_pct`
    (`TraitSystem.run_pct_mult`, M8). Opponent pilots gain the raw
    amount. Each gain is at least 1, capped at `MASTERY_MAX`.
- **Auto vs manual** (`StaffSystem.is_delegated(state, "knowledge")`):
  - delegated → the sheet shows `코치에게 맡기기` (`auto_assign_all`), and `settle_week` fills empty
    research slots itself before the gain. No card alert.
  - manual → the player picks per pilot; the hub card `alert`s while any pilot has none.
  - Coach rule (`auto_research_mech`, plain, not optimal): own-role mech with the highest mastery
    still below the cap (ties: lower id).

## Hub card / sheet (`MasteryPanel`)
- Card: `value` = `N / 5 지정`, `sub` = weekly research gain after multipliers (or what is missing),
  `owner` = `StaffSystem.owner_name(state, "knowledge")`.
- Sheet: owner + effective knowledge + gain multiplier, level-% legend (Lv0..Lv5), gain rule + "upgrades at
  Lv3 · 4 · 5", the auto button (delegated) or a manual hint, then one card per pilot in
  `GameEnums.ROLE_DISPLAY_ORDER`: portrait, name, current research mech, top-3 mastery line (`mech LvN`), a chip
  per own-role mech (`name / LvN · ±%`, a level bar = `%LevelBar` fill `anchor_right` = progress inside the
  level, colour = level) and **`%NextUpgrade`** — the next locked mech upgrade of the research mech (or the
  coach's pick): `다음 강화 Lv4 · <mech>: <step text>` (`MechUpgrades.next_step` / `step_text`), or "all
  unlocked". Tap a chip = set research, tap the selected chip = clear.
- **F6 preview** — run `UI_View_MasteryPanel.tscn` alone and it fills dummy data (`resources/UiPreview.gd`):
  in-memory run, `auto_assign_all` + four `settle_week`s, bound without a sheet.
  A tap refills the same body in place (`_fill`); rows and chips are reused (`_ensure`), so the tapped
  chip is never freed while it is emitting.
- Quirks (§14 T1, only while `QuirkSystem.is_enabled`): a legend line (research quirk chance + grade
  odds from `QuirkSystem.grade_odds`) above the cards, and under each card's mech chips a
  `기벽 n / slots` block — one line per quirk (grade pill · name in grade colour · effect line from
  `QuirkSystem.effect_text`). The card grows with its `%Content` (height = content + the scene's pads).
- **Sheet scene** (`UI_View_MasteryPanel.tscn`, root `VBoxContainer` top-wide over the body; theme `OutgameTheme.tres`).
  The sheet's scroll height follows the root's height (`resized`); `Tail` is the bottom gap.
  ```
  MasteryPanel (VBox)
  ├ %Empty                      no run (hidden)
  └ %Main (VBox)
    ├ HeadRow  %Head (owner · knowledge) | %Gain
    ├ %Legend · %Rules · %Auto (Ghost) · %AutoGap · %NoCoach · %QuirkOdds
    ├ %Pilots (MasteryPilotRow, sep 16)
    └ Tail
  MasteryPilotRow (Panel · Card) → %Content (VBox, inset 18)
    ├ Top (244)  %Portrait (round portrait added by code) · %Name · %Research · %PositionBadge_Position (PositionBadge) · %TopMechs · %Chips (MasteryMechChip) · %NextUpgrade
    └ %Quirks    Divider · Head (%Count · %Max) · %QuirkEmpty · %Lines (MasteryQuirkLine) · Tail
  MasteryMechChip (Button) → LevelTrack (grey ColorRect) → %LevelBar (fill)
  ```
  Code owns: texts, delegated / quirk switching, research colour, chip variation (`PrimaryButton` = research
  mech, else `GhostButton`), level bar fill / colour, grade colours, the round portrait
  (`OutgameTheme.add_round_portrait` into `%Portrait`), and the pilot card height.

## Where mastery shows outside this folder
- Ban/pick (`features/match_flow/ban_pick/README.md` "Mech mastery"): slot tags (`Lv3 +10%`), grid badges
  (Lv3+), sheet line, `MechDetailPanel` mastery block + **mech upgrade block**, AI ban/pick scoring and enemy
  assignment (points), analysis markers.
- `OpponentIntel` (match prep) top-mastery lines (`mech LvN`), `SeasonPilotDetail` research line (level name /
  colour), `WeekProgressView._mastery_text` (day card: `숙련 +n · <mech> LvN`), `QuirkSystem` condition
  `tier:<n>` = mastery **level** ≥ n.
- BattleSim: only `match_ctx.mech_levels` (mech upgrades — passive params, "+" mech cards).
