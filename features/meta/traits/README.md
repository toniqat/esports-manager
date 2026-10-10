# Traits (M8)

Manager traits — equipped per preset, frozen into the run at run start, scored as bonus points.
Contract: `docs/outgame_dev_plan.md` §12 (effect keys §12.3, unlock grammar §12.4).

표시 텍스트는 l10n key (`trait` 도메인 — data `trait.{id}.name/desc` + `trait.equip.*` for `validate_equip`).
`rarity_name(r)` delegates to `GameEnums.rarity_label` (the `RARITY_NAMES` table is gone).

## Files
| File | Class | Role |
|---|---|---|
| `TraitUi.gd` | `class_name TraitUi extends RefCounted` (static) | Display helpers: `rarity_color(rarity)` (0 grey · 1 teal · 2 blue · 3 purple · 4 amber, all `OutgameTheme`) and `add_rarity_chip(parent, rarity, pos, sz, font)`. **Every screen that colours a trait by rarity uses it** — run result, hub staff sheet, `TraitPickerView`, shop (`ShopPopup.rarity_color` delegates) |
| `TraitSystem.gd` | `class_name TraitSystem extends RefCounted` (static) | `traits.csv` cache (rows hold l10n keys `name_key` / `desc_key` — `trait.{id}.name/desc`; display only through `name_of(id)` / `desc_of(id)`, which fills `{p1}` / `{p2}` via `Loc.t` params), bonus points, `validate_equip`, run-time reads (`run_mod` / `run_pct_mult` / `ingame_traits`), `evaluate_unlocks` / `unlock_met` / `longest_win_streak` / `max_outings` |

## Unlock conditions (`traits.unlock`, `evaluate_unlocks(state, result, profile)`)
Judged once at settlement by `RunResult.build_result` (pure — granting is
`ProfileManager.apply_run_result`). Traits already in `profile.traits.owned` and rows with an empty
`unlock` are skipped. `result` is the settlement dictionary, `state` the run's `season_state`.

| Condition | Met when |
|---|---|
| `clear` | `result.outcome == "clear"` |
| `wins:N` | `result.wins ≥ N` |
| `titles:N` | `result.titles ≥ N` |
| `phase:N` | `result.phases_cleared ≥ N` |
| `win_streak:N` | longest run of consecutive `won` entries in `run_stats.matches` ≥ N |
| `outings:N` | max `MentalSystem.outings` among my pilots ≥ N |
| `mvp:N` | Σ `result.mvp` (my pilots' match MVPs this run) ≥ N |
| `finance_manual_profit:N` | `finance.manual_profit_weeks` ≥ N (surplus weeks while the manager ran finance — counted by `FinanceSystem.settle_week`) |
| `true_ending` | `result.true_endings` non-empty |
| `runs:N` | `profile.runs.size() + 1 ≥ N` (this run counts; an empty profile = 1) |
| `team:T` | `result.team_id == T` and `phases_cleared ≥ 1` |
| `bonus:N` | `result.bonus_points ≥ N` and `phases_cleared ≥ 1` |

Unknown condition → `push_warning`, not unlocked. Test runs pass an empty profile, so only run
conditions can be met (`runs:N` sees 1) — and nothing is granted.

## Rules
- Bonus points = Σ `bonus_cost` of `-` traits − Σ of `+` traits; a set with bonus < 0, duplicates or unowned
  traits is not equippable (`validate_equip`). **No equip-count limit** — bonus points are the only cap
  (`TRAIT_SLOTS` const and `slot_count()` removed, `trait.equip.too_many` deprecated).
- Run: `season_state.run_setup.traits` / `.bonus_points` (snapshot by `GameManager.start_run`).
  Outgame systems read `TraitSystem.run_mod(state, key)` (Σ p1, 0 when none).
- In-game traits go to BattleSim as `match_ctx.traits` (`features/battle_sim/trait/`).
- Score: `RunResult` adds `bonus × phases_cleared × RUN_SCORE_PER_BONUS` (per cleared phase — equip-and-abandon earns nothing).
- Outgame effect hooks (§12.3): `train_exp_pct` → `TrainingBoard.exp_mult_table` (with the
  breakthrough `PlayerData.train_bonus_pct` per pilot), `mastery_pct` → `MechMastery.gain_mult`,
  `income_pct` / `upkeep_pct` → `FinanceSystem.sponsor_income` / `upkeep_cost`, `trust_gain` →
  `MentalSystem.add_trust` (rises only, floored at 0), `incident_pct` → `MentalSystem.ensure_incident`.
  No traits equipped → every multiplier is exactly 1 / every addend 0.
- The run's equipped traits are shown in the hub 스태프 sheet (`StaffPanel`), new unlocks on the
  run result screen (`../run_result/`).
- Equipping UI lives in the manager tab (`../manager/`) and the run setup manager step (`../run_setup/`).
