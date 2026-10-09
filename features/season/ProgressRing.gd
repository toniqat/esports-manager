@tool
class_name ProgressRing
extends Control

# Radial progress ring drawn around a pilot portrait (`SeasonPilotCard`): a full track circle,
# then an arc from 12 o'clock clockwise for `ratio` (the card: the pilot's 깨달음 level EXP
# bar, `TrainingLevel.progress`). An optional **change segment** `seg_from` → `seg_to` (0..1)
# is drawn on top in `seg_color` (week screen: the day's level EXP in a lighter tone, the same
# look as `GaugeRing`). Placed as a node in the card scene (a `_draw` widget); the scene sets
# its size and `width`, the card script sets the ratios and colours. The ring sits on the
# node's edge, so the portrait slot goes inside it, inset by `width` + a small gap.

const _SEGMENTS: int = 64

## Stroke thickness (px).
@export var width: float = 8.0:
	set(v):
		width = v
		queue_redraw()
## Filled share, 0..1.
@export_range(0.0, 1.0) var ratio: float = 0.4:
	set(v):
		ratio = clampf(v, 0.0, 1.0)
		queue_redraw()
## Arc colour (the track uses `OutgameTheme.SURFACE_SUNK`).
@export var color: Color = OutgameTheme.ACCENT:
	set(v):
		color = v
		queue_redraw()
## Change segment start / end (0..1); equal = no segment.
@export_range(0.0, 1.0) var seg_from: float = 0.0:
	set(v):
		seg_from = clampf(v, 0.0, 1.0)
		queue_redraw()
@export_range(0.0, 1.0) var seg_to: float = 0.0:
	set(v):
		seg_to = clampf(v, 0.0, 1.0)
		queue_redraw()
@export var seg_color: Color = Color.WHITE:
	set(v):
		seg_color = v
		queue_redraw()


func _draw() -> void:
	var d: float = minf(size.x, size.y)
	var centre: Vector2 = size * 0.5
	var r: float = d * 0.5 - width * 0.5
	if r <= 0.0:
		return
	draw_arc(centre, r, 0.0, TAU, _SEGMENTS, OutgameTheme.SURFACE_SUNK, width, true)
	_arc(centre, r, 0.0, ratio, color)
	_arc(centre, r, minf(seg_from, seg_to), maxf(seg_from, seg_to), seg_color)


## Arc from `a` to `b` (shares of the ring, 0 = 12 o'clock, clockwise); nothing when b <= a.
func _arc(centre: Vector2, r: float, a: float, b: float, col: Color) -> void:
	if b <= a:
		return
	var start: float = -PI * 0.5
	draw_arc(centre, r, start + TAU * a, start + TAU * b,
			maxi(4, int(_SEGMENTS * (b - a))), col, width, true)
