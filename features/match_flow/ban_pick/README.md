# Match Flow — Ban/Pick

## BanPickController.gd
`extends Node` — child of MatchFlow.

Implements the LoL-international ban/pick draft against a random AI opponent.

### Sequence (14 actions)
Pattern: `B-B-P-PP-PP-P-B-B-PP-PP` — 4 bans + 10 picks total. Each side ends
with **2 bans + 5 picks**.

| # | Side | Kind |
|---|---|---|
| 0 | Blue | Ban |
| 1 | Red | Ban |
| 2 | Blue | Pick |
| 3 | Red | Pick |
| 4 | Red | Pick |
| 5 | Blue | Pick |
| 6 | Blue | Pick |
| 7 | Red | Pick |
| 8 | Blue | Ban |
| 9 | Red | Ban |
| 10 | Blue | Pick |
| 11 | Blue | Pick |
| 12 | Red | Pick |
| 13 | Red | Pick |

The constant `SEQUENCE` encodes this directly. `player_side` (BLUE or RED) is
passed in by MatchFlow at random.

### UI
Full-screen panel with:
- 14-box sequence indicator at top (highlights current action)
- 5×6 mech card grid (all 30 mechs from the DB)
- Pick rosters (Blue / Red) under the grid
- Status label showing whose turn it is

Mechs that are banned or picked are dimmed and disabled. Clicking a legal mech
on the player's turn commits the action.

### Opponent AI
Simple: when `SEQUENCE[_action_idx][0] != _player_side`, after a 0.45 s delay
the AI picks/bans a random legal mech.

### Output
Emits `phase_finished({banned, player_picks, enemy_picks})` once index 14 is reached.
`player_picks` / `enemy_picks` are mapped from blue/red to the user's perspective.

### Mechs have no role
Any mech can be picked into any slot — assignment to a position happens later
in the Assign phase.
