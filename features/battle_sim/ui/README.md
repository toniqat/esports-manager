# UI Module

## HudBuilder.gd
`extends Node` — child of BattleSim.

Builds the battle HUD and updates labels each turn.

### build_ui()
Creates two panels inside `_bs._canvas` (a CanvasLayer added to BattleSim):
- **Top panel** — Enemy HQ HP label, Turn counter
- **Bottom panel** — Player HQ HP label, Next Turn button, Auto Play button, log label, Cost label, End Phase button
- **Victory panel** — Win/lose label + Play Again button

Also connects:
- `_btn_next.pressed` → `_bs._on_next_turn_pressed`
- `_btn_auto.pressed` → `_bs._on_auto_play_pressed`
- `_btn_end_card_phase.pressed` → `_bs._card_phase.end_card_phase`
- `rb.pressed` (Play Again) → `_bs._on_restart_pressed`

### update_hud()
Refreshes all labels from `_bs` state. Toggles visibility of Next Turn / Auto Play (BATTLE only) and End Phase (CARD_PHASE only).

### mk_label(parent, text, font_size, color, pos, sz, align)
Convenience helper to create and add a styled Label.
