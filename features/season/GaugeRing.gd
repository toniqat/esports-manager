@tool
class_name GaugeRing
extends Control

# Half-ring gauge of one `PilotGauge` flag (a `_draw` widget placed as a node in
# `UI_Comp_PilotGauge.tscn`): only the **bottom half** of a circle — a track from 9 o'clock down
# through 6 to 3 o'clock, filled **left → right** for `ratio`, then a second pass for
# `over_ratio` drawn **on top** in `over_color` (stress above 100 = a full first pass + the
# overflow pass on the same half arc). An optional **change segment** `seg_from` → `seg_to`
# (in lap units 0..2: 0..1 = first pass, 1..2 = second pass) is drawn over each pass in
# `seg_color` / `seg_over_color` — "today's change" (lighter tone for a rise, a faint ghost for
# the part a fall removed). The circle is as wide as the node and its lowest point touches the
# node's bottom (`centre()`), so the icon sits in the bowl. The scene sets size and `width`,
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


## Circle centre in local coordinates: as wide as the node, lowest point on its bottom edge.
func centre() -> Vector2:
	return Vector2(size.x * 0.5, size.y - size.x * 0.5)


func _radius() -> float:
	return size.x * 0.5 - width * 0.5


func _draw() -> void:
	var r: float = _radius()
	if r <= 0.0:
		return
	var c: Vector2 = centre()
	var lo: float = minf(seg_from, seg_to)
	var hi: float = maxf(seg_from, seg_to)
	_arc(c, r, 0.0, 1.0, track_color)
	_arc(c, r, 0.0, ratio, color)
	_arc(c, r, clampf(lo, 0.0, 1.0), clampf(hi, 0.0, 1.0), seg_color)
	_arc(c, r, 0.0, over_ratio, over_color)
	_arc(c, r, clampf(lo - 1.0, 0.0, 1.0), clampf(hi - 1.0, 0.0, 1.0), seg_over_color)


## Arc from `a` to `b` (shares of the half ring, 0 = 9 o'clock, 1 = 3 o'clock, through the
## bottom); nothing when b <= a. Angles run PI → 0 (y points down, so PI / 2 is the bottom).
func _arc(c: Vector2, r: float, a: float, b: float, col: Color) -> void:
	if b <= a:
		return
	draw_arc(c, r, PI - PI * a, PI - PI * b, maxi(4, int(_SEGMENTS * (b - a))), col, width, true)
