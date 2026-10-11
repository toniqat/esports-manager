@tool
class_name PilotFlag
extends Control

# The pennant behind one `PilotGauge` (a `_draw` widget placed as a node in
# `UI_Comp_PilotGauge.tscn`, full rect, under the gauge's contents): a tall pentagon — a
# rectangle whose bottom `point_h` px narrow to a point at the bottom centre. White field, thin
# border and a soft drop shadow (the card's shared look, `OutgameTheme` tokens); the top edge
# tucks under the portrait plate of `SeasonPilotCard`, so the flag seems to hang from it.

## Height of the pointed part at the bottom (px).
@export var point_h: float = 12.0:
	set(v):
		point_h = v
		queue_redraw()
@export var fill: Color = OutgameTheme.SURFACE:
	set(v):
		fill = v
		queue_redraw()
@export var border: Color = OutgameTheme.BORDER_STRONG:
	set(v):
		border = v
		queue_redraw()
@export var border_w: float = 1.5:
	set(v):
		border_w = v
		queue_redraw()
## Drop shadow offset (px); colour `OutgameTheme.SHADOW`.
@export var shadow_offset: Vector2 = Vector2(0, 3):
	set(v):
		shadow_offset = v
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


## The pentagon's corners, clockwise from the top left.
func outline() -> PackedVector2Array:
	var w: float = size.x
	var h: float = size.y
	var p: float = clampf(point_h, 0.0, h)
	return PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h - p),
			Vector2(w * 0.5, h), Vector2(0, h - p)])


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var pts: PackedVector2Array = outline()
	var shadow := PackedVector2Array()
	for q in pts:
		shadow.append(q + shadow_offset)
	draw_colored_polygon(shadow, OutgameTheme.SHADOW)
	draw_colored_polygon(pts, fill)
	if border_w > 0.0:
		var ring: PackedVector2Array = pts.duplicate()
		ring.append(pts[0])
		draw_polyline(ring, border, border_w, true)
