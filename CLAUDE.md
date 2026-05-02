# EsportsManager — Project Navigation Map

## Workflow Instructions
**Read this file first every session.** Then locate the relevant feature folder and read its `README.md` before touching any code.

---

## Project Overview
- **Engine**: Godot 4.5-stable, GDScript
- **Target**: 2D Mobile Portrait 1080×1920
- **Main scene**: `res://scenes/MatchFlow.tscn` (BAN_PICK → ASSIGN → JUNGLE_START → BattleSim)
- **Primary focus**: match flow + `res://scenes/BattleSim.tscn` (battle mechanics)

---

## Directory Structure

```
esports-manager/
├── CLAUDE.md                    ← YOU ARE HERE
│
├── features/
│   ├── card_draw/               ← Card draw game prototype (secondary)
│   │   ├── README.md            ← Read before editing card draw code
│   │   ├── CardDraw.gd          ← Scene controller (was Main.gd)
│   │   └── Card.gd              ← Card visual node
│   │
│   ├── match_flow/              ← Pre-battle pipeline (PRIMARY entry)
│   │   ├── README.md            ← Read before editing match flow code
│   │   ├── MatchFlow.gd         ← class_name MatchFlow — orchestrator
│   │   ├── ban_pick/            ← LoL-international ban/pick + random AI
│   │   ├── assign/              ← Mech↔player slot manual assignment
│   │   └── jungle_start/        ← Assassin jungle start direction (LEFT/RIGHT)
│   │
│   └── battle_sim/              ← Battle simulation (PRIMARY FOCUS)
│       ├── README.md            ← Read before editing battle sim code
│       ├── BattleSim.gd         ← Thin orchestrator (class_name BattleSim)
│       ├── combat/
│       │   ├── README.md
│       │   ├── SimulationCore.gd   ← Main turn loop, targeting, win condition
│       │   ├── MinionSystem.gd     ← Minion spawn/move/merge/combat
│       │   ├── RecallSystem.gd     ← Safe recall state machine
│       │   └── Pathfinding.gd      ← BFS + greedy movement
│       ├── rendering/
│       │   ├── README.md
│       │   └── BattleRenderer.gd   ← All _draw() logic (extends Node2D)
│       ├── card_phase/
│       │   ├── README.md
│       │   └── CardPhaseManager.gd ← Card draw/play overlay and effects
│       ├── gambit/
│       │   ├── README.md
│       │   └── GambitPhaseManager.gd ← Pre-battle lane assignment UI
│       └── ui/
│           ├── README.md
│           └── HudBuilder.gd       ← HUD construction and label updates
│
├── autoloads/
│   ├── README.md                ← Autoload documentation
│   └── GameManager.gd           ← State singleton — NO class_name
│
├── resources/
│   ├── README.md                ← Resource documentation
│   ├── CardData.gd              ← class_name CardData (card data container)
│   ├── GameEnums.gd             ← class_name GameEnums (all shared enums)
│   ├── PilotData.gd             ← class_name PilotData (pilot runtime state)
│   ├── TurretData.gd            ← class_name TurretData (turret state)
│   ├── MinionData.gd            ← class_name MinionData (minion group state)
│   ├── PlayerData.gd            ← class_name PlayerData (out-game persona + assigned mech)
│   └── MechData.gd              ← class_name MechData (mech stats — no role)
│
├── scenes/
│   ├── MatchFlow.tscn           ← MAIN scene — pre-battle pipeline (uses features/match_flow/)
│   ├── BattleSim.tscn           ← Battle sim scene (entered from MatchFlow)
│   ├── CardDraw.tscn            ← Card draw scene (uses features/card_draw/)
│   └── Card.tscn                ← Card prefab (instantiated at runtime)
│
└── addons/godot_mcp/            ← MCP editor plugin (do not modify)
```

---

## Feature Map

| Feature | Scene | Script | Status |
|---|---|---|---|
| Match Flow | `scenes/MatchFlow.tscn` | `features/match_flow/MatchFlow.gd` | **Main entry** — pre-battle pipeline |
| Battle Sim | `scenes/BattleSim.tscn` | `features/battle_sim/BattleSim.gd` | **Primary focus** — consumes match_ctx |
| Card Draw | `scenes/CardDraw.tscn` | `features/card_draw/CardDraw.gd` | Prototype complete |

### Match Flow → Battle Sim handoff
`MatchFlow` populates `GameManager.match_ctx` (player_roster, enemy_roster,
jungle_start_dir, banned_mech_ids, …) then `change_scene_to_file` to BattleSim.
`BattleSim.spawn_pilots_with_lanes()` injects each `PlayerData.assigned_mech`'s
hp/atk/heal/move_range into `PilotData`. If `match_ctx.active` is false (running
BattleSim standalone), it falls back to `ROLE_STATS` defaults.

### Battle Sim — Module Architecture
`BattleSim.gd` is a **thin orchestrator** (`class_name BattleSim extends Node2D`).
Each child module has `@onready var _bs: BattleSim = get_parent() as BattleSim` and accesses state via `_bs.*`.

| Node | Script | Purpose |
|---|---|---|
| SimulationCore | `combat/SimulationCore.gd` | Main turn loop, targeting, movement, win condition |
| MinionSystem | `combat/MinionSystem.gd` | Minion lifecycle (spawn/move/merge/combat) |
| RecallSystem | `combat/RecallSystem.gd` | Safe recall (RETREATING → CHANNELING → teleport) |
| Pathfinding | `combat/Pathfinding.gd` | BFS + greedy movement |
| BattleRenderer | `rendering/BattleRenderer.gd` | All `_draw()` logic (extends Node2D) |
| CardPhaseManager | `card_phase/CardPhaseManager.gd` | Card turn flow, deck, hand, card effects |
| GambitPhaseManager | `gambit/GambitPhaseManager.gd` | Gambit overlay UI and lane assignment |
| HudBuilder | `ui/HudBuilder.gd` | HUD construction and update |

### Battle Sim — Active Systems
| System | Description |
|---|---|
| Gambit Phase | **UI removed.** Lane is now fixed by role (TANK→LEFT, FIGHTER→CENTER, ASSASSIN→GUERRILLA, SUPPORT/SNIPER→RIGHT). Pre-battle choices live in `features/match_flow/`. |
| 3-Lane System | Waypoint paths through T2→T1→midpoint→T1→T2→HQ; unconstrained BFS between waypoints |
| Lane Midpoints | Left=(1,7), Center=(4,7), Right=(7,7) |
| Guerrilla AI | Captures neutral zones first; then pursues lowest-HP enemy |
| Minion System | Spawns 1 group/lane/team every 3 turns; turret gating; group combat |
| Safe Recall | 20% HP threshold → RETREATING → CHANNELING (3 turns) → teleport to HQ |
| Card Phase | Threshold-gated (cost ≥ 8); player plays cards, AI auto-plays, then returns to BATTLE |
| Neutral Zones | 4 rectangular zones; Guerrilla-only capture; gray/blue/red ownership coloring |

---

## Critical Patterns

### Autoload Access (Godot 4.5)
Do NOT use `class_name` on autoload scripts. Access at runtime:
```gdscript
@onready var _gm: Node = get_node("/root/GameManager")
```

### Module Communication
All cross-module calls go through the BattleSim orchestrator:
```gdscript
_bs._sim_core.simulate_turn()
_bs._pathfinder.bfs_next_step(...)
_bs._renderer.queue_redraw()
```

### Enums
All shared enums live in `resources/GameEnums.gd` with `class_name GameEnums`.
- Battle sim: `BattlePhase`, `Role`, `LanePosition`, `Lane`, `RecallState`
- Card draw: `Phase`
- Match flow: `MatchPhase`, `JungleStartDir`, `DraftSide`

### Scene → Script Relationship
Each `.tscn` file references its script by UID. When moving scripts, update both the `.uid` file and the `path=` in the `.tscn` file.

---

## Session Checklist
1. Read `CLAUDE.md` (this file)
2. Identify the target feature (`match_flow`, `battle_sim`, or `card_draw`)
3. Read `features/<feature>/README.md`
4. For battle_sim and match_flow: also read the relevant module's README in its subfolder
5. Make focused changes only in that feature's folder
6. After adding tables/columns to CSV: run **Project → Tools → Rebuild game.db**

---

## Godot-SQLite Addon

**Addon**: `addons/godot-sqlite/` — GDNative SQLite3 wrapper for Godot 4.0+
**Platforms**: Windows, Linux, Mac, Android, iOS, HTML5

### Core API (class `SQLite`)
```gdscript
var db := SQLite.new()
db.path = "res://data/game.db"       # read-only (packaged)
db.path = "user://data/game.db"      # read-write (runtime)
db.open_db()
db.close_db()
db.query("SELECT * FROM pilots")
db.query_with_bindings("SELECT * FROM pilots WHERE role = ?", [role_id])
db.create_table("pilots", { "id": {"data_type":"int","primary_key":true}, ... })
db.insert_row("pilots", {"id":1, "role":"Tank", "hp":200, "atk":8})
db.select_rows("pilots", "hp > 100", ["role","hp"])  # returns Array of Dicts
db.update_rows("pilots", "id = 1", {"hp": 210})
db.delete_rows("pilots", "id = 1")
```

### Data Types
`int` → INTEGER, `real` → REAL, `text`/`char(n)` → TEXT, `blob` → BLOB (PackedByteArray)

### Important Constraints
- Column/table **names cannot be bound** — interpolate them directly into query strings
- **No encryption** support
- Read-only DBs: package inside `.pck` at `res://`; Read-write DBs: copy to `user://` at runtime
- Foreign keys must be enabled **before** `open_db()`

### Import / Export
```gdscript
db.export_to_json("user://backup.json")
db.import_from_json("res://data/seed.json")
db.backup_to("user://save.db")
db.restore_from("user://save.db")
```

### CSV → DB Workflow Pattern
CSV files live in `data/csv/`. The **EditorPlugin** at `addons/csv_to_db/plugin.gd`
reads each CSV at editor time (menu: **Project → Tools → Rebuild game.db**) and
writes `res://data/game.db` using `create_table` + `insert_row`. Adding a new
table = add a CSV under `data/csv/` and add an entry to both `SCHEMAS` and
`TABLE_DEFS` in the plugin.

### Tables (current)
| Table | CSV | Read at | Purpose |
|---|---|---|---|
| `pilots` | `pilots.csv` | BattleSim startup | Per-role baseline stats (used as fallback when match_ctx is inactive) |
| `cards` | `cards.csv` | GameManager startup | Card pool for the BattleSim card phase |
| `game_config` | `game_config.csv` | BattleSim startup | Tunable knobs (HP, turns, thresholds) |
| `lane_config` | `lane_config.csv` | BattleSim startup | LANE_NAMES, LANE_MAX, midpoints |
| `players` | `players.csv` | MatchFlow startup | 10 hardcoded out-game players (5 per team), `PlayerData` fields |
| `mechs` | `mechs.csv` | MatchFlow startup | 30 mech pool (no role); drives PilotData stats when picked |

At runtime, `GameManager` and BattleSim's `DataLoader` open the DB once, load
tables into Dictionaries / Arrays keyed by ID, then close the DB. All in-game
access goes through those structures — not live DB queries.
