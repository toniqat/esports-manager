# Traits (M8)

Manager traits — equipped per preset, frozen into the run at run start, scored as bonus points.
Contract: `docs/outgame_dev_plan.md` §12 (effect keys §12.3, unlock grammar §12.4).

## Files
| File | Class | Role |
|---|---|---|
| `TraitSystem.gd` | `class_name TraitSystem extends RefCounted` (static) | `traits.csv` cache, bonus points, `validate_equip`, run-time reads (`run_mod` / `run_pct_mult` / `ingame_traits`), `evaluate_unlocks` |

## Rules
- Bonus points = Σ `bonus_cost` of `-` traits − Σ of `+` traits; a set with bonus < 0, more than
  `TRAIT_SLOTS`, duplicates or unowned traits is not equippable (`validate_equip`).
- Run: `season_state.run_setup.traits` / `.bonus_points` (snapshot by `GameManager.start_run`).
  Outgame systems read `TraitSystem.run_mod(state, key)` (Σ p1, 0 when none).
- In-game traits go to BattleSim as `match_ctx.traits` (`features/battle_sim/trait/`).
- Score: `RunResult` adds `bonus × RUN_SCORE_PER_BONUS`.
- Equipping UI lives in the manager tab (`../manager/`) and the run setup manager step (`../run_setup/`).
