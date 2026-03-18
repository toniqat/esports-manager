# EsportsManager — Project Navigation Map

## Workflow Instructions
**Read this file first every session.** Then locate the relevant feature folder and read its `README.md` before touching any code.

---

## Project Overview
- **Engine**: Godot 4.5-stable, GDScript
- **Target**: 2D Mobile Portrait 1080×1920
- **Main scene**: `res://scenes/CardDraw.tscn` (card draw prototype — secondary)
- **Primary focus**: `res://scenes/BattleSim.tscn` (battle mechanics)

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
│   └── MinionData.gd            ← class_name MinionData (minion group state)
│
├── scenes/
│   ├── CardDraw.tscn            ← Card draw scene (uses features/card_draw/)
│   ├── Card.tscn                ← Card prefab (instantiated at runtime)
│   └── BattleSim.tscn           ← Battle sim scene (PRIMARY — uses features/battle_sim/)
│
└── addons/godot_mcp/            ← MCP editor plugin (do not modify)
```

---

## Feature Map

| Feature | Scene | Script | Status |
|---|---|---|---|
| Battle Sim | `scenes/BattleSim.tscn` | `features/battle_sim/BattleSim.gd` | **Primary focus** |
| Card Draw | `scenes/CardDraw.tscn` | `features/card_draw/CardDraw.gd` | Prototype complete |

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
| Gambit Phase | Full-screen overlay; player assigns 5 pilots to Left / Center / Right / Guerrilla before battle |
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
Battle sim enums: `GameEnums.BattlePhase`, `GameEnums.Role`, `GameEnums.Lane`, `GameEnums.RecallState`
Card draw enums: `GameEnums.Phase`

### Scene → Script Relationship
Each `.tscn` file references its script by UID. When moving scripts, update both the `.uid` file and the `path=` in the `.tscn` file.

---

## Session Checklist
1. Read `CLAUDE.md` (this file)
2. Identify the target feature (`battle_sim` or `card_draw`)
3. Read `features/<feature>/README.md`
4. For battle_sim: also read the relevant module's README in its subfolder
5. Make focused changes only in that feature's folder

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
CSV files live in `data/csv/`. An **EditorPlugin tool script** (`tools/CsvToDb.gd`) reads each
CSV at editor time and writes `data/game.db` using `create_table` + `insert_rows`.
At runtime, `GameManager` opens `game.db` once, loads tables into Dictionaries keyed by ID,
then closes the DB. All in-game access goes through those Dictionaries — not live DB queries.
