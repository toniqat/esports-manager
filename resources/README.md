# Resources

Shared data definitions used across features.

## Files

### CardData.gd
`class_name CardData`, extends `Resource`.

One row from the `cards` SQLite table, plus a few runtime fields:
- `card_name: String`
- `cost: int` — 작전 점수 cost
- `uses: int` — max plays per match (0 = unlimited)
- `cast_method: String` — `range / target / location / instant`
- `target: String` — `caster / enemy / ally / pilot / hand / location`
- `cast_range: int` — tiles from caster (0 = self, 99 = unbounded)
- `area: int` — AoE radius around target (0 = single)
- `keyword: String` — empty or `"exhaust"` (소멸)
- `effect: String` — semicolon-chain dispatched by `CardPhaseManager`
  (e.g. `"draw:2;discard:2"`, `"attack:1|pierce"`)
- `description: String` — text shown on the card front + description box
- `owner_pilot: PilotData` (runtime, **not** `@export`) — the 시전자, set
  by `CardPhaseManager.build_starter_decks()`
- `remaining_uses: int` (runtime) — per-instance charges left this match

Instantiated at runtime by `CardPhaseManager.build_starter_decks()` from the
`cards` SQLite table (loaded into `GameManager.card_pool_bs`). Not saved to disk.

### GameEnums.gd
`class_name GameEnums`, extends `RefCounted`.

Shared enum definitions:
- `Role { TANK, FIGHTER, ASSASSIN, SUPPORT, SNIPER }` — pilot/player position
- `LanePosition { LEFT, CENTER, RIGHT, GUERRILLA }` — battle-lane slot
- `Lane { LEFT, CENTER, RIGHT }` — waypoint/building lanes (no GUERRILLA)
- `BattlePhase { GAMBIT, CARD_PHASE, BATTLE }` — in-battle phase machine
- `TowerLevel { HQ, LEVEL_2, LEVEL_1 }` — building atlas selector
- `MatchPhase { LOAD, BAN_PICK, ASSIGN, JUNGLE_START, LAUNCH }` — out-of-battle pipeline
- `JungleStartDir { LEFT, RIGHT }` — assassin's jungle entry side
- `DraftSide { BLUE, RED }` — ban/pick draft sides

### PilotData.gd
`class_name PilotData`, extends `RefCounted`.

In-battle pilot state: role, hp/max_hp, atk, team, grid_pos, lane, waypoint_idx,
`move_range` (cells per minute), `jungle_start_pref` (GameEnums.JungleStartDir
or -1), plus combat dice stats `hit` and `evasion` populated from PlayerData
(`mechanics` → hit, `gamesense` → evasion). Recall is now an instant teleport,
so there is no recall_state / channel_timer field.

`shield: int` is the 보호막 pool granted by the 보호 card. Both card attacks
and battlefield damage (the `damage_map` apply step in `SimulationCore.simulate_turn`)
subtract from `shield` first, then `hp`. Cleared on every 본진 복귀 path:
`RecallSystem._teleport_home` (HP threshold / out-of-position / 복귀 card) and
`SimulationCore.process_respawns` (death respawn).
`BattleRenderer._draw_pilot_circle` paints a cyan ring just outside the HP ring
sized by `shield / max_hp` so the buff is visible on the field.

UI animation fields (`anim_prev_grid_pos`, `anim_move_t/dur`, `anim_shake_t/dur`,
`anim_recall_phase/t/dur/orig`) are mutated by `BattleSim.anim_pilot_*` helpers
and read only by `BattleRenderer` — the simulation never reads them.

### TurretData.gd
In-battle turret state — see `features/battle_sim/README.md`.

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
- Combat stats `hp, atk` — drive PilotData stats when piloted

Loaded from the `mechs` table.

### BuildingData.gd / WaypointData.gd
Optional inspector-set blueprint resources for `Building` / `Waypoint` nodes
under `BattleField/BuildingLayer` and `BattleField/WaypointLayer`.

### UiHelpers.gd
`class_name UiHelpers`, extends `RefCounted`. Static helpers for
procedurally-built UI panels — currently `mk_label(...)` shared by MatchFlow
controllers and HudBuilder.

## Usage Pattern
```gdscript
# Reference enums
GameEnums.MatchPhase.BAN_PICK

# Create card data
var card = CardData.new("Strike", 1, "A basic attack.")

# Match-flow data
var p := PlayerData.new(0, "Faker", GameEnums.Role.ASSASSIN, 0, 95, 95, 98, 95, 98)
var m := MechData.new(12, "Phantom-S1", 90, 26, 0, 2)
p.assigned_mech = m
```
