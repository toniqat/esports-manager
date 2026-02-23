# Gambit Phase Module

## GambitPhaseManager.gd
`extends Node` — child of BattleSim.

Builds and manages the pre-battle pilot lane assignment overlay.

### UI building
- `build_gambit_ui()` — creates full-screen overlay Panel, 5 pilot buttons, 4 lane slot panels, status label, Auto-Assign and Launch Battle buttons. Stores all refs on `_bs`.

### Refresh
- `refresh_gambit_ui()` — updates pilot button text/colour, slot labels, launch button enabled state, and status text.

### Callbacks
- `on_gambit_pilot_selected(idx)` — toggles pilot selection highlight
- `on_gambit_slot_pressed(slot)` — assigns selected pilot to slot (respects LANE_MAX)
- `on_gambit_auto_assign_pressed()` — random 2-1-1-1 + 1 Guerrilla assignment
- `on_launch_battle_pressed()` — hides overlay, spawns pilots + turrets + neutral zones, transitions to BATTLE

### Constraints
- Max 2 pilots per lane (LEFT / CENTER / RIGHT), max 1 Guerrilla
- "Launch Battle" is disabled until all 5 pilots are assigned
