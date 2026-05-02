# UI Module

## HudBuilder.gd
`extends Node` — child of BattleSim.

Builds the battle HUD and updates it each turn via `update_hud()`.

### build_ui()
Creates UI panels inside `_bs.canvas` (a CanvasLayer added to BattleSim):

- **Top panel** (y=0, h=110) — Enemy pilot status board (5 slots, team 1)
- **Bottom panel** (y=1650, h=270) — Allied pilot status board (5 slots, team 0) + controls
- **Victory panel** — Win/lose label + Play Again button

Removed: Enemy HQ HP label, Player HQ HP label, Turn counter.

Also connects:
- `btn_next.pressed` → `_bs._on_next_turn_pressed`
- `_btn_auto.pressed` → `_bs._on_auto_play_pressed`
- `btn_end_card_phase.pressed` → `_bs._card_phase.end_card_phase`
- Play Again button → `_bs._on_restart_pressed`

### Pilot Status Boards
Each board contains 5 pre-built slots. Each slot has:
- **Icon** — `ColorRect` background in role color + `Label` showing role abbreviation (T/F/A/S/Sn)
- **HP bar** — `ProgressBar` (0–100, no percentage text)
- **DEAD label** — red "DEAD" label that replaces the bar when pilot is dead (icon goes grayscale)

Slots are sorted left-to-right by `LanePosition` (LEFT → CENTER → RIGHT → GUERRILLA).
Empty slots (before gambit launches pilots) are hidden.

Role colors: TANK=blue, FIGHTER=orange, ASSASSIN=purple, SUPPORT=green, SNIPER=red.

Board layout: 16px margin each side, SLOT_W=192px, SLOT_GAP=8px, ICON_SIZE=60px, BAR_H=22px.

### update_hud()
- Updates log label, cost label, button visibility (BATTLE vs CARD_PHASE).
- Calls `_update_pilot_boards()` which re-sorts `_bs.pilots` by team and lane, then calls `_apply_slots()`.

### mk_label(parent, text, font_size, color, pos, sz, align)
Convenience helper to create and add a styled Label.
