class_name BanPickPilotDot
extends Control

# Small round pilot badge on a ban/pick grid cell (`BanPickMechCell`): a tight crop of the
# face — the middle of the eye band (`PilotImages.eye_for`, 480×200), so an eye reads even at
# ~32px — inside a ring. A `_draw` widget placed as nodes in the cell scene; the scene sets the
# size (diameter = the shorter side), the cell sets the pilot and the look (`show_pilot`).
# Highlight = ring colour / width + full opacity, data from `BanPickController`.

const _SEGMENTS: int = 32
## Part of the eye band shown in the circle, in UV (0..1) — about a 163×160 px square around
## the band's centre (between / on the eyes).
const EYE_UV := Rect2(0.33, 0.1, 0.34, 0.8)
## Opacity of a badge that is not highlighted.
const DIM_ALPHA: float = 0.7

var _tex: Texture2D = null
var _ring: Color = OutgameTheme.BORDER
var _ring_w: float = 2.0


## Shows `pilot_id`'s face. `focus` = highlighted (accent ring, full opacity); otherwise a
## thin `side_col` ring, dimmed.
func show_pilot(pilot_id: int, side_col: Color, focus: bool) -> void:
	_tex = PilotImages.eye_for(pilot_id)
	_ring = OutgameTheme.ACCENT if focus else side_col
	_ring_w = 3.0 if focus else 2.0
	modulate.a = 1.0 if focus else DIM_ALPHA
	queue_redraw()


func _draw() -> void:
	var d: float = minf(size.x, size.y)
	if d <= 0.0:
		return
	var r: float = d * 0.5
	var centre: Vector2 = size * 0.5
	draw_circle(centre, r, OutgameTheme.SURFACE_SUNK)
	if _tex != null:
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in _SEGMENTS:
			var a: float = TAU * float(i) / float(_SEGMENTS)
			var off := Vector2(cos(a), sin(a))
			pts.append(centre + off * r)
			uvs.append(EYE_UV.position + (off * 0.5 + Vector2(0.5, 0.5)) * EYE_UV.size)
		draw_colored_polygon(pts, Color(1, 1, 1), uvs, _tex)
	draw_arc(centre, r - _ring_w * 0.5, 0.0, TAU, _SEGMENTS, _ring, _ring_w, true)
