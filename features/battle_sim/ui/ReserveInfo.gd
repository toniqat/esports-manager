class_name ReserveInfo
extends CanvasLayer

## 예약 칩 설명 판 — tapping a reservation chip (`ReservationChips`) opens this beside the
## chip: a plate listing what that card reserved (one line per effect, `hud.reserve.*`)
## and, under it, the card's own description box (`CardDescBox`, same look as the hand).
## Any press outside the column closes it; that press is left unhandled so whatever was
## touched still reacts. Presses on a chip are left to `ReservationChips` (it toggles).
##
## Scene: `UI_View_ReserveInfo.tscn` (layer, plate, title). Code: lines text, the card
## box (code widget) in `%DescSlot`, position next to the chip.

const SCENE_PATH := "res://features/battle_sim/ui/UI_View_ReserveInfo.tscn"
## Column width — plate and card description box.
const WIDTH := 420.0
## Gap between the chip's right edge and the column.
const CHIP_GAP := 14.0
const SCREEN_MARGIN := 16.0

## `func(pos: Vector2) -> bool` — true when `pos` is on a chip (the chips own that press).
var is_on_anchor: Callable = Callable()

var _root: Control = null
var _column: VBoxContainer = null
var _lines: Label = null
var _desc_slot: Control = null
var _key: String = ""
## 여닫을 때마다 오른다 — 한 프레임 기다리는 배치가 그새 다시 열린 판을 건드리지 않게.
var _open_gen: int = 0


static func create() -> ReserveInfo:
	return (load(SCENE_PATH) as PackedScene).instantiate() as ReserveInfo


func _ready() -> void:
	_root = %Root as Control
	_column = %Column as VBoxContainer
	_lines = %Lines as Label
	_desc_slot = %DescSlot as Control
	visible = false
	if UiPreview.is_standalone(self):
		_fill_preview()


func is_open() -> bool:
	return visible


## Key of the group shown (the chip's card uid) — "" when closed.
func shown_key() -> String:
	return _key if visible else ""


## Opens next to `anchor` (the chip rect, canvas coordinates). `card` may be null
## (source unknown) — then only the reserve lines show.
func open(key: String, lines: PackedStringArray, card: CardData, anchor: Rect2) -> void:
	_key = key
	_lines.text = "\n".join(lines)
	for c in _desc_slot.get_children():
		c.queue_free()
	_desc_slot.visible = card != null
	if card != null:
		var box: Panel = CardDescBox.build(card, WIDTH)
		_desc_slot.add_child(box)
		_desc_slot.custom_minimum_size = box.size
	visible = true
	_column.size = Vector2(WIDTH, 0.0)
	_column.position.x = anchor.end.x + CHIP_GAP
	# 줄바꿈 글(`%Lines`)의 높이는 폭이 정해진 다음 프레임에야 맞게 나온다 — 그 한
	# 프레임은 투명하게 두고 재서 놓는다.
	_column.modulate.a = 0.0
	_open_gen += 1
	var gen: int = _open_gen
	await get_tree().process_frame
	if gen != _open_gen or not visible:
		return
	_column.reset_size()
	_column.size.x = WIDTH
	_column.modulate.a = 1.0
	var h: float = _column.get_combined_minimum_size().y
	var vp: Vector2 = _root.get_viewport_rect().size
	var y: float = clampf(anchor.get_center().y - h * 0.5, SCREEN_MARGIN,
			maxf(SCREEN_MARGIN, vp.y - SCREEN_MARGIN - h))
	_column.position = Vector2(anchor.end.x + CHIP_GAP, y)


func close() -> void:
	visible = false
	_key = ""
	_open_gen += 1


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if PointerPress.state(event) != PointerPress.PRESS:
		return
	var pos: Vector2 = PointerPress.position_of(event)
	if is_on_anchor.is_valid() and bool(is_on_anchor.call(pos)):
		return
	if _column.get_global_rect().has_point(pos):
		get_viewport().set_input_as_handled()
		return
	close()


# ── F6 preview ───────────────────────────────────────────────────────────────

func _fill_preview() -> void:
	var lines := PackedStringArray([
		Loc.t(L.HUD_RESERVE_STRATEGY, {"n": "+3"}),
		Loc.t(L.HUD_RESERVE_DRAW, {"n": 3}),
	])
	var card: CardData = null
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		var def: Dictionary = gm.card_def(46)
		if not def.is_empty():
			card = CardData.from_def(def)
	open("preview", lines, card, Rect2(8.0, 900.0, 150.0, 44.0))
