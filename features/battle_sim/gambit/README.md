# Gambit Phase Module

## GambitPhaseManager.gd
`extends Node` — child of BattleSim.

The old in-battle lane-assignment overlay has been **removed**. Lane assignment
is now fixed by role; the only pre-battle choice (jungle start direction) lives
in `features/match_flow/jungle_start/`.

### Role → Lane mapping (constant `ROLE_TO_LANE`)
| Role | Lane |
|---|---|
| TANK | LEFT |
| FIGHTER | CENTER |
| ASSASSIN | GUERRILLA |
| SUPPORT | RIGHT |
| SNIPER | RIGHT |

LANE_MAX (from `lane_config.csv`) tolerates this distribution: 1 LEFT, 1 CENTER,
2 RIGHT, 1 GUERRILLA = 5 pilots.

### Public API
- `auto_assign_lanes()` — fills `_bs._gambit_lanes[0..4]` from `ROLE_TO_LANE`
- `launch_battle()` — spawns pilots/turrets/neutral zones and sets
  `game_phase = BATTLE`. Equivalent to the old "Launch Battle" button click.

Both run from `BattleSim._ready()` and `_on_restart_pressed()`. There is no
overlay, no buttons, no manual assignment — the BattleSim scene transitions
directly into BATTLE.
