# Resources

Shared data definitions used across features.

## Files

### CardData.gd
`class_name CardData`, extends `Resource`.

A lightweight data container for a single card:
- `card_name: String`
- `cost: int` — mana cost (1–7+)
- `description: String`

Instantiated at runtime by `GameManager._build_decks()`. Not saved to disk.

### GameEnums.gd
`class_name GameEnums`, extends `RefCounted`.

Shared enum definitions:
- `Phase { DRAW, PLAYER_ACTION, AI_ACTION }` — used by GameManager and CardDraw scene

## Usage Pattern
```gdscript
# Reference enums
GameEnums.Phase.DRAW

# Create card data
var card = CardData.new("Strike", 1, "A basic attack.")
```
