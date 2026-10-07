class_name BanPickSheetCard
extends VBoxContainer

# One card of the bottom sheet's card row: the real hand card (`Card.tscn`, added by the
# controller into `slot` at `SHEET_CARD_SCALE`), a transparent tap button over it (opens the
# description box) and the count badge underneath (`×n` / `생성 전용`).
# Layout in `UI_Comp_BanPickSheetCard.tscn`; `BanPickController._build_card_row` fills it.

const SCENE_PATH: String = "res://features/match_flow/ban_pick/UI_Comp_BanPickSheetCard.tscn"

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
	if UiPreview.is_standalone(self):
		_fill_preview()


## Puts the card node under the tap button (the card itself ignores the mouse).
## Call `Card.setup` after this — its `@onready` refs resolve only inside the tree.
func hold_card(node: Control) -> void:
	slot.add_child(node)
	slot.move_child(node, 0)


## F6 단독 실행 미리보기 — Triumph 의 실제 메크 카드 `질주`(×2) 한 장. 채우는 법은
## `BanPickController._build_card_row` 와 같다(카드는 트리에 넣은 뒤 setup).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(hit.pressed, "sheet card tapped")
	var def: Dictionary = _preview_card_def(6, 2)
	if def.is_empty():
		return
	var node := (load("res://scenes/Card.tscn") as PackedScene).instantiate() as Card
	hold_card(node)
	node.setup(CardData.from_def(def), false, true)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.pivot_offset = Vector2.ZERO
	node.scale = Vector2(0.9, 0.9)
	node.position = Vector2.ZERO
	var cnt: int = int(def.get("count", 0))
	count.text = ("×%d" % cnt) if cnt > 0 else "생성 전용"


## 그 메크의 카드 표에서 `count == want_count` 인 첫 카드(없으면 첫 카드).
func _preview_card_def(mech_id: int, want_count: int) -> Dictionary:
	var gm: Node = get_node_or_null("/root/GameManager")
	var defs: Array = gm.mech_cards_for(mech_id) if gm != null else []
	for raw in defs:
		if int((raw as Dictionary).get("count", 0)) == want_count:
			return raw
	return defs[0] if not defs.is_empty() else {}
