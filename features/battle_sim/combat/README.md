# Combat Modules

All scripts extend `Node` and are children of the root `BattleSim` node.
Each module accesses shared state via `@onready var _bs: BattleSim = get_parent() as BattleSim`.

## Pathfinding.gd
BFS pathfinding with greedy fallback.
- `bfs_next_step(from, to, mover, constraint, stop_dist, preferred_col)` → Vector2i
- `greedy(from, to, blocked, constraint, preferred_col)` → Vector2i
- `neighbors(pos, constraint, preferred_col)` → Array[Vector2i]
- `chebyshev(a, b)` → int; `manhattan(a, b)` → int

## RecallSystem.gd
Safe recall logic (RETREATING → CHANNELING → teleport).
- `compute_recall_safe_pos(pilot)` → Vector2i
- `check_danger_state(log_lines)` — triggers RETREATING at 20% HP
- `process_channeling(log_lines)` — ticks channel timer, handles interruption

## MinionSystem.gd
Minion lifecycle: spawn, move, merge, combat.
- `spawn_minions()` — every `MINION_SPAWN_INTERVAL` turns
- `move_minions(log_lines)` — advances waypoints, stops on enemies
- `merge_minions()` — same-team groups on same cell are merged
- `process_minion_combat(minion_dmg, log_lines)` — floor(N/2) mutual damage
- `get_friendly_minions_at(pos, team)` → bool
- `get_minions_at_cell(pos, team)` → MinionData or null
- `furthest_minion_in_lane(lane, team)` → MinionData or null

## SimulationCore.gd
Main turn loop and all combat/movement/spawn logic.
- `simulate_turn()` — full turn: respawns → danger → channeling → minions → pilots → turrets → damage → zone captures → win check
- `get_enemies_in_range`, `get_turrets_in_range`, `get_allies_in_range`
- `find_weakest_ally`, `pick_target`, `move_pilot`
- `current_waypoint`, `enemy_turret_blocking_at`, `nearest_uncaptured_zone`
- `t1_alive_in_lane`, `any_t2_destroyed`, `has_enemy_turret_at`
- `process_respawns`, `init_ownership_map`, `init_neutral_zones`
- `process_neutral_zone_captures`, `spawn_pilots_with_lanes`, `spawn_turrets`
- `check_win_condition`
