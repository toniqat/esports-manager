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

### Turn loop
- `simulate_turn()` — full turn: respawns → danger → channeling → minions →
  pilots → turrets → damage → zone captures → win check

### Targeting
- `get_enemies_in_range`, `get_turrets_in_range`, `get_allies_in_range`
- `find_weakest_ally`, `pick_target`

### Movement
- `move_pilot(pilot)` — calls `_step_pilot_once` up to `pilot.move_range` times
  (stops early on no-progress). `move_range` is set from the assigned mech.
- `_step_pilot_once(pilot)` — single-cell advance: chooses goal (waypoint /
  weak ally / capture target / lowest-HP enemy), applies turret gating, then
  asks Pathfinding for one step.
- `current_waypoint`, `lane_turret_gate`, `enemy_turret_blocking_at`

### Neutral zones (jungle)
- `nearest_uncaptured_zone(pilot)` — biases the assassin toward the zone
  matching `pilot.jungle_start_pref`; falls back to the other own-side zone
  once the preferred one is captured. With pref = -1 it returns nearest across
  both own-side zones (legacy behavior).
- `_nearest_in_cells(pilot, cells)` — helper used by the function above.
- `init_neutral_zones`, `process_neutral_zone_captures`

### Spawning
- `spawn_pilots_with_lanes()` — builds 5 player + 5 enemy `PilotData` using the
  fixed role→lane mapping from `GambitPhaseManager.ROLE_TO_LANE`. Stats come
  from `_stats_for(...)`.
- `_stats_for(ctx_active, roster, idx, role_id)` — returns `{hp, atk, heal, move_range}`.
  When `match_ctx.active`, pulls from `roster[idx].assigned_mech`. Otherwise
  falls back to `ROLE_STATS` defaults (move_range = 1).
- The assassin (GUERRILLA) gets `jungle_start_pref` set from `match_ctx.jungle_start_dir`
  (player team) or randomly (enemy team).
- `spawn_turrets()` — reads `TURRET_POSITIONS` from FieldLoader, falls back to
  hardcoded coordinates if missing.

### Misc
- `t1_alive_in_lane`, `any_t2_destroyed`, `has_enemy_turret_at`
- `process_respawns`, `lowest_hp_enemy`, `weak_ally_target`
- `check_win_condition`
