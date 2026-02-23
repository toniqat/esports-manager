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
