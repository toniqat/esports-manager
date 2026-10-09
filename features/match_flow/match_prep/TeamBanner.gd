class_name TeamBanner
extends Control

# A team's banner behind one row of PREP pilot cards, borderless. Draws the team's banner image
# (`texture` = `TeamLogos.banner`: main-colour field, sub-colour stripes / edge bands, faint logo
# watermark) scaled to cover the rect, cropping the overflow (keeps its aspect, centred). Without
# an image it falls back to a procedural band in `color` (`TeamLogos.color`): lighter horizontal
# stripes every `STRIPE_PITCH` px and a darker band along the top and bottom edge.
# A `_draw` widget placed as a node in `UI_View_MatchPrepView.tscn` (it fills its parent
# MarginContainer, under the cards); `MatchPrepView` sets `texture` and `color`.

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


## Banner image (null = the procedural fallback in `color`).
@export var texture: Texture2D = null:
	set(v):
		texture = v
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	if texture != null:
		_draw_cover(w, h)
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


## The image scaled to cover `w` × `h` (aspect kept, centred, overflow cropped via the source region).
func _draw_cover(w: float, h: float) -> void:
	var ts: Vector2 = texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	var k: float = maxf(w / ts.x, h / ts.y)
	var src := Vector2(w / k, h / k)
	draw_texture_rect_region(texture, Rect2(0.0, 0.0, w, h), Rect2((ts - src) * 0.5, src))
