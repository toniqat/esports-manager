# quirk/ — quirks (기벽, §14 T1)

Contract: `docs/outgame_dev_plan.md` §14. Run-only positive pilot passives (stat bonuses only),
applied by `MatchFlow._finalize_rosters` to roster copies — BattleSim never reads them.

| File | Role |
|---|---|
| `QuirkSystem.gd` | `class_name QuirkSystem` (static). State `season_state.quirks`, gain / reroll / slot, stat bonus, `apply_to`. |

(Stub from the base commit — the T1 agent writes the rules, table grammar and UI sections.)
