# Manager (M9)

Manager growth and presets between runs. Contract: `docs/outgame_dev_plan.md` §12.

## Files
| File | Class | Role |
|---|---|---|
| `ManagerProgress.gd` | `class_name ManagerProgress extends RefCounted` (static) | Pure rules over the profile dict: levels (`manager_levels.csv`), removal / specialisation points, preset stats + validation, prestige |
| `ManagerTab.gd` | `class_name ManagerTab extends Control` | Lobby `감독` tab (stub in the base commit) |

## Stat model
`base = type − removed` (≥ 1, removals permanent until prestige), `preset = base + alloc` (≤ `MANAGER_STAT_CAP`).
Each level-up = `MANAGER_REMOVE_PER_LEVEL` removal points; one removal = one specialisation point;
`Σ alloc ≤ Σ removed` per preset. Prestige at `PRESTIGE_LEVEL`: level / exp / removals reset, type
re-chosen, presets → `kind = "prestige"` (unusable until `reset_preset`), +1 normal preset (≤
`PRESET_MAX_COUNT`), `PRESTIGE_REWARD_*` currency. Mutators don't save — the screen calls `save_profile()`.
