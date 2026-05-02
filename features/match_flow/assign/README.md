# Match Flow — Assign

## AssignController.gd
`extends Node` — child of MatchFlow.

Lets the player manually assign each of their 5 picked mechs to one of the 5
player slots (TANK / FIGHTER / ASSASSIN / SUPPORT / SNIPER). The enemy team is
auto-assigned by shuffling its 5 picks onto its 5 roster slots.

### Position constraint
**None.** Mechs have no role. Any picked mech may be assigned to any slot.

### UI
- Top row: 5 picked mech cards (HP/ATK/HEAL/MOVE)
- Below: 5 player slot rows (role + player name + assigned mech, or `— empty —`)
- Confirm button — disabled until all 5 slots are filled

### Interaction
- Tap a mech to select it (highlighted yellow)
- Tap an empty slot to assign the selected mech
- Tap an assigned slot to clear it (mech returns to selectable)

### Output
Emits `phase_finished({player_roster, enemy_roster})` after Confirm. By that
point each `PlayerData.assigned_mech` is set on both rosters.
