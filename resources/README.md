# Resources

Shared data definitions used across features.

## Files

### CardData.gd
`class_name CardData`, extends `Resource`.

A lightweight data container for a single card:
- `card_name: String`
- `cost: int` — mana cost (1–7+)
- `description: String`

Instantiated at runtime by `GameManager._build_decks()`. Not saved to disk.

### GameEnums.gd
`class_name GameEnums`, extends `RefCounted`.

Shared enum definitions:
- `Phase { DRAW, PLAYER_ACTION, AI_ACTION }` — used by GameManager and CardDraw scene
- `Role { TANK, FIGHTER, ASSASSIN, SUPPORT, SNIPER }` — pilot/player position
- `LanePosition { LEFT, CENTER, RIGHT, GUERRILLA }` — battle-lane slot
- `Lane { LEFT, CENTER, RIGHT }` — waypoint/building lanes (no GUERRILLA)
- `BattlePhase { GAMBIT, CARD_PHASE, BATTLE }` — in-battle phase machine
- `RecallState { NONE, RETREATING, CHANNELING }` — pilot recall state
- `MatchPhase { LOAD, BAN_PICK, ASSIGN, JUNGLE_START, LAUNCH }` — out-of-battle pipeline
- `JungleStartDir { LEFT, RIGHT }` — assassin's jungle entry side
- `DraftSide { BLUE, RED }` — ban/pick draft sides

### PilotData.gd
`class_name PilotData`, extends `RefCounted`.

In-battle pilot state: role, hp/max_hp, atk, team, grid_pos, lane, recall fields,
`waypoint_idx`, plus `move_range` (cells/turn) and `jungle_start_pref`
(GameEnums.JungleStartDir or -1).

### TurretData.gd, MinionData.gd
In-battle building/minion state — see `features/battle_sim/README.md`.

### PlayerData.gd
`class_name PlayerData`, extends `Resource`.

Out-game player persona consumed by MatchFlow / BattleSim:
- `id, name, role (GameEnums.Role), team_id (0=player, 1=enemy)`
- Stats `laning, mechanics, gamesense, teamfight, mental` (each 1–100)
- `assigned_mech: MechData` — set by AssignController at match prep time

Loaded from the `players` table (CSV-seeded via `addons/csv_to_db`).

### MechData.gd
`class_name MechData`, extends `Resource`.

Mech with **no role/position** — any mech is assignable to any player slot:
- `id, name`
- Combat stats `hp, atk, heal, move_range` — drive PilotData stats when piloted

Loaded from the `mechs` table.

## Usage Pattern
```gdscript
# Reference enums
GameEnums.Phase.DRAW
GameEnums.MatchPhase.BAN_PICK

# Create card data
var card = CardData.new("Strike", 1, "A basic attack.")

# Match-flow data
var p := PlayerData.new(0, "Faker", GameEnums.Role.ASSASSIN, 0, 95, 95, 98, 95, 98)
var m := MechData.new(12, "Phantom-S1", 90, 26, 0, 2)
p.assigned_mech = m
```
