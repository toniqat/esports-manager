# Autoloads

Godot singletons registered in `project.godot`. Available globally via `/root/<Name>`.

## Files

### GameManager.gd
**Game state singleton** — owns the BattleSim card pool and the **match
context** that flows from MatchFlow into BattleSim. No `class_name` (Godot 4.5
quirk) — access at runtime via `get_node("/root/GameManager")`.

---

#### BattleSim card pool
- `card_pool_bs: Array` — loaded once on `_ready()` from the `cards` table via
  `_load_card_pool_bs()`. CardPhaseManager copies entries into starter decks.

---

#### Match Context (MatchFlow → BattleSim)
Populated by `features/match_flow/MatchFlow.gd` and consumed by
`features/battle_sim/combat/SimulationCore.spawn_pilots_with_lanes()`.

```gdscript
var match_ctx: Dictionary = {
    "active": bool,                 # false when running BattleSim standalone
    "player_roster": Array[PlayerData],   # 5 players sorted by role 0..4
    "enemy_roster":  Array[PlayerData],
    "jungle_start_dir": int (GameEnums.JungleStartDir),
    "player_side":   int (GameEnums.DraftSide),
    "banned_mech_ids": Array[int],
    "all_mechs":      Array[MechData],
}
```

API:
- `reset_match_ctx()` — clears all keys back to defaults (active = false)
- `load_match_data()` → `{"players": Array[PlayerData], "mechs": Array[MechData]}`
  or `{"error": String}`. Reads the `players` and `mechs` SQLite tables.

When `match_ctx.active == false`, BattleSim falls back to `ROLE_STATS` defaults
(loaded from `pilots.csv`).

## Note
Do NOT add `class_name` to autoload scripts in Godot 4.5 — causes parse errors in other scripts.
