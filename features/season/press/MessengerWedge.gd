@tool
class_name MessengerWedge
extends Control

# Speech-bubble tail (`_draw` widget) — placed as a node in `UI_Comp_MessengerNpcBubble.tscn` /
# `UI_Comp_MessengerPlayerBubble.tscn`, next to the bubble it belongs to.
#
# The triangle fills this node's rect and points away from the bubble (`point_left` = the bubble
# is on the right, the tail points left at the speaker). Its base is pushed `OVERLAP` px into
# the bubble so it covers the bubble's edge (border) where they meet — the wedge's parent slot
# therefore draws above the bubble (`z_index` 1 in the scenes).
# The colour is the bubble's own fill (`bubble`'s `panel` stylebox), so a variation change in
# the theme recolours the tail too. `@tool` — the editor shows it.

const OVERLAP: float = 1.0

## The tail points left (bubble on its right) or right (bubble on its left).
@export var point_left: bool = true:
	set(v):
		point_left = v
		queue_redraw()

## The bubble this tail continues — its `panel` stylebox fill is the tail colour.
@export_node_path("Control") var bubble: NodePath:
	set(v):
		bubble = v
		queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var pts: PackedVector2Array
	if point_left:
		pts = PackedVector2Array([
			Vector2(w + OVERLAP, 0.0), Vector2(OVERLAP, h * 0.45), Vector2(w + OVERLAP, h)])
	else:
		pts = PackedVector2Array([
			Vector2(-OVERLAP, 0.0), Vector2(w - OVERLAP, h * 0.45), Vector2(-OVERLAP, h)])
	draw_colored_polygon(pts, _fill_color())


func _fill_color() -> Color:
	var b := get_node_or_null(bubble) as Control if not bubble.is_empty() else null
	if b != null:
		var sb := b.get_theme_stylebox(&"panel") as StyleBoxFlat
		if sb != null:
			return sb.bg_color
	return OutgameTheme.SURFACE
