# mastery/ — mech mastery (M4, reworked §15 A)

Display text is l10n keys (`mastery` domain; the mech-lab body's own lines are `research_mech.body.*`); the level label is `mastery.level` ("Lv{n}") via
`MechMastery.level_name(l)`; mech upgrade lines are `mastery.upgrade.<id>.desc` (data column of
`mech_upgrades.csv`, see `features/battle_sim/mech/README.md` "Mech upgrades").

Contract: `docs/outgame_dev_plan.md` §11 + **§15 A**. Run-scoped state, string keys only (JSON round-trips
them; numbers come back as floats, so every read goes through `int()`):

| Key | Shape |
|---|---|
| `season_state.mech_mastery` | `{"<pilot_id>": {"<mech_id>": int 0..MASTERY_MAX}}` — all 60 pilots (league 40 + INTL 20) × all mechs |

The old per-pilot weekly research mech (`season_state.mastery_research`) is **gone** (§16): mastery is
trained by the **mech lab** (`features/season/facility/research/MechResearch.gd`). Old saves drop the key
on load (`SaveSystem._deserialize_season_state` no longer copies it).

| File | Role |
|---|---|
| `MechMastery.gd` | `class_name MechMastery` (static). Init (rank deal), points → level / progress, level %, apply, `mech_levels_ctx`, gains (`gain` / `gain_preview` / `gain_mult`), `growth_mech`. Reads the mech table (`mechs`) and `players` / `intl_players` `mech_pref` from game.db itself — `all_mechs` rows are `{id, name_key, role}`; `mech_name(id)` = `Loc.t(name_key)`. |
| `MechLabBody.gd` + `UI_View_MechLabBody.tscn` | 메크 연구소 facility-sheet body (`MechResearch.make_body`) — read-only mastery overview of my pilots against the lab's research mech. |
| `UI_Comp_MasteryPilotRow.tscn` · `UI_Comp_MasteryMechChip.tscn` · `UI_Comp_MasteryQuirkLine.tscn` | Item scenes of the body (no script): one pilot card · one mech chip (read-only, `mouse_filter` ignore) · one quirk line. |

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
- **Gains** — all through `gain(state, pid, mech, amount)`:
  - **matches give nothing** (§15 — `MASTERY_GAIN_MATCH` / `record_match` were removed).
  - **mech lab** (§16): a completed `mech_lab` research on a target mech gives every one of my five
    pilots `MASTERY_GAIN_LAB` × row `p1` % (empty = 100) on that mech, then rolls the research quirk —
    `MechResearch.on_complete` (see the facility README "MechResearch").
  - Saturday story `mastery:` clause (§15 D, `FocusTraining.add_story_mastery`): the pilot's Saturday
    mech, else the lab's research mech (`MechResearch.lab_mech`), else `growth_mech`.
  - Multiplier, **my pilots only**: `knowledge_mult` (`MASTERY_KNOW_BASE + MASTERY_KNOW_PER ×
    StaffSystem.effective("knowledge")` — §16: the knowledge value of the mech-lab occupant) ×
    `FinanceSystem.mastery_mult` × trait `mastery_pct` (`TraitSystem.run_pct_mult`, M8). Opponent pilots
    gain the raw amount. Each gain is at least 1, capped at `MASTERY_MAX`.
  - Removed with the per-pilot research (§16): `mastery_research`, `research_mech` / `set_research`,
    `auto_research_mech` / `auto_assign_all` / `missing_research_count`, `settle_week` (+ its quirk roll →
    `MechResearch.quirk_roll`), `add_training_exp` (training `M` tiles are gone), consts
    `MASTERY_GAIN_RESEARCH` · `MASTERY_TRAIN_SCALE`, the 메크 연구 hub card (`MasteryPanel`).
- `growth_mech(state, pd)`: own-role mech with the highest mastery still below the cap (ties: lower
  id), -1 if none — fallback mech (story clause, lab body when the lab is idle).

## Mech-lab body (`MechLabBody`)
- Built by `MechResearch.make_body` → `MechLabBody.create(state)`; fills itself when it enters the tree
  (`_ready` → `refresh()`), `refresh()` refills in place (rows / chips / quirk lines reused by `_ensure`).
  Read-only: choosing the research and its target mech is the facility sheet's research list (agent B).
- Head: lab occupant · effective knowledge | gain multiplier; `%Target` = `연구 대상: <mech> · 완료 시 선수
  전원 +n` (after multipliers; `FaintLabel` "no mech under research" when the lab is idle); level-% legend;
  static rules line; quirk odds (research chance + grade odds, only while `QuirkSystem.is_enabled`).
- One card per pilot (`GameEnums.ROLE_DISPLAY_ORDER`): portrait, name, position badge, `%Research` =
  `<lab mech> LvN · +n` (or `· 최대` at the cap, or "no target"), top-3 mastery, chips (the lab mech first
  as `PrimaryButton`, then own-role mechs as `GhostButton`, 3 at most; level bar = progress inside the
  level, colour = level), `%NextUpgrade` = next locked mech upgrade of the lab mech (or `growth_mech`),
  then the quirk block (`기벽 n / slots`, one line per quirk).
- **F6 preview** — run `UI_View_MechLabBody.tscn` alone: in-memory run (`UiPreview.ensure_run`), the first
  available mech-lab row + first target completed once (`on_complete`) and selected, then filled.
- **Scene** (`UI_View_MechLabBody.tscn`, root `VBoxContainer` top-wide; theme `OutgameTheme.tres`):
  ```
  MechLabBody (VBox)
  ├ %Empty                      no run (hidden)
  └ %Main (VBox)
    ├ HeadRow  %Head (occupant · knowledge) | %Gain
    ├ %Target · %Legend · Rules (static tx_ key) · %QuirkOdds
    ├ %Pilots (MasteryPilotRow, sep 16 — the scene sample is reused)
    └ Tail
  MasteryPilotRow (Panel · Card) → %Content (VBox, inset 18)
    ├ Top (244)  %Portrait (round portrait added by code) · %Name · %Research · %PositionBadge_Position · %TopMechs · %Chips (MasteryMechChip) · %NextUpgrade
    └ %Quirks    Divider · Head (%Count · %Max) · %QuirkEmpty · %Lines (MasteryQuirkLine) · Tail
  MasteryMechChip (Button, read-only) → LevelTrack (grey ColorRect) → %LevelBar (fill)
  ```
  Code owns: texts, target / research colours, chip variation, level bar fill / colour, grade colours,
  the round portrait (`OutgameTheme.add_round_portrait` into `%Portrait`), and the pilot card height.

## Where mastery shows outside this folder
- Ban/pick (`features/match_flow/ban_pick/README.md` "Mech mastery"): slot tags (`Lv3 +10%`), grid badges
  (Lv3+), sheet line, `MechDetailPanel` mastery block + **mech upgrade block**, AI ban/pick scoring and enemy
  assignment (points), analysis markers.
- `OpponentIntel` (match prep) top-mastery lines (`mech LvN`), `SeasonPilotDetail` research line (the lab's
  research mech, `MechResearch.lab_mech` — level name / colour), `WeekProgressView._mastery_text` (day card
  `숙련 +n`, normally empty now that training has no mastery tiles), `QuirkSystem` condition
  `tier:<n>` = mastery **level** ≥ n.
- BattleSim: only `match_ctx.mech_levels` (mech upgrades — passive params, "+" mech cards).
