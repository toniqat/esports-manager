class_name PilotMarker
extends RefCounted

# ── Pilot marker: portrait disc + team ring + speech-bubble tail + soft shadow ──
# One look and one seating rule for every screen that stands pilot portraits on a
# point: the battlefield (`BattleRenderer`, one tile = one point) and the team base map
# (`BaseMap`, one spot = one point; it reuses only the tail / shadow helpers, its seating
# and outline-only look are `BaseMapSeating`). Static only — callers pass the CanvasItem that is
# drawing (inside its `_draw` / `draw` signal).
#
# Seating (`pick_row_seats`): the pilots of one point form a **block** sitting in a
# horizontal row `d = diameter + MARKER_GAP` below (v = +1) or above (v = −1) the point,
# `cap` per row (more = the next row out). A row that overlaps markers already placed
# shifts sideways by half a seat (0 → ½ → −½ → 1 → −1, towards `bias` first), then one
# row further out, up to `SLOT_RINGS` rows; nothing found = empty (the caller falls back).
# After all blocks are seated, `repair_arrow_overlaps` re-seats any row block whose
# portraits cover another block's tail (sideways only, never further out).
# Draw order across all markers of a screen: shadows → tails → portraits.

## Battlefield portrait radius (`BattleRenderer.PILOT_RADIUS_BASE` × `HexGrid.DISPLAY_SCALE`).
const FIELD_RADIUS: float = 31.5 * 1.35
## Ring thickness and the gap between portrait edge and ring.
const HP_RING_W := 8.0
const HP_RING_GAP := 1.0
## Thick black outline — the ring's outer edge and the tail's border share it.
const MARKER_OUTLINE_W := 5.0
## Ring divider every `HP_TICK_STEP` HP — half the outline width.
const HP_TICK_W := MARKER_OUTLINE_W * 0.5
const HP_TICK_STEP: int = 25
## Team colours (ring · tail).
const TEAM_RING_COLORS := [Color(0.2, 0.5, 0.9), Color(0.9, 0.2, 0.2)]
## Shield — appended to the ring like extra HP.
const SHIELD_RING_COLOR := Color(0.82, 0.83, 0.86)
const ARROW_WIDTH_SCALE := 0.9
## How far the sharp outline tip may run past the fill tip (px).
const ARROW_TIP_MITER_MAX := 10.0
const MARKER_SHADOW_OFFSET := Vector2(0.0, 8.0)
const MARKER_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.45)
## Shadow edge blur width (px) and layer count (stacked offset layers = gradient edge).
const MARKER_SHADOW_BLUR: float = 16.0
const MARKER_SHADOW_LAYERS: int = 7
## Minimum gap between portraits (px). Row spacing and the overlap test use the same value.
const MARKER_GAP := 6.0
## Rows tried outwards from the point.
const SLOT_RINGS := 3
## Portraits per row.
const ROW_CAP := 3

## Which part of the shadow to lay: a lifted portrait lays the tail part (TAIL, minus
## the disc) with the tails and its disc part (DISC) later with itself.
enum ShadowPart { FULL, TAIL, DISC }


## Portrait radius → outermost marker radius (the black outline outside the ring).
static func outer_radius(draw_radius: float) -> float:
	return draw_radius + HP_RING_GAP + HP_RING_W + MARKER_OUTLINE_W


static func alpha_mul(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * alpha)


static func circle_polygon(center: Vector2, r: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var ang: float = float(i) / float(n) * TAU
		out.append(center + Vector2(cos(ang), sin(ang)) * r)
	return out


static func close_polygon(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.is_empty():
		return pts
	var out := PackedVector2Array(pts)
	out.append(pts[0])
	return out


# ── Tail (speech-bubble arrow) ───────────────────────────────────────────────
## The tail's axis — `{dir, perp, apex_len, base_len, base_half}` (fill), empty when the
## portrait sits too close to the point. The tip always stops `tip_inset(radius)` short
## of `aim_point` (it never pokes past it).
static func arrow_axis(circle_pos: Vector2, aim_point: Vector2,
		radius: float, em: float) -> Dictionary:
	var to_tile := aim_point - circle_pos
	var dist: float = to_tile.length()
	if dist < 1.0:
		return {}
	var dir := to_tile / dist
	var draw_radius: float = radius * em
	var apex_len: float = dist - tip_inset(radius)
	if apex_len <= draw_radius * 0.75:
		return {}
	return {"dir": dir, "perp": Vector2(-dir.y, dir.x), "apex_len": apex_len,
			"base_len": draw_radius * 0.6,
			"base_half": clamp(radius * 0.9, 10.0, 18.0) * em * ARROW_WIDTH_SCALE}


## Distance the fill tip stops short of the aim point.
static func tip_inset(radius: float) -> float:
	return clamp(radius * 0.55, 10.0, 26.0)


## Tail fill — a sharp triangle; empty = no tail.
static func arrow_fill_polygon(circle_pos: Vector2, aim_point: Vector2,
		radius: float, em: float) -> PackedVector2Array:
	var ax := arrow_axis(circle_pos, aim_point, radius, em)
	if ax.is_empty():
		return PackedVector2Array()
	var dir: Vector2 = ax["dir"]
	var perp: Vector2 = ax["perp"]
	var half: float = float(ax["base_half"])
	var base := circle_pos + dir * float(ax["base_len"])
	return PackedVector2Array([
		circle_pos + dir * float(ax["apex_len"]),
		base + perp * half,
		base - perp * half,
	])


## Tail outline (black plate) — the fill grown by `MARKER_OUTLINE_W` with mitred corners
## (tip capped at `ARROW_TIP_MITER_MAX`). Shadows and the seat overlap tests use it.
static func arrow_outline_polygon(circle_pos: Vector2, aim_point: Vector2,
		radius: float, em: float) -> PackedVector2Array:
	var ax := arrow_axis(circle_pos, aim_point, radius, em)
	if ax.is_empty():
		return PackedVector2Array()
	var dir: Vector2 = ax["dir"]
	var perp: Vector2 = ax["perp"]
	var w: float = MARKER_OUTLINE_W
	var apex_len: float = float(ax["apex_len"])
	var base_len: float = float(ax["base_len"])
	var half: float = float(ax["base_half"])
	var half_ang: float = atan2(half, apex_len - base_len)
	var push: float = minf(w / maxf(sin(half_ang), 0.05), ARROW_TIP_MITER_MAX)
	var back_half: float = half * (apex_len - base_len + w) / (apex_len - base_len) \
			+ w / cos(half_ang)
	var base := circle_pos + dir * (base_len - w)
	return PackedVector2Array([
		circle_pos + dir * (apex_len + push),
		base + perp * back_half,
		base - perp * back_half,
	])


## Black outline triangle, then the team-colour fill.
static func draw_arrow(ci: CanvasItem, circle_pos: Vector2, aim_point: Vector2,
		radius: float, color: Color, alpha: float = 1.0, em: float = 1.0) -> void:
	var fill := arrow_fill_polygon(circle_pos, aim_point, radius, em)
	if fill.is_empty():
		return
	var outline := arrow_outline_polygon(circle_pos, aim_point, radius, em)
	var black := alpha_mul(Color(0.0, 0.0, 0.0), alpha)
	ci.draw_colored_polygon(outline, black)
	ci.draw_polyline(close_polygon(outline), black, 1.0, true)
	var fill_col := alpha_mul(color.darkened(0.1), alpha)
	ci.draw_colored_polygon(fill, fill_col)
	ci.draw_polyline(close_polygon(fill), fill_col, 1.0, true)


# ── Shadow ───────────────────────────────────────────────────────────────────
## Disc + tail silhouette as one shape, moved down and laid in `MARKER_SHADOW_LAYERS`
## blurred layers whose stack reaches `MARKER_SHADOW_COLOR.a` in the middle. `arrow` =
## the tail outline (`arrow_outline_polygon`, may be empty). `outer` > 0 overrides the
## disc silhouette radius (default `outer_radius(draw_radius)`; the base map's outline-only
## marker is smaller).
static func draw_shadow(ci: CanvasItem, pos: Vector2, draw_radius: float,
		arrow: PackedVector2Array, alpha: float = 1.0, part: ShadowPart = ShadowPart.FULL,
		outer: float = -1.0) -> void:
	var disc := circle_polygon(pos, outer if outer > 0.0 else outer_radius(draw_radius), 40)
	var shapes: Array = [disc]
	match part:
		ShadowPart.TAIL:
			shapes = [] if arrow.is_empty() else Geometry2D.clip_polygons(arrow, disc)
		ShadowPart.FULL:
			if not arrow.is_empty():
				shapes = Geometry2D.merge_polygons(disc, arrow)
	var disc_cw: bool = Geometry2D.is_polygon_clockwise(disc)
	var core_a: float = MARKER_SHADOW_COLOR.a * alpha
	var layer_a: float = 1.0 - pow(1.0 - core_a, 1.0 / float(MARKER_SHADOW_LAYERS))
	var col := Color(MARKER_SHADOW_COLOR.r, MARKER_SHADOW_COLOR.g,
			MARKER_SHADOW_COLOR.b, layer_a)
	for raw in shapes:
		var poly := raw as PackedVector2Array
		if Geometry2D.is_polygon_clockwise(poly) != disc_cw:
			continue   # a hole
		var moved := PackedVector2Array()
		for v in poly:
			moved.append(v + MARKER_SHADOW_OFFSET)
		for i in MARKER_SHADOW_LAYERS:
			var f: float = float(i) / float(MARKER_SHADOW_LAYERS - 1) - 0.5
			for layer in Geometry2D.offset_polygon(moved, f * MARKER_SHADOW_BLUR,
					Geometry2D.JOIN_ROUND):
				var lp := layer as PackedVector2Array
				if Geometry2D.is_polygon_clockwise(lp) != disc_cw:
					continue   # a hole of the offset
				ci.draw_colored_polygon(lp, col)


# ── Portrait disc + ring ─────────────────────────────────────────────────────
## Black backing disc (= the ring's outer outline), a white disc behind the portrait
## (some `*_circle.png` are transparent inside), the portrait (`fallback` colour without
## one). The ring is drawn by the caller (`draw_hp_ring`).
static func draw_disc(ci: CanvasItem, pos: Vector2, draw_radius: float, portrait: Texture2D,
		tint: Color, fallback: Color, alpha: float = 1.0) -> void:
	ci.draw_circle(pos, outer_radius(draw_radius),
			alpha_mul(Color(0.0, 0.0, 0.0), alpha), true, -1.0, true)
	ci.draw_circle(pos, maxf(1.0, draw_radius - 1.0), alpha_mul(tint, alpha))
	if portrait != null:
		var rect := Rect2(pos.x - draw_radius, pos.y - draw_radius,
				draw_radius * 2.0, draw_radius * 2.0)
		ci.draw_texture_rect(portrait, rect, false, alpha_mul(tint, alpha))
	else:
		ci.draw_circle(pos, draw_radius, alpha_mul(fallback, alpha))


## Ring turn = max(max HP, HP + shield).
static func hp_ring_span(hp: int, shield: int, max_hp: int) -> float:
	return float(maxi(maxi(max_hp, 1), hp + shield))


## Centre radius of the ring outside a portrait of `draw_radius`.
static func hp_ring_radius(draw_radius: float) -> float:
	return draw_radius + HP_RING_W * 0.5 + HP_RING_GAP


## Empty ring (dark) → HP (team colour) → shield (light grey) → `HP_TICK_STEP` dividers.
## A full ring without dividers: `hp = max_hp = 1`.
static func draw_hp_ring(c: CanvasItem, pos: Vector2, draw_radius: float,
		hp: int, shield: int, max_hp: int, color: Color, alpha: float) -> void:
	var ring_r: float = hp_ring_radius(draw_radius)
	var w: float = HP_RING_W
	c.draw_arc(pos, ring_r, 0.0, TAU, 36, alpha_mul(Color(0.15, 0.15, 0.15), alpha), w)
	var span: float = hp_ring_span(hp, shield, max_hp)
	var start_a: float = -PI * 0.5
	var hp_f: float = clampf(float(maxi(hp, 0)) / span, 0.0, 1.0)
	var all_f: float = clampf(float(maxi(hp, 0) + maxi(shield, 0)) / span, 0.0, 1.0)
	if hp_f > 0.0:
		c.draw_arc(pos, ring_r, start_a, start_a + TAU * hp_f,
				maxi(8, int(36.0 * hp_f)), alpha_mul(color, alpha), w)
	if all_f > hp_f:
		c.draw_arc(pos, ring_r, start_a + TAU * hp_f, start_a + TAU * all_f,
				maxi(4, int(36.0 * (all_f - hp_f))), alpha_mul(SHIELD_RING_COLOR, alpha), w)
	var tick_inner: float = ring_r - w * 0.5
	var tick_outer: float = ring_r + w * 0.5
	var tick_col: Color = alpha_mul(Color(0.05, 0.05, 0.05), alpha)
	var i: int = 1
	while float(i * HP_TICK_STEP) < span:
		var ang: float = start_a + TAU * float(i * HP_TICK_STEP) / span
		var dirv := Vector2(cos(ang), sin(ang))
		c.draw_line(pos + dirv * tick_inner, pos + dirv * tick_outer, tick_col, HP_TICK_W)
		i += 1


# ── Seating ──────────────────────────────────────────────────────────────────
## A portrait at `pos` would overlap one of `placed` (slightly lenient: neighbours in a
## row sit exactly `2r + MARKER_GAP` apart).
static func slot_collides(pos: Vector2, r: float, placed: Array) -> bool:
	var min_d: float = r * 2.0 + MARKER_GAP * 0.5
	for raw in placed:
		if pos.distance_to(raw as Vector2) < min_d:
			return true
	return false


## Seats of a block of `n` in horizontal rows (members left to right): `[{vec (offset
## from the point), ring (row index outwards), row (row inside the block)}]`, or empty
## when every candidate overlaps. `strict` also tests tails (`seat_crosses_arrows`);
## `ring_limit` caps how far out it looks.
static func pick_row_seats(tile_center: Vector2, n: int, v: float, cap: int, bias: int,
		r: float, placed: Array, arrows: Array = [], strict: bool = false,
		ring_limit: int = SLOT_RINGS) -> Array:
	var counts: Array = []
	var left: int = n
	while left > 0:
		var c: int = mini(left, cap)
		counts.append(c)
		left -= c
	var step: float = r * 2.0 + MARKER_GAP
	var side: float = 1.0 if bias > 0 else -1.0
	var shifts: Array = [0.0, 0.5 * side, -0.5 * side, side, -side]
	for o in range(mini(ring_limit, SLOT_RINGS)):
		for raw_s in shifts:
			var s: float = float(raw_s)
			var cand: Array = []
			var ok: bool = true
			for ri in range(counts.size()):
				var c: int = int(counts[ri])
				var y: float = v * step * float(o + ri + 1)
				for k in range(c):
					var vec := Vector2((float(k) - float(c - 1) * 0.5 + s) * step, y)
					if slot_collides(tile_center + vec, r, placed) or (strict
							and seat_crosses_arrows(tile_center, vec, r, placed, arrows)):
						ok = false
						break
					cand.append({"vec": vec, "ring": o + ri, "row": ri})
				if not ok:
					break
			if ok:
				return cand
	return []


## The portrait at this seat touches another's tail, or its own tail would touch
## another's portrait (portraits measured by `outer_radius`).
static func seat_crosses_arrows(tile_center: Vector2, vec: Vector2, r: float,
		placed: Array, arrows: Array) -> bool:
	var outer: float = outer_radius(r)
	var pos: Vector2 = tile_center + vec
	if disc_hits_arrows(pos, outer, arrows):
		return true
	var mine := arrow_outline_polygon(pos, tile_center, r, 1.0)
	if mine.is_empty():
		return false
	for raw in placed:
		if point_polygon_distance(raw as Vector2, mine) < outer:
			return true
	return false


## After the greedy pass: every row block (`entries[i]` = `{pilots: Array, center, v, cap,
## bias, row: bool, seats: Array}`) whose portraits touch another block's tail is
## re-seated with the strict test, sideways only (never past its own row). No clean seat
## = left as it is.
static func repair_arrow_overlaps(entries: Array, r: float) -> void:
	var outer: float = outer_radius(r)
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		if not bool(e["row"]):
			continue
		var others_disc: Array = []
		var others_arrow: Array = []
		for j in range(entries.size()):
			if j != i:
				collect_block_shapes(entries[j], r, others_disc, others_arrow)
		var tc: Vector2 = e["center"] as Vector2
		var hit: bool = false
		for raw_seat in e["seats"] as Array:
			if disc_hits_arrows(tc + ((raw_seat as Dictionary)["vec"] as Vector2),
					outer, others_arrow):
				hit = true
				break
		if not hit:
			continue
		var ring0: int = int(((e["seats"] as Array)[0] as Dictionary)["ring"])
		var seats: Array = pick_row_seats(tc, (e["pilots"] as Array).size(), float(e["v"]),
				int(e["cap"]), int(e["bias"]), r, others_disc, others_arrow, true, ring0 + 1)
		if not seats.is_empty():
			e["seats"] = seats


## Appends a block's portrait centres and tail outlines (scale 1).
static func collect_block_shapes(e: Dictionary, r: float, discs: Array, arrows: Array) -> void:
	var tc: Vector2 = e["center"] as Vector2
	for raw_seat in e["seats"] as Array:
		var pos: Vector2 = tc + ((raw_seat as Dictionary)["vec"] as Vector2)
		discs.append(pos)
		var arrow := arrow_outline_polygon(pos, tc, r, 1.0)
		if not arrow.is_empty():
			arrows.append(arrow)


static func disc_hits_arrows(pos: Vector2, outer: float, arrows: Array) -> bool:
	for raw in arrows:
		if point_polygon_distance(pos, raw as PackedVector2Array) < outer:
			return true
	return false


## Distance from a point to a convex polygon (0 inside).
static func point_polygon_distance(pt: Vector2, poly: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(pt, poly):
		return 0.0
	var best: float = INF
	for k in range(poly.size()):
		var q := Geometry2D.get_closest_point_to_segment(pt, poly[k], poly[(k + 1) % poly.size()])
		best = minf(best, pt.distance_to(q))
	return best
