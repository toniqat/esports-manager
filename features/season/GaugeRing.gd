@tool
class_name GaugeRing
extends Control

# Radial progress ring of one `PilotGauge` (a `_draw` widget placed as a node in
# `UI_Comp_PilotGauge.tscn`): a full track circle, an arc from 12 o'clock clockwise for
# `ratio`, then a second-lap arc for `over_ratio` drawn **on top** in `over_color` (stress
# above 100 = a full first lap + the overflow lap). An optional **change segment**
# `seg_from` → `seg_to` (in lap units 0..2: 0..1 = first lap, 1..2 = second lap) is drawn
# over each lap in `seg_color` / `seg_over_color` — the stress gauge's "today's change"
# (lighter tone for a rise, a faint ghost for the part a fall removed). The scene sets its
# size and `width`, `PilotGauge` sets the ratios and colours (data colours).

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
## Change segment start / end in lap units (0..2); equal = no segment.
@export_range(0.0, 2.0) var seg_from: float = 0.0:
	set(v):
		seg_from = clampf(v, 0.0, 2.0)
		queue_redraw()
@export_range(0.0, 2.0) var seg_to: float = 0.0:
	set(v):
		seg_to = clampf(v, 0.0, 2.0)
		queue_redraw()
@export var color: Color = OutgameTheme.POSITIVE:
	set(v):
		color = v
		queue_redraw()
@export var over_color: Color = OutgameTheme.NEGATIVE:
	set(v):
		over_color = v
		queue_redraw()
## Change segment colour on the first / second lap.
@export var seg_color: Color = Color.WHITE:
	set(v):
		seg_color = v
		queue_redraw()
@export var seg_over_color: Color = Color.WHITE:
	set(v):
		seg_over_color = v
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
	var lo: float = minf(seg_from, seg_to)
	var hi: float = maxf(seg_from, seg_to)
	draw_arc(centre, r, 0.0, TAU, _SEGMENTS, track_color, width, true)
	_arc(centre, r, 0.0, ratio, color)
	_arc(centre, r, clampf(lo, 0.0, 1.0), clampf(hi, 0.0, 1.0), seg_color)
	_arc(centre, r, 0.0, over_ratio, over_color)
	_arc(centre, r, clampf(lo - 1.0, 0.0, 1.0), clampf(hi - 1.0, 0.0, 1.0), seg_over_color)


## Arc from `a` to `b` (shares of a lap, 0 = 12 o'clock, clockwise); nothing when b <= a.
func _arc(centre: Vector2, r: float, a: float, b: float, col: Color) -> void:
	if b <= a:
		return
	var start: float = -PI * 0.5
	draw_arc(centre, r, start + TAU * a, start + TAU * b,
			maxi(4, int(_SEGMENTS * (b - a))), col, width, true)
