class_name TeamBanner
extends Control

# A team's banner behind one row of PREP pilot cards — a square, borderless band in the team's
# signature colour (`TeamLogos.color`) with thin lighter horizontal stripes every `STRIPE_PITCH`
# px and a slightly darker band along the top and bottom edge, so the two sides read apart at a
# glance. A `_draw` widget placed as a node in `UI_View_MatchPrepView.tscn` (it fills its parent
# MarginContainer, under the cards); `MatchPrepView` sets `color`.

## Distance between two stripe lines and their thickness (px).
const STRIPE_PITCH: float = 12.0
const STRIPE_W: float = 3.0
## How much lighter the stripes are / darker the edge bands (`Color.lightened` / `darkened`).
const STRIPE_LIGHTEN: float = 0.14
const EDGE_DARKEN: float = 0.12
const EDGE_H: float = 10.0

## Banner colour (the team's signature colour).
@export var color: Color = Color("#2F6FD6"):
	set(v):
		color = v
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	draw_rect(Rect2(0.0, 0.0, w, h), color)
	var edge: Color = color.darkened(EDGE_DARKEN)
	draw_rect(Rect2(0.0, 0.0, w, EDGE_H), edge)
	draw_rect(Rect2(0.0, h - EDGE_H, w, EDGE_H), edge)
	var stripe: Color = color.lightened(STRIPE_LIGHTEN)
	var y: float = EDGE_H + STRIPE_PITCH * 0.5
	while y + STRIPE_W <= h - EDGE_H:
		draw_rect(Rect2(0.0, y, w, STRIPE_W), stripe)
		y += STRIPE_PITCH
