# Match Flow — Jungle Start

## JungleStartController.gd
`extends Node` — child of MatchFlow.

Replaces the old in-battle Gambit lane-assignment overlay. Asks the user one
question: which side of the jungle does the assassin start on?

### Options
- `LEFT` (default) — assassin prefers neutral zone 0 (player team) / 2 (enemy team)
- `RIGHT` — prefers neutral zone 1 (player team) / 3 (enemy team)

### UI
Two large toggle buttons (LEFT / RIGHT) and a `Launch Battle` button.
Selection is reflected immediately; Launch is enabled once a direction is set
(the controller defaults to LEFT on entry so launch is always enabled).

### Output
Emits `phase_finished({dir})` where `dir` is `GameEnums.JungleStartDir.LEFT` or
`RIGHT`.

### Where it's consumed
`MatchFlow` writes the value into `GameManager.match_ctx.jungle_start_dir`.
`SimulationCore.spawn_pilots_with_lanes()` copies it onto the assassin's
`PilotData.jungle_start_pref`. `SimulationCore.nearest_uncaptured_zone()` then
prefers cells from the matching neutral zone before falling back to the other.
