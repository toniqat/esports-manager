@tool
class_name BaseMapBuilding
extends Polygon2D

# ── One building of a base map, for the time-of-day lighting (`BaseMapLighting`) ──
# The polygon is the building's **roof** (its top face as seen on the art, map-local
# through this node's transform + `offset`); `height` is how many screen pixels the
# walls hang down from the roof edge to the ground. Everything else is derived:
#   * walls  = one quad per roof edge that faces down on screen (the visible sides),
#              edge → edge + (0, height); their light normal comes from the edge's
#              direction on the ground (`BaseMapLighting.wall_normal`)
#   * footprint = the roof moved down by `height` (the ground outline the shadow starts from)
# Drag the polygon's points in the editor (Polygon2D point editing) and set `height`;
# the editor draws the derived walls (blue) and the footprint (dashed) over the art.
# Tall parts of one building (a tower on a wing) are separate nodes.
# Overlaps follow the scene order: a later sibling is drawn over an earlier one (here in the
# editor and in the lighting's normal view), so put buildings in front further down.

const _EDITOR_WALL: Color = Color(0.25, 0.55, 1.0, 0.28)
const _EDITOR_EDGE: Color = Color(0.1, 0.3, 0.9, 0.9)
const _EDITOR_FOOT: Color = Color(1.0, 0.85, 0.1, 0.9)

## Screen pixels from the roof edge down to the ground (wall height on the art).
@export_range(0.0, 400.0, 1.0) var height: float = 40.0:
	set(v):
		height = v
		queue_redraw()


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_local_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		queue_redraw()


## Roof outline in this node's local space (`polygon` + `offset`), wound so its signed
## area is positive (outward edge normal of edge e = (e.y, −e.x)).
func _local_roof() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in polygon:
		pts.append(p + offset)
	if _signed_area(pts) < 0.0:
		pts.reverse()
	return pts


## Roof outline in the parent's space (the map, when `Buildings` sits at the origin).
func roof() -> PackedVector2Array:
	return transform * _local_roof()


## Ground outline: the roof moved down by `height`, in the parent's space.
func footprint() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in roof():
		out.append(p + Vector2(0.0, height))
	return out


## Visible walls in the parent's space: `[{poly: PackedVector2Array, edge: Vector2,
## out: Vector2}]` — `edge` = the roof edge's screen direction, `out` = its outward
## screen normal (pointing down for every visible wall).
func walls() -> Array:
	return _walls_of(roof())


func _walls_of(pts: PackedVector2Array) -> Array:
	var out: Array = []
	if pts.size() < 3:
		return out
	var drop := Vector2(0.0, height)
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		var e: Vector2 = b - a
		if e.length() < 0.5:
			continue
		var n: Vector2 = Vector2(e.y, -e.x).normalized()
		if n.y <= 0.02:
			continue  # faces up / sideways on screen: hidden behind the roof
		out.append({"poly": PackedVector2Array([a, b, b + drop, a + drop]), "edge": e, "out": n})
	return out


## Ground shadow for a sun whose shadow moves `per_px` screen pixels per pixel of
## height: the convex hull of the footprint and the footprint pushed out to the roof
## height's shadow tip. Parent space. Empty when the sun is down.
func shadow(per_px: Vector2) -> PackedVector2Array:
	var foot: PackedVector2Array = footprint()
	if foot.size() < 3 or per_px == Vector2.ZERO:
		return PackedVector2Array()
	var pts := PackedVector2Array(foot)
	var tip: Vector2 = per_px * height
	for p in foot:
		pts.append(p + tip)
	var hull: PackedVector2Array = Geometry2D.convex_hull(pts)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	return hull


static func _signed_area(pts: PackedVector2Array) -> float:
	var a: float = 0.0
	for i in pts.size():
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[(i + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


# ── Editor preview ───────────────────────────────────────────────────────────
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var pts: PackedVector2Array = _local_roof()
	if pts.size() < 3:
		return
	for w in _walls_of(pts):
		var poly: PackedVector2Array = w["poly"]
		draw_colored_polygon(poly, _EDITOR_WALL)
		var loop := PackedVector2Array(poly)
		loop.append(poly[0])
		draw_polyline(loop, _EDITOR_EDGE, 1.5)
	var drop := Vector2(0.0, height)
	for i in pts.size():
		draw_dashed_line(pts[i] + drop, pts[(i + 1) % pts.size()] + drop, _EDITOR_FOOT, 1.5, 5.0)
