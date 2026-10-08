@tool
class_name TrustRing
extends Control

# Radial progress ring drawn around a pilot portrait (`SeasonPilotCard`): a full track circle,
# then an arc from 12 o'clock clockwise for `ratio` (trust / TRUST_MAX). Placed as a node in the
# card scene (a `_draw` widget); the scene sets its size and `width`, the card script sets
# `ratio` and `color` (trust band colour, `HubView.trust_color`). The ring sits on the node's
# edge, so the portrait slot goes inside it, inset by `width` + a small gap.

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


func _draw() -> void:
	var d: float = minf(size.x, size.y)
	var centre: Vector2 = size * 0.5
	var r: float = d * 0.5 - width * 0.5
	if r <= 0.0:
		return
	draw_arc(centre, r, 0.0, TAU, _SEGMENTS, OutgameTheme.SURFACE_SUNK, width, true)
	if ratio <= 0.0:
		return
	var start: float = -PI * 0.5
	var points: int = maxi(4, int(_SEGMENTS * ratio))
	draw_arc(centre, r, start, start + TAU * ratio, points, color, width, true)
