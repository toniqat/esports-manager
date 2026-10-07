class_name BanPickSheetCard
extends VBoxContainer

# One card of the bottom sheet's card row: the real hand card (`Card.tscn`, added by the
# controller into `slot` at `SHEET_CARD_SCALE`), a transparent tap button over it (opens the
# description box) and the count badge underneath (`×n` / `생성 전용`).
# Layout in `BanPickSheetCard.tscn`; `BanPickController._build_card_row` fills it.

const SCENE_PATH: String = "res://features/match_flow/ban_pick/BanPickSheetCard.tscn"

var slot: Control = null
var hit: Button = null
var count: Label = null


## Instantiates the scene. `BanPickSheetCard.new()` is an empty box — don't use it.
static func create() -> BanPickSheetCard:
	return (load(SCENE_PATH) as PackedScene).instantiate() as BanPickSheetCard


func _ready() -> void:
	slot = %Slot
	hit = %Hit
	count = %Count


## Puts the card node under the tap button (the card itself ignores the mouse).
## Call `Card.setup` after this — its `@onready` refs resolve only inside the tree.
func hold_card(node: Control) -> void:
	slot.add_child(node)
	slot.move_child(node, 0)
