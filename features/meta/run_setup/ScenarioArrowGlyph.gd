@tool
class_name ScenarioArrowGlyph
extends Control

# `_draw` widget: one chevron (‹ or ›) centred in its rect, round caps. Placed inside the plate-less
# league arrow buttons of `ScenarioSelectView` (white; dims while the button is held; an arrow with
# no league behind it is hidden by the view).

## true = points right (›), false = left (‹).
@export var point_right: bool = true:
	set(v):
		point_right = v
		queue_redraw()
@export var stroke: float = 7.0:
	set(v):
		stroke = v
		queue_redraw()
@export var color: Color = Color.WHITE:
	set(v):
		color = v
		queue_redraw()
@export var shadow_color: Color = Color(0, 0, 0, 0.45):
	set(v):
		shadow_color = v
		queue_redraw()

const SHADOW_OFFSET := Vector2(0.0, 3.0)


func _ready() -> void:
	resized.connect(queue_redraw)
	# The button has no plate, so the glyph itself shows the press.
	var b := get_parent() as BaseButton
	if b != null and not Engine.is_editor_hint():
		b.button_down.connect(func() -> void: modulate.a = 0.5)
		b.button_up.connect(func() -> void: modulate.a = 1.0)


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var hw: float = minf(size.x, size.y) * 0.22    # half depth of the chevron
	var hh: float = minf(size.x, size.y) * 0.40    # half height
	var d: float = 1.0 if point_right else -1.0
	var pts := PackedVector2Array([
		c + Vector2(-hw * d, -hh), c + Vector2(hw * d, 0.0), c + Vector2(-hw * d, hh)])
	# Soft dark shadow under the stroke — the glyph has no plate and often sits over bright art.
	var sh := PackedVector2Array()
	for p in pts:
		sh.append(p + SHADOW_OFFSET)
	draw_polyline(sh, shadow_color, stroke + 4.0, true)
	draw_polyline(pts, color, stroke, true)
	for p in pts:
		draw_circle(p, stroke * 0.5, color, true, -1.0, true)
