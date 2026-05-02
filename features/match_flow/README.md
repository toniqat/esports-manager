# Feature: Match Flow

## Purpose
Pre-battle pipeline that runs **before** `BattleSim.tscn`:

```
LOAD → BAN_PICK → ASSIGN → JUNGLE_START → LAUNCH (change_scene → BattleSim)
```

Entry point: `scenes/MatchFlow.tscn` (set as the project's main scene). On `LAUNCH`,
`GameManager.match_ctx` is populated and the scene transitions to `BattleSim.tscn`.

---

## Module Architecture

`MatchFlow.gd` is a thin orchestrator (`class_name MatchFlow extends Node2D`).
Three child controllers each build their own UI on `enter()` and emit
`phase_finished(result)` when done:

| Node | Script | Responsibility |
|---|---|---|
| BanPickController | `ban_pick/BanPickController.gd` | LoL-international ban/pick (4 bans + 10 picks) with random AI |
| AssignController | `assign/AssignController.gd` | Manual mech↔player slot assignment for the player team (enemy auto-shuffled) |
| JungleStartController | `jungle_start/JungleStartController.gd` | Choose Assassin's jungle start direction (LEFT or RIGHT) |

Each controller accesses the orchestrator via:
```gdscript
@onready var _mf: MatchFlow = get_parent() as MatchFlow
```
UI panels parent to `_mf.canvas` (the CanvasLayer in MatchFlow.tscn).

---

## MatchFlow.gd

State machine with phases from `GameEnums.MatchPhase`. Loads `players` and `mechs`
tables on entry via `GameManager.load_match_data()`. On the final `LAUNCH` phase
populates:

```gdscript
GameManager.match_ctx = {
	"active": true,
	"player_roster": Array[PlayerData],   # 5 players sorted by role 0..4, assigned_mech set
	"enemy_roster":  Array[PlayerData],
	"jungle_start_dir": int (LEFT|RIGHT),
	"player_side":   int (BLUE|RED),
	"banned_mech_ids": Array[int],
	"all_mechs":      Array[MechData],
}
```

`BattleSim.gd` reads `match_ctx.active` to decide whether to inject mech stats
into pilots; otherwise it falls back to `ROLE_STATS` defaults.

---

## Data flow into BattleSim
- `PlayerData.assigned_mech.hp/atk/heal/move_range` → `PilotData` stats via
  `SimulationCore._stats_for()`
- `match_ctx.jungle_start_dir` → `PilotData.jungle_start_pref` (assassin only),
  consumed by `SimulationCore.nearest_uncaptured_zone()` for zone preference

---

## Files

| File | Purpose |
|---|---|
| `MatchFlow.gd` | State machine orchestrator |
| `ban_pick/BanPickController.gd` | Ban/Pick phase |
| `assign/AssignController.gd` | Mech-to-player assignment phase |
| `jungle_start/JungleStartController.gd` | Jungle direction phase |
