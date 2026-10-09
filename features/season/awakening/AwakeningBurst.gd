@tool
class_name AwakeningBurst
extends Control

# Awakening intro FX (`_draw` widget placed as a node in `UI_View_Awakening.tscn`): amber
# rays turning slowly around a point, a glow and a ring that expands once. `progress`
# (0 → 1, tweened by `AwakeningView`) drives the ring and the fade-in; `spin` turns the
# rays. Draws nothing at progress 0.

## Centre of the burst as a fraction of this node's size.
@export var center_ratio: Vector2 = Vector2(0.5, 0.33)
@export var ray_count: int = 18
@export var color: Color = OutgameTheme.ACCENT

var progress: float = 0.0:
	set(v):
		progress = v
		queue_redraw()
var spin: float = 0.0:
	set(v):
		spin = v
		queue_redraw()


func _process(delta: float) -> void:
	if progress > 0.0 and is_visible_in_tree():
		spin = fmod(spin + delta * 0.25, TAU)


func _draw() -> void:
	if progress <= 0.0:
		return
	var c: Vector2 = size * center_ratio
	var reach: float = size.length() * 0.6
	var a: float = clampf(progress * 1.6, 0.0, 1.0)
	# rays — thin wedges, every other one fainter
	for i in ray_count:
		var ang: float = spin + TAU * float(i) / float(ray_count)
		var half: float = TAU / float(ray_count) * 0.18
		var alpha: float = (0.22 if i % 2 == 0 else 0.11) * a
		var pts := PackedVector2Array([c,
				c + Vector2.from_angle(ang - half) * reach,
				c + Vector2.from_angle(ang + half) * reach])
		var cols := PackedColorArray([Color(color, alpha), Color(color, 0.0), Color(color, 0.0)])
		draw_polygon(pts, cols)
	# glow
	for k in 6:
		var r: float = lerpf(60.0, 260.0, float(k) / 5.0) * (0.6 + 0.4 * a)
		draw_circle(c, r, Color(color, 0.07 * a))
	# expanding ring (once, fades out)
	var ring_t: float = clampf(progress, 0.0, 1.0)
	var ring_r: float = lerpf(120.0, 640.0, ring_t)
	draw_arc(c, ring_r, 0.0, TAU, 96, Color(color, 0.8 * (1.0 - ring_t)), 6.0, true)
