# Feature: Card Draw

## Purpose
Prototype card-draw game where the player and AI alternate drawing from separate decks, accumulate mana (CP), and play cards during action phases. Demonstrates core card game loop, fan-arc hand layout, and flip animations.

## Files

### CardDraw.gd
**Scene controller** for `scenes/CardDraw.tscn` (root Node2D).

Responsibilities:
- Connects to `GameManager` autoload signals and drives all UI updates
- Manages `player_card_nodes` and `ai_card_nodes` arrays of `Card` instances
- Orchestrates draw phase (animates cards from deck position to fan hand)
- Handles player input: tap-to-select, second-tap-to-play, End Turn button
- Runs AI turn: picks affordable cards with delay, then ends AI turn
- Fan layout: `_fan_position()` / `_relayout_hand()` place cards on a circular arc

Key constants: `PLAYER_HAND_CENTER`, `AI_HAND_CENTER`, `FAN_RADIUS`, `FAN_HALF_ANGLE_DEG`

### Card.gd
**Card visual node** (`class_name Card`, extends Control). Used by `scenes/Card.tscn`.

Responsibilities:
- Displays card data (name, cost, description) with cost-tier color tinting
- Flip animation: scale-X tween to 0 → swap panel visibility → scale-X back to 1
- Arc movement: quadratic bezier `animate_to()` from deck to hand position
- Hover lift (mouse_entered/exited) and click signal (`card_clicked`)
- `set_affordable()`: applies gold border when card is playable

## Dependencies
- `GameManager` autoload (`/root/GameManager`) — phase/draw/mana signals
- `CardData` resource (`res://resources/CardData.gd`) — card name/cost/description
- `GameEnums` (`res://resources/GameEnums.gd`) — `Phase` enum
- `scenes/Card.tscn` — instantiated at runtime for each drawn card
