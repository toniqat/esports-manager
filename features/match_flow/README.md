# Feature: Match Flow

## Purpose
Pre-battle pipeline that runs **before** `BattleSim.tscn`:

```
LOAD → PREP → BAN_PICK → ASSIGN → JUNGLE_START → LAUNCH (change_scene → BattleSim)
```

PREP is the pre-match dashboard — both rosters' stats laid out side by
side so the player can review who they're up against before committing
to BAN_PICK. Pressing "경기 시작" advances to BAN_PICK and triggers the
pre-ban-pick autosave.

Entry point: `scenes/MatchFlow.tscn`. Resume saves skip PREP and jump
directly to BAN_PICK (or LAUNCH for post-gambit saves) since the player
already committed when the save was written. On `LAUNCH`,
`GameManager.match_ctx` is populated and the scene transitions to `BattleSim.tscn`.

---

## Module Architecture

`MatchFlow.gd` is a thin orchestrator (`class_name MatchFlow extends Node2D`).
Three child controllers each build their own UI on `enter()` and emit
`phase_finished(result)` when done:

| Node | Script | Responsibility |
|---|---|---|
| MatchPrepController | `match_prep/MatchPrepController.gd` | Pre-match dashboard — both rosters with stats. "경기 시작" → BAN_PICK. |
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
- `PlayerData.assigned_mech.hp/atk` → `PilotData` stats via
  `SimulationCore._stats_for()`
- `match_ctx.jungle_start_dir` → `PilotData.jungle_start_pref` (assassin only),
  consumed by `SimulationCore._nearest_uncaptured_neutral()` for zone preference

---

## Files

| File | Purpose |
|---|---|
| `MatchFlow.gd` | State machine orchestrator |
| `ban_pick/BanPickController.gd` | Ban/Pick phase |
| `assign/AssignController.gd` | Mech-to-player assignment phase |
| `jungle_start/JungleStartController.gd` | Jungle direction phase |

---

## Save hooks
`MatchFlow.gd` owns two of the four campaign autosave triggers (the other
two live in `SeasonHub`):

- **Pre-ban-pick** — fires in `_on_prep_finished()` when the player
  presses "경기 시작" on the PREP dashboard. Writes
  `season_state.match_resume = {phase: BAN_PICK, player_side, ...empty
  arrays}`. Skipped when running MatchFlow standalone (no `pending_match`).
- **Post-gambit** — fires in `_on_jungle_finished()` before `_launch_battle`
  scene-changes to BattleSim. Writes the full match snapshot:
  `{phase: LAUNCH, player_side, banned_mech_ids, player_picked_mech_ids,
  enemy_picked_mech_ids, player_assigned_mech_ids, enemy_assigned_mech_ids,
  jungle_start_dir}`. The mech-id arrays are 5-entry, role-sorted (0..4) so
  resume can re-attach `assigned_mech` to each PlayerData.

### Resume entry
`_ready()` reads `season_state.match_resume`. Non-null → skip PREP (the
player already committed when the save was written) and:
- `phase == BAN_PICK` → restore `player_side` and `_enter_phase(BAN_PICK)`.
- `phase == LAUNCH` → `_resume_at_launch(resume)` rebuilds `match_ctx`
  from the resume payload (rosters via `_team_roster()`, mechs via
  `_find_mech()`) and scene-changes to BattleSim immediately. No UI
  controllers run.

`match_resume` is cleared in-memory on consumption; on disk it's only
overwritten by the next post-gambit or post-week save. Closing mid-battle
keeps the disk save at the post-gambit snapshot, so the resume path
replays the battle from scratch with the same locked-in picks.
