# Autoloads

Godot singletons registered in `project.godot`. Available globally via `/root/<Name>`.

## Files

### GameManager.gd
**Game state singleton** for the Card Draw feature. No `class_name` — access at runtime via `get_node("/root/GameManager")`.

Responsibilities:
- Owns both decks (`player_deck`, `ai_deck`), hands, and discard piles
- Tracks `current_phase` (DRAW / PLAYER_ACTION / AI_ACTION) using `GameEnums.Phase`
- Manages mana pools (`player_mana`, `ai_mana`, `max_cost`)
- Emits signals for all state changes; scene scripts connect to these

Key signals: `phase_changed`, `card_drawn`, `card_played`, `mana_changed`, `game_log`, `ai_turn_finished`, `card_overflow_discarded`

Key methods:
- `start_draw_phase()` — resets draw alternation, emits `phase_changed`
- `execute_draw()` — draws one card for the current player, checks initiative (threshold = 7)
- `player_play_card(card)` → bool — deducts mana, emits `card_played`
- `ai_play_card()` → CardData — picks random affordable card
- `end_player_turn()` / `end_ai_turn()` — transitions back to draw phase

## Note
Do NOT add `class_name` to autoload scripts in Godot 4.5 — causes parse errors in other scripts.
