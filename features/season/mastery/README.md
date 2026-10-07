# mastery/ — mech mastery (M4)

Display text is l10n keys (`mastery` domain); `TIER_NAMES` holds keys — `tier_name(t)` translates.

Contract: `docs/outgame_dev_plan.md` §11. Run-scoped state, string keys only (JSON round-trips them;
numbers come back as floats, so every read goes through `int()`):

| Key | Shape |
|---|---|
| `season_state.mech_mastery` | `{"<pilot_id>": {"<mech_id>": int 0..MASTERY_MAX}}` — all 60 pilots (league 40 + INTL 20) × all mechs |
| `season_state.mastery_research` | `{"<pilot_id>": mech_id}` — my pilots' weekly research mech (absent = none) |

| File | Role |
|---|---|
| `MechMastery.gd` | `class_name MechMastery` (static). Init, read, tiers, bonus, gains, research, week close. Reads the mech table (`mechs`) from game.db itself — `all_mechs` rows are `{id, name_key, role}`; `mech_name(id)` = `Loc.t(name_key)`. |
| `MasteryPanel.gd` + `UI_View_MasteryPanel.tscn` | Hub manage card 「메크 연구」 + its `HubSheet` body (research picker). |
| `UI_Comp_MasteryPilotRow.tscn` · `UI_Comp_MasteryMechChip.tscn` · `UI_Comp_MasteryQuirkLine.tscn` | Item scenes of the sheet (no script): one pilot card · one own-role mech chip · one quirk line. |

All tuning numbers are `MASTERY_*` keys in `data/csv/const.csv` — none are written here.

## Rules
- **Initial value** (`init_run`, called by `GameManager.start_run`): `players.main_mechs` /
  `intl_players.main_mechs` → `MASTERY_INIT_MAIN`; other mechs of the pilot's own role class →
  `MASTERY_INIT_ROLE`; everything else → `MASTERY_INIT_OTHER`. Named pilots have 2 mains, mobs 1,
  spread across each role's mechs so no single ban hurts every team.
- **Tier** (`tier_of`): 0 미숙 / 1 보통 / 2 능숙 / 3 마스터 at thresholds `MASTERY_TIER_1..3`.
- **Effect** (`stat_bonus` / `apply_to`): flat `MASTERY_BONUS_<tier>` added to **each** of the six
  pilot stats while riding that mech (미숙 is negative; floor `PlayerData.STAT_MIN`). Applied only by
  `MatchFlow._finalize_rosters` on roster **copies** — `all_pilots` is never touched, BattleSim never
  reads mastery. `is_enabled(state)` is false outside a run → bonus 0, UI hidden.
- **Gains** — all through `gain(state, pid, mech, amount)`:
  - match: `record_match(state, pending_match)` — `MASTERY_GAIN_MATCH` for every pilot in
    `pending_match.assigned_mechs` (both teams of **my** match; AI-vs-AI matches give nothing).
    Guarded by `pending_match.mastery_recorded`.
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
    still below the master threshold (else the highest below the cap).

## Hub card / sheet (`MasteryPanel`)
- Card: `value` = `N / 5 지정`, `sub` = weekly research gain after multipliers (or what is missing),
  `owner` = `StaffSystem.owner_name(state, "knowledge")`.
- Sheet: owner + effective knowledge + gain multiplier, tier-bonus legend, gain amounts, the auto
  button (delegated) or a manual hint, then one card per pilot in `GameEnums.ROLE_DISPLAY_ORDER`:
  portrait, name, current research mech, top-3 mastery line, and a chip per own-role mech
  (`name / tier value`, tier-coloured bar). Tap a chip = set research, tap the selected chip = clear.
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
    ├ Top (208)  %Portrait (round portrait added by code) · %Name · %Research · %PositionBadge_Position (PositionBadge) · %TopMechs · %Chips (MasteryMechChip)
    └ %Quirks    Divider · Head (%Count · %Max) · %QuirkEmpty · %Lines (MasteryQuirkLine) · Tail
  ```
  Code owns: texts, delegated / quirk switching, research colour, chip variation (`PrimaryButton` = research
  mech, else `GhostButton`), tier bar / grade colours, the round portrait (`OutgameTheme.add_round_portrait`
  into `%Portrait`), and the pilot card height.

## Where mastery shows outside this folder
Ban/pick (`features/match_flow/ban_pick/README.md` "Mech mastery"): slot tags, grid tags, sheet line,
`MechDetailPanel` block, AI ban/pick scoring and enemy assignment, analysis markers.
