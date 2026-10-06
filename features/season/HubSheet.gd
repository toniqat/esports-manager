class_name HubSheet
extends CanvasLayer

# The **shared detail sheet** opened by the hub manage cards (staff · mech research · finance).
# Dims the whole screen and shows one white card inside the safe area (title · vertically
# scrolling body · bottom `닫기`). Same pattern as `meta/lobby/ConfirmPopup.gd` — being a
# CanvasLayer its coordinates are viewport-based (`docs/mobile_safe_area.md` pattern C)
# and the card sits inside the safe area.
#
# Usage (each panel's `open(host)`):
#   var sheet := HubSheet.open_on(host, "스태프")
#   var body: Control = sheet.body          # width = sheet.body_w(), place children absolutely
#   ... add children to body ...
#   sheet.set_body_height(y)                # scroll height
#   sheet.closed.connect(...)               # on close
#
# `HubView` already connects `closed` to its `refresh()`, so panels that change state
# inside the sheet don't need to call the hub themselves.

signal closed

const OVERLAY_LAYER: int = 18
const DIM_COLOR := Color(0.11, 0.11, 0.18, 0.58)
const SIDE_MARGIN: float = 36.0
const TOP_MARGIN: float = 60.0
const PAD: float = 40.0
const TITLE_H: float = 56.0
const BTN_H: float = 112.0

var body: Control = null
var _root: Control = null
var _card: Panel = null
var _card_w: float = 0.0


func _init() -> void:
	layer = OVERLAY_LAYER


## Opens a sheet under `host` and returns it.
static func open_on(host: Node, title: String) -> HubSheet:
	var sheet := HubSheet.new()
	host.add_child(sheet)
	sheet._build(title)
	return sheet


## Body width (inside the scroll).
func body_w() -> float:
	return _card_w - PAD * 2.0


## Tells the scroll how tall the body is.
func set_body_height(h: float) -> void:
	if body != null:
		body.custom_minimum_size.y = h


## The card itself, for callers that need fixed controls outside the scroll
## (card-local coordinates). Callers create those controls.
func card() -> Panel:
	return _card


func close() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	closed.emit()
	queue_free()


func _build(title: String) -> void:
	var vp: Vector2 = ScreenMetrics.viewport_size()
	_root = Control.new()
	_root.position = Vector2.ZERO
	_root.size = vp
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# The dim eats input so nothing leaks to the hub behind. Tapping empty space closes.
	var dim := Button.new()
	dim.flat = true
	dim.focus_mode = Control.FOCUS_NONE
	dim.position = Vector2.ZERO
	dim.size = vp
	dim.pressed.connect(close)
	_root.add_child(dim)
	var dim_rect := ColorRect.new()
	dim_rect.color = DIM_COLOR
	dim_rect.position = Vector2.ZERO
	dim_rect.size = vp
	dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim_rect)

	var top: float = ScreenMetrics.top_y() + TOP_MARGIN
	var bottom: float = ScreenMetrics.bottom_y() - 24.0
	_card_w = minf(vp.x - SIDE_MARGIN * 2.0, 1008.0)
	var card_h: float = bottom - top
	_card = OutgameTheme.add_card(_root,
			Vector2(ScreenMetrics.center_x() - _card_w * 0.5, top),
			Vector2(_card_w, card_h), 24)
	# A press on the card must not fall through to the dim and close the sheet.
	_card.mouse_filter = Control.MOUSE_FILTER_STOP

	UiHelpers.mk_label(_card, title, 40, OutgameTheme.TEXT,
			Vector2(PAD, PAD - 6.0), Vector2(body_w(), TITLE_H))
	OutgameTheme.add_divider(_card, Vector2(PAD, PAD + TITLE_H + 8.0), body_w())

	var scroll_top: float = PAD + TITLE_H + 24.0
	var scroll_h: float = card_h - scroll_top - BTN_H - PAD - 20.0
	var vs: Dictionary = OutgameTheme.add_vscroll(_card, Vector2(PAD, scroll_top),
			Vector2(body_w(), scroll_h))
	body = vs["body"]

	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.focus_mode = Control.FOCUS_NONE
	OutgameTheme.style_ghost_button(close_btn, 30)
	close_btn.position = Vector2(PAD, card_h - PAD - BTN_H)
	close_btn.size = Vector2(body_w(), BTN_H)
	close_btn.pressed.connect(close)
	_card.add_child(close_btn)
