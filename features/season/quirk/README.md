# quirk/ — quirks (기벽, §14 T1)

Contract: `docs/outgame_dev_plan.md` §14 (decisions 14.0, interfaces 14.1). Run-only **positive**
pilot passives — flat stat bonuses only. `MatchFlow._finalize_rosters` adds them to roster
**copies** (`QuirkSystem.apply_to`, after `PilotMods` and mastery); BattleSim never reads quirks.

| File | Role |
|---|---|
| `QuirkSystem.gd` | `class_name QuirkSystem` (static). State, gain / reroll / slot, condition check, stat bonus, `apply_to`, shared text helpers (grade name / colour, effect line). Reads table `quirks` from game.db itself — rows hold l10n keys `name_key` / `desc_key` (`quirk.{id}.name/desc`); display via `name_of(id)` / `desc_of(id)`. State keeps quirk ids only. |

All tuning numbers are `QUIRK_*` keys in `data/csv/const.csv` — none are written here.
Display text is l10n keys (`quirk` domain: `quirk.cond.*`, `quirk.effect.cond`). Grade names come from
`GameEnums.rarity_label` via `GRADE_TIERS` (일반 · 희귀 · 영웅 = tiers 0 · 2 · 3).

## State
`season_state.quirks = {"<pilot_id>": {"slots": int, "ids": [quirk_id]}}` — **my five pilots only**
(`init_run`, called by `GameManager.start_run`: 0 quirks, `QUIRK_SLOTS_START` slots). String keys;
the save round-trips it through JSON, so every read goes through `int()` (`quirks_of` / `slots_of`).
`is_enabled(state)` is false outside a run → no bonus, every quirk UI hidden.

## Rules
- **Slots**: start `QUIRK_SLOTS_START`, `add_slot` adds `QUIRK_SLOT_GAIN` (`slot_gain()`) up to `QUIRK_SLOTS_MAX`; the slot-op text `training.quirk_op.slot` reads the same const as `{quirk_slot_gain}`.
- **Gain** (`gain_random`): rolls one quirk into an empty slot ("forced equip"). No empty slot →
  `"full"`, nothing changes (reroll to replace). A pilot never holds the same quirk twice.
- **Reroll** (`reroll`): every equipped quirk is redrawn; each slot avoids the quirk it replaces and
  the ones already drawn, so every slot changes and there are still no duplicates. Can go down a
  grade — that is the risk of rerolling.
- **Roll**: grade first, weight per grade `QUIRK_GRADE_W_<g>` + `QUIRK_KNOW_W_<g>` × effective
  knowledge (`StaffSystem.effective(state, "knowledge")`, grade 0 has no knowledge part), so a
  better knowledge stat shifts odds to 희귀 / 영웅 (`grade_odds` for display). Then a quirk of that
  grade by its row `weight`. A grade with nothing left to draw drops out.
- **RNG**: seeded from `run_seed` · phase · phase week · `week_day` · pilot · purpose · the pilot's
  current quirks and slots — a reload replays the same result; two rolls in a row still differ.
- **Bonus** (`stat_bonus(state, pd)` for `pd.assigned_mech`, `stat_bonus_with(state, pd, mech_id)`
  for previews, `bonus_total` = sum of the six): every quirk's `stats`, plus its `cond_stats` when
  its `cond` holds for that mech. Floor `PlayerData.STAT_MIN` in `apply_to`.

## Sources
| Source | Where | What |
|---|---|---|
| Training tiles with `Q` cells | `TrainingBoard.apply_day_training` (see `features/season/training/README.md` "Quirk tiles") | `quirk:gain` / `quirk:reroll` / `quirk:slot` on the pilot of each `Q` cell, on that cell's day |
| Mech research | `MechMastery.settle_week` | each of my pilots with a research mech: `QUIRK_RESEARCH_CHANCE`% → `gain_random` (seeded per run · week · pilot) |

## Table `data/csv/quirks.csv` (game.db `quirks`)
| Column | Meaning |
|---|---|
| `id` | int PK |
| `name_key` | l10n key `quirk.{id}.name` |
| `grade` | 0 일반 / 1 희귀 / 2 영웅 (6 each) |
| `stats` | Unconditional bonus, `stat:n` joined by `\|` — keys from `PlayerData.STAT_KEYS` (unknown keys dropped) |
| `cond` | Condition for `cond_stats` (grammar below), empty = none |
| `cond_stats` | Extra bonus while `cond` holds, same grammar as `stats` |
| `weight` | Draw weight inside its grade (0 = never drawn) |
| `desc_key` | l10n key `quirk.{id}.desc` — flavour line. The effect text on screen is generated from the columns (`effect_text`), never from `desc` |

Values are placeholders sized against mastery (`MASTERY_BONUS_*` adds to all six stats): 일반 ≈ one
stat +3, 희귀 ≈ two stats totalling +6, 영웅 ≈ +3 always and +8 more under its condition.

### `cond` grammar
Clauses joined by `&` (all must hold). Evaluated against the mech the pilot rides; with no mech
(-1) a condition never holds. An unknown clause never holds.

| Clause | Holds when |
|---|---|
| `main` | the mech is one of the pilot's main mechs (`PlayerData.main_mechs`) |
| `own_role` | the mech's role class (`mechs.role`) equals the pilot's role |
| `mech_role:<n>` | the mech's role class is `n` (`GameEnums.Role`: 0 탱커 · 1 격투 · 2 암살 · 3 서폿 · 4 원딜) |
| `tier:<n>` | the pilot's mastery tier with that mech is ≥ `n` (`MechMastery.tier_of`, 0..3) |

## Where quirks show
| Screen | What |
|---|---|
| `메크 연구` sheet (`features/season/mastery/MasteryPanel.gd`) | grade odds + research chance line; per pilot card a `기벽 n / slots` block, one line per quirk (grade pill · name in grade colour · effect) |
| Ban/pick (`features/match_flow/ban_pick/`) | my portraits: `기벽 n` badge (highest grade colour); my mech slots: `기벽 +N` tag (total with that mech); bottom sheet rider line `· 기벽 +N`; `MechDetailPanel` quirk block for the tapped seat's pilot (unmet conditions dimmed) |
| Week progress day rows | `apply_day_training` row key `quirk` — drawn by `features/season/week/` (T3+T4) |
| Collection detail | **not shown** — quirks are run-only (§14.0) |
