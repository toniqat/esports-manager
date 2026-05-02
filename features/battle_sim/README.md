# Feature: Battle Sim

## Purpose
Turn-based tactical battle simulator on a hex grid. Five pilot roles per team
(Tank, Fighter, Assassin, Support, Sniper) fight toward the enemy HQ through a
3-lane turret system. Includes Card Phase (tactical card overlay).

## Entry point
Normally entered from `scenes/MatchFlow.tscn` via `change_scene_to_file`.
Standalone launch of `BattleSim.tscn` also works — falls back to `ROLE_STATS`
defaults and a default jungle direction (LEFT).

## Match Context handoff
On `_ready()`, BattleSim reads `GameManager.match_ctx`:

| match_ctx field | Used by |
|---|---|
| `player_roster[i].assigned_mech` | `SimulationCore._stats_for()` → `PilotData` hp/atk/heal/move_range |
| `enemy_roster[i].assigned_mech` | same, for team 1 |
| `jungle_start_dir` | `PilotData.jungle_start_pref` on the player-team assassin |
| `active = false` | Triggers fallback to `ROLE_STATS` (no MatchFlow ran) |

---

## Module Architecture

BattleSim.gd is a **thin orchestrator** (`class_name BattleSim extends Node2D`). All logic lives in child modules. Each module has:
```gdscript
@onready var _bs: BattleSim = get_parent() as BattleSim
```
And accesses shared state via `_bs.pilots`, `_bs.turn_count`, etc.

### Child nodes (in scene order)
| Node | Type | Script | Purpose |
|---|---|---|---|
| SimulationCore | Node | `combat/SimulationCore.gd` | Main turn loop, targeting, movement, spawn, win condition |
| MinionSystem | Node | `combat/MinionSystem.gd` | Minion lifecycle (spawn/move/merge/combat) |
| RecallSystem | Node | `combat/RecallSystem.gd` | Safe recall (RETREATING → CHANNELING → teleport) |
| Pathfinding | Node | `combat/Pathfinding.gd` | BFS + greedy movement |
| BattleRenderer | Node2D | `rendering/BattleRenderer.gd` | All `_draw()` logic |
| CardPhaseManager | Node | `card_phase/CardPhaseManager.gd` | Card turn flow, deck, hand, card effects |
| GambitPhaseManager | Node | `gambit/GambitPhaseManager.gd` | Auto role→lane mapping + launch (UI removed; replaced by `features/match_flow/`) |
| HudBuilder | Node | `ui/HudBuilder.gd` | HUD construction and update |

Cross-module calls go through `_bs`:
```gdscript
_bs._sim_core.simulate_turn()
_bs._pathfinder.bfs_next_step(...)
_bs._renderer.queue_redraw()
```

---

## BattleSim.gd (thin orchestrator)

Responsibilities:
- Declares all **constants** (grid, HQ, turret, card phase, lane paths, neutral zones)
- Declares all **state vars** (pilots, turrets, _minions, game_phase, HUD refs, card state, `_gambit_lanes`)
- Holds `@onready` refs to all child modules
- Public **coordinate helpers**: `cell_center(pos)`, `pilot_label(p)`, `role_stats_str(role)`
- **Lifecycle**: `_ready()`, `_process(delta)`, `_unhandled_key_input(event)`
  - `_ready` calls `_gambit.auto_assign_lanes()` then `_gambit.launch_battle()` —
    no overlay, scene transitions straight into BATTLE.
- **Button callbacks**: `_on_next_turn_pressed()`, `_on_auto_play_pressed()`, `_on_restart_pressed()`

---

## Data Classes (resources/)

| File | class_name | Description |
|---|---|---|
| `resources/PilotData.gd` | PilotData | Pilot runtime state: role, hp, team, grid_pos, lane, recall_state, waypoint_idx, **move_range**, **jungle_start_pref** |
| `resources/TurretData.gd` | TurretData | Turret state: team, grid_pos, hp, tier, lane, alive |
| `resources/MinionData.gd` | MinionData | Minion group: team, lane, count (default 30), grid_pos, waypoint_idx |
| `resources/PlayerData.gd` | PlayerData | Out-game persona — id, name, role, team_id, 5 stats, `assigned_mech` |
| `resources/MechData.gd` | MechData | Mech (no role) — id, name, hp, atk, heal, move_range |

---

## Enums (resources/GameEnums.gd)

| Enum | Values |
|---|---|
| `GameEnums.BattlePhase` | GAMBIT, CARD_PHASE, BATTLE |
| `GameEnums.Role` | TANK, FIGHTER, ASSASSIN, SUPPORT, SNIPER |
| `GameEnums.LanePosition` | LEFT=0, CENTER=1, RIGHT=2, GUERRILLA=3 |
| `GameEnums.Lane` | LEFT=0, CENTER=1, RIGHT=2 (waypoint/building lanes) |
| `GameEnums.RecallState` | NONE, RETREATING, CHANNELING |
| `GameEnums.JungleStartDir` | LEFT, RIGHT (assassin start preference) |

---

## Grid

- 9 columns × 15 rows, `CELL_SIZE=100`, `GRID_ORIGIN=(90,130)`
- Code coordinates: (0,0) = top-left (enemy HQ side), (4,14) = player HQ, (4,0) = enemy HQ

## 3-Lane System

| Lane | Team 0 waypoints (HQ→enemy HQ) | Midpoint |
|---|---|---|
| Left (0) | (4,14)→(1,11)→(1,8)→(1,7)→(1,6)→(1,3)→(4,0) | (1,7) |
| Center (1) | (4,14)→(4,11)→(4,8)→(4,7)→(4,6)→(4,3)→(4,0) | (4,7) |
| Right (2) | (4,14)→(7,11)→(7,8)→(7,7)→(7,6)→(7,3)→(4,0) | (7,7) |
| Guerrilla (3) | Unconstrained — captures neutral zones then chases lowest-HP enemy | — |
Team 1 paths are exact reverses of Team 0.

## Turret Positions

| Team | Tier | Left | Center | Right |
|---|---|---|---|---|
| 1 (enemy) | T1 | (1,6) | (4,6) | (7,6) |
| 1 (enemy) | T2 | (1,3) | (4,3) | (7,3) |
| 0 (player) | T1 | (1,8) | (4,8) | (7,8) |
| 0 (player) | T2 | (1,11) | (4,11) | (7,11) |

T2 is invulnerable while its lane T1 is alive. HQ is only attackable after a T2 is destroyed.
Turrets require friendly minions present (acting as siege shields) before pilots can attack them.

## Neutral Zone Ownership

4 rectangular zones (2 friendly-side, 2 enemy-side). Only the Guerrilla pilot can capture them by stepping on their cells. Gray = uncaptured; blue = team 0; red = team 1.

## Recall System

At 20% HP, a pilot enters RETREATING: moves to a safe cell behind their nearest friendly turret.
Once there, 3-turn CHANNELING countdown begins. If interrupted by an enemy in the same cell, restart RETREATING. On completion, teleport to own HQ at full HP.

## Minion System

- Spawn: 1 group per lane per team every 3 turns at own HQ
- Move: stops at first enemy in cell (turret, pilot, or opposing minion group)
- Turret gating: pilot can only attack a turret if friendly minions are in the same cell
- Minion combat: floor(N/2) mutual damage per turn when opposing groups meet

## Card Phase

Triggered when `_player_cost >= PHASE_THRESHOLD (8)`. Player plays cards from fan hand; AI auto-plays affordable cards on End Phase. Cards draw 1/side/turn. Cost carries over unspent.

---

## Dependencies

- `resources/GameEnums.gd` — shared enums
- `resources/PilotData.gd`, `TurretData.gd`, `MinionData.gd` — data classes
- `autoloads/GameManager.gd` — battle phase signals (infrastructure, optional sync)
- `scenes/Card.tscn` / `features/card_draw/Card.gd` — card visual nodes
