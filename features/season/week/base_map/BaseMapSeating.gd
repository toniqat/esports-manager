class_name BaseMapSeating
extends RefCounted

# ── Base map marker seating + look (map only, not the battlefield's row rule) ──
# The base map shows only my own five pilots, so there are no team sides. A spot is one
# point; its pilots sit around it:
#   1 pilot  → straight above the point at `SINGLE_DIST` (the battlefield's first-row look),
#   2+       → a regular polygon centred on the point (2 = left / right, 3 = triangle,
#              4 = square, 5 = pentagon), seat 0 at the top (even counts: the top edge
#              is flat) and the rest clockwise in entry order. Radius = just enough that
#              neighbouring portraits keep `SEAT_GAP`, and at least `outer + MIN_TAIL` so
#              every tail stays visible (tails meet at the point).
# A layout that touches portraits / tails already placed (other spots) is rotated
# (`ROTATIONS_DEG`), then grown (`GROWS`); none clean = the plain layout anyway.
# Seats are clamped into the on-screen area. The look is outline-only: a thin outline
# (`OUTLINE_W`) around the portrait and a solid tail, both in the entry's `ring` colour.

## Outline around the portrait (no HP / team ring on the map).
const OUTLINE_W: float = PilotMarker.MARKER_OUTLINE_W
## Minimum gap between two portraits' outlines.
const SEAT_GAP: float = PilotMarker.MARKER_GAP
## Shortest tail left visible between a portrait's outline and its point (px).
const MIN_TAIL: float = 18.0
## A lone pilot's portrait centre above the point = the battlefield's first row
## (diameter + gap).
const SINGLE_DIST: float = PilotMarker.FIELD_RADIUS * 2.0 + PilotMarker.MARKER_GAP
## Layout rotations tried (degrees, clockwise), then radius growth factors.
const ROTATIONS_DEG: Array = [0.0, 15.0, -15.0, 30.0, -30.0, 45.0, -45.0]
const GROWS: Array = [1.0, 1.2, 1.45]


## Portrait radius → outermost drawn radius (portrait + outline).
static func outer_radius(draw_radius: float) -> float:
	return draw_radius + OUTLINE_W


## Distance from the point to each seat for a group of `n`.
static func seat_distance(n: int, r: float) -> float:
	if n <= 1:
		return SINGLE_DIST
	var outer: float = outer_radius(r)
	var chord: float = outer * 2.0 + SEAT_GAP
	return maxf(chord * 0.5 / sin(PI / float(n)), outer + MIN_TAIL)


## Seat offsets of a group of `n` at `dist`, rotated `rot` radians clockwise.
static func layout(n: int, dist: float, rot: float) -> Array:
	var out: Array = []
	var step: float = TAU / float(maxi(n, 1))
	var start: float = -PI * 0.5 + rot
	if n % 2 == 0:
		start -= step * 0.5   # flat top edge: 2 = left / right, 4 = square
	for k in n:
		var ang: float = start + step * float(k)
		out.append(Vector2(cos(ang), sin(ang)) * dist)
	return out


## Tail outline of a portrait at `centre` pointing at `ground` (tip on the point).
static func tail_outline(centre: Vector2, ground: Vector2, r: float, em: float = 1.0) -> PackedVector2Array:
	return PilotMarker.arrow_outline_polygon(centre, tail_aim(centre, ground, r), r, em)


## The tail aims past the point by the battlefield's tip inset, so its tip lands on it.
static func tail_aim(centre: Vector2, ground: Vector2, r: float) -> Vector2:
	var d: Vector2 = ground - centre
	if d.length() < 1.0:
		return ground
	return ground + d.normalized() * PilotMarker.tip_inset(r)


## Seat offsets (Vector2 from `center`, one per pilot in entry order) of a group of `n`,
## clamped into `area` (portrait centres). `discs` / `tails` = portrait centres and tail
## outlines already placed (other spots); the caller appends this group's afterwards.
static func pick_seats(center: Vector2, n: int, r: float, area: Rect2,
		discs: Array, tails: Array) -> Array:
	var base: float = seat_distance(n, r)
	var first: Array = []
	for raw_g in GROWS:
		for raw_rot in ROTATIONS_DEG:
			var seats: Array = _clamped(center, layout(n, base * float(raw_g),
					deg_to_rad(float(raw_rot))), area)
			if first.is_empty():
				first = seats
			if not _collides(center, seats, r, discs, tails):
				return seats
	return first


static func _clamped(center: Vector2, vecs: Array, area: Rect2) -> Array:
	var out: Array = []
	for raw in vecs:
		out.append((center + (raw as Vector2)).clamp(area.position, area.end) - center)
	return out


## The layout touches itself (after the clamp), a placed portrait or a placed tail, or
## one of its tails touches a placed portrait.
static func _collides(center: Vector2, vecs: Array, r: float, discs: Array, tails: Array) -> bool:
	var outer: float = outer_radius(r)
	var min_d: float = outer * 2.0 + SEAT_GAP * 0.5
	for i in vecs.size():
		var pos: Vector2 = center + (vecs[i] as Vector2)
		for j in i:
			if pos.distance_to(center + (vecs[j] as Vector2)) < min_d:
				return true
		for raw in discs:
			if pos.distance_to(raw as Vector2) < min_d:
				return true
		if PilotMarker.disc_hits_arrows(pos, outer, tails):
			return true
		var mine: PackedVector2Array = tail_outline(pos, center, r)
		if mine.is_empty():
			continue
		for raw in discs:
			if PilotMarker.point_polygon_distance(raw as Vector2, mine) < outer:
				return true
	return false
