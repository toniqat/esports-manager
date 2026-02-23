# Card Phase Module

## CardPhaseManager.gd
`extends Node` — child of BattleSim.

Manages the card draw/play overlay that gates each battle turn.

### Turn flow
- `do_battle_turn()` — calls `_bs._sim_core.simulate_turn()`, accumulates cost, draws cards, enters CARD_PHASE when cost ≥ PHASE_THRESHOLD
- `start_card_phase()` — transitions to CARD_PHASE, highlights affordable cards
- `end_card_phase()` — AI plays affordable cards, returns to BATTLE

### Card management
- `build_starter_decks()` — 10-card decks from a 6-card pool (Strike / Mend / Reinforce / Focus Fire / Rally / Overcharge)
- `draw_card(is_player)` → CardData — pops from deck, reshuffles discard if empty
- `spawn_card_node(cd)` / `spawn_ai_card_node()` — instantiates Card.tscn into _bs._canvas
- `relayout_hand(nodes, center, flip)` — fan arc layout; `fan_slot(index, total, center, flip)` → position/rotation dict
- `highlight_affordable_cards()` — marks affordable player cards

### Card interaction
- `on_player_card_clicked(card)` — first click selects, second click plays
- `select_card` / `deselect_card` — tween to selected position or back to fan
- `play_player_card(card)` — deducts cost, removes from hand, applies effect
- `apply_card_effect(cd, is_player)` → String log message

### Effect types
| effect_type | Behaviour |
|---|---|
| damage | Random enemy pilot -N HP |
| focus_damage | Lowest-HP enemy -N HP |
| heal | Lowest-HP ally +N HP |
| buff_atk | All ally pilots +N ATK next simulate_turn() |
| minions | +N minions to random ally lane |
