class_name AwakeningCardCell
extends VBoxContainer

# One pilot card of the awakening screens and the ban/pick preset picker: the real hand
# card (`scenes/Card.tscn`, the same node the battle and the ban/pick sheet draw) inside a
# selectable frame, a transparent tap button over it and a caption line under it
# ("강화됨" for an upgraded "+" card, or any note the host sets).
#
# **Layout lives in `UI_Comp_AwakeningCardCell.tscn`.** This script fills the card, scales it
# (`set_card_scale`) and switches the frame between `SelectableCard` / `SelectableCardOn`.

signal tapped(card_id: int)

const SCENE_PATH: String = "res://features/season/awakening/UI_Comp_AwakeningCardCell.tscn"

## Card shown in this cell (-1 = none).
var card_id: int = -1


static func create() -> AwakeningCardCell:
	return (load(SCENE_PATH) as PackedScene).instantiate() as AwakeningCardCell


func _ready() -> void:
	(%Hit as Button).pressed.connect(func() -> void: tapped.emit(card_id))
	if UiPreview.is_standalone(self):
		_fill_preview()


## Card size factor (1 = the 160×220 hand card). Call before or after `fill`.
func set_card_scale(k: float) -> void:
	(%CardSlot as Control).custom_minimum_size = Vector2(Card.CARD_W, Card.CARD_H) * k
	(%Card as Control).scale = Vector2(k, k)


## Shows cards.csv row `id` — call once the cell is in the tree (`Card.gd` binds its
## children in `@onready`). An upgraded "+" card gets the "강화됨" caption.
func fill(id: int) -> void:
	card_id = id
	var gm: Node = get_node_or_null("/root/GameManager")
	var def: Dictionary = gm.card_def(id) if gm != null else {}
	if def.is_empty():
		return
	(%Card as Card).setup(CardData.from_def(def), false, true)
	set_caption(Loc.t(L.AWAKENING_UPGRADE_DONE) if PilotLoadout.is_upgraded(id) else "",
			&"AccentLabel")


## Caption under the card ("" hides it but keeps its line, so rows stay aligned).
func set_caption(text: String, variation: StringName = &"CaptionLabel") -> void:
	var lb: Label = %Caption
	lb.text = text
	lb.theme_type_variation = variation


func set_selected(on: bool) -> void:
	(%Frame as PanelContainer).theme_type_variation = &"SelectableCardOn" if on else &"SelectableCard"


## A cell that cannot be picked: faded, taps ignored.
func set_locked(on: bool) -> void:
	modulate = Color(1, 1, 1, 0.45) if on else Color.WHITE
	(%Hit as Button).disabled = on


## F6 단독 실행 미리보기 — 강화된 [교전 개시+] 한 장, 선택된 모양.
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(tapped)
	set_card_scale(1.0)
	fill(101)
	set_selected(true)
