@tool
class_name GaugeRing
extends Control

# Radial progress ring of one `PilotGauge` panel (a `_draw` widget placed as a node in
# `UI_Comp_PilotGauge.tscn`): a full track circle, an arc from 12 o'clock clockwise for
# `ratio`, then a second-lap arc for `over_ratio` drawn **on top** in `over_color` (stress
# above 100 = a full first lap + the overflow lap). The scene sets its size and `width`,
# `PilotGauge` sets the ratios and colours (data colours).

const _SEGMENTS: int = 64

## Stroke thickness (px).
@export var width: float = 5.0:
	set(v):
		width = v
		queue_redraw()
## First lap, 0..1.
@export_range(0.0, 1.0) var ratio: float = 0.6:
	set(v):
		ratio = clampf(v, 0.0, 1.0)
		queue_redraw()
## Second lap drawn over the first, 0..1 (0 = none).
@export_range(0.0, 1.0) var over_ratio: float = 0.0:
	set(v):
		over_ratio = clampf(v, 0.0, 1.0)
		queue_redraw()
@export var color: Color = OutgameTheme.POSITIVE:
	set(v):
		color = v
		queue_redraw()
@export var over_color: Color = OutgameTheme.NEGATIVE:
	set(v):
		over_color = v
		queue_redraw()
@export var track_color: Color = OutgameTheme.SURFACE_SUNK:
	set(v):
		track_color = v
		queue_redraw()


func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.5 - width * 0.5
	if r <= 0.0:
		return
	var centre: Vector2 = size * 0.5
	draw_arc(centre, r, 0.0, TAU, _SEGMENTS, track_color, width, true)
	_lap(centre, r, ratio, color)
	_lap(centre, r, over_ratio, over_color)


func _lap(centre: Vector2, r: float, share: float, col: Color) -> void:
	if share <= 0.0:
		return
	var start: float = -PI * 0.5
	draw_arc(centre, r, start, start + TAU * share, maxi(4, int(_SEGMENTS * share)), col, width, true)
