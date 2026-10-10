class_name BaseMap
extends Control

# ── Team base map (팀 부지 맵) ───────────────────────────────────────────────
# One scene per map (`UI_Comp_BaseMap_<Name>.tscn`), all with this script:
#
#   BaseMap_<Name> (Control DESIGN_SIZE, mouse Ignore)
#   ├ %Art     TextureRect, the map art (resources/images/base_map/)
#   ├ Spots    Control ─ Spot_H · Spot_E · Spot_C · Spot_D · Spot_G · Spot_M · Spot_Q ·
#   │                    Spot_W · Spot_Dorm · Spot_Entrance  (Marker2D, drag them in the editor)
#   │                    + Spot_Fac_* (one per facility, `facility_defs.csv` `spot`; team maps only)
#   ├ %Facilities  Control, code adds the facility research bubbles (`ResearchBubble.populate`)
#   ├ %Tokens  Control, code adds the pilot tokens here
#   ├ Lighting   BaseMapLighting (optional): time-of-day tint, sun, building shadows
#   ├ Buildings  Node2D (optional, hidden at runtime): BaseMapBuilding roof polygons + heights
#   └ Roads      BaseMapRoads (optional, hidden at runtime): Line2D roads the pilots walk
#
# A training colour group has one spot (`COLOR_SPOTS`, the colour table of
# `features/season/training/README.md`); `Dorm` and `Entrance` are the afternoon
# away spots. Which map a team uses is data (`teams.csv` `map_id` → `SCENES`).
# Pilots are drawn as portrait markers (tail + shadow helpers from `PilotMarker`, seating and
# the outline-only look from `BaseMapSeating`): a spot is one point (on the road nearest it,
# `Roads`); a lone pilot stands above it, a crowd sits around it as a regular polygon, every
# tail pointing at it (`place_tokens`). `walk_from` moves them along the roads; `play_hour`
# runs the clock.

## Map scale against the art's authored 1000 × 634 frame (`ART_BASE_SIZE`). The scenes are
## already authored at this scale — root size, art rect and every `Spot_*` marker — so
## `spot_point` / `facility_point` / `size` are in **scaled map pixels**. Overlays put on the
## map (pilot tokens, research bubbles) are NOT scaled: only their positions follow the spots.
const MAP_SCALE: float = 1.2
const ART_BASE_SIZE: Vector2 = Vector2(1000, 634)
## Root size of every map scene (= ART_BASE_SIZE × MAP_SCALE, rounded). Wider than the
## 1080 screen: hosts centre it horizontally (`mount`) and the overflow is cropped equally
## on both sides; `visible_rect()` is the part on screen.
const DESIGN_SIZE: Vector2 = Vector2(1200, 761)
## Phone viewport width (`docs/mobile_safe_area.md` §1) — the fallback of `visible_rect`
## outside the tree.
const VIEW_WIDTH: float = 1080.0

## `map_id` → scene. Same order as the image numbering in `resources/images/base_map/`, which
## starts at 02 (the two indoor Schale maps 00 / 01 were removed 2026-10: map_id = number − 2).
const SCENES: Array = [
	"res://features/season/week/base_map/UI_Comp_BaseMap_Gehenna.tscn",
	"res://features/season/week/base_map/UI_Comp_BaseMap_Abydos.tscn",
	"res://features/season/week/base_map/UI_Comp_BaseMap_Millennium.tscn",
	"res://features/season/week/base_map/UI_Comp_BaseMap_Trinity.tscn",
	"res://features/season/week/base_map/UI_Comp_BaseMap_RedWinter.tscn",
	"res://features/season/week/base_map/UI_Comp_BaseMap_Hyakkiyako.tscn",
	"res://features/season/week/base_map/UI_Comp_BaseMap_DuShiratori.tscn",
	"res://features/season/week/base_map/UI_Comp_BaseMap_Shanhaijing.tscn",
	"res://features/season/week/base_map/UI_Comp_BaseMap_Haruhabara.tscn",
	"res://features/season/week/base_map/UI_Comp_BaseMap_WildHunt.tscn",
]

## The weekend stadium (Sat prep / Sun match / Sun press), not a team map — not in
## `SCENES`, so no `teams.csv` `map_id` can pick it.
const STADIUM_SCENE: String = "res://features/season/week/base_map/UI_Comp_BaseMap_Stadium.tscn"

const SPOT_NEUTRAL: String = "W"
## Growth spot (colours A / P share it); also a valid `facility` value.
const SPOT_GROWTH: String = "G"
const SPOT_DORM: String = "Dorm"
const SPOT_ENTRANCE: String = "Entrance"
## Stadium spots: team room (Saturday analysis / ban-pick), stage booths (Sunday match),
## press room (Sunday afternoon).
const SPOT_TEAM_ROOM: String = "TeamRoom"
const SPOT_BOOTH: String = "Booth"
const SPOT_PRESS: String = "Press"

## Training tile colour symbol → spot. Growth A / P share `G`; the amplifier's black
## self cell `K` and "no tile" (basic course) stand on the neutral spot.
const COLOR_SPOTS: Dictionary = {
	"H": "H", "E": "E", "C": "C", "D": "D", "A": "G", "P": "G",
	"M": "M", "Q": "Q", "W": "W", "K": "W",
}

## Portrait radius on the map = the battlefield's (`PilotMarker.FIELD_RADIUS`); markers keep
## this pixel size whatever the map's scale.
const MARKER_RADIUS: float = PilotMarker.FIELD_RADIUS
## Walking speed along the roads (map px / s) and the shortest walk.
const WALK_SPEED: float = 300.0
const WALK_MIN_TIME: float = 0.45

const _PREVIEW_TOKEN: String = "res://features/season/week/UI_Comp_WeekMapPilot.tscn"
const _PREVIEW_STEP: float = 3.5
const _PREVIEW_PILOTS: int = 5
const _PREVIEW_HOURS: Array = [8.0, 11.0, 15.0, 18.5]
## F6 preview: per round, how many pilots share one spot (1 = all random) — shows every
## polygon of `BaseMapSeating`.
const _PREVIEW_CROWDS: Array = [5, 3, 1, 4, 2]

@onready var _tokens: Control = %Tokens
@onready var _roads: BaseMapRoads = get_node_or_null("Roads") as BaseMapRoads
@onready var _lighting: BaseMapLighting = get_node_or_null("Lighting") as BaseMapLighting

## key → {node, anchor, portrait, ring, ground, vec, ground_now, centre_now} of the last
## `place_tokens` (`ground` + `vec` = where it rests; `*_now` = where it is drawn now).
var _placed: Dictionary = {}
var _walks: Array = []   # running walk Tweens
var _preview_round: int = 0


## Instantiates the map scene of `map_id` (clamped into `SCENES`).
static func create(map_id: int) -> BaseMap:
	var idx: int = clampi(map_id, 0, SCENES.size() - 1)
	return (load(String(SCENES[idx])) as PackedScene).instantiate() as BaseMap


## Instantiates the stadium map (`STADIUM_SCENE`).
static func create_stadium() -> BaseMap:
	return (load(STADIUM_SCENE) as PackedScene).instantiate() as BaseMap


## Marker name of a facility's spot (`facility_defs.csv` `spot`, e.g. `Spot_Fac_Intel`).
static func facility_spot_name(fid: String) -> String:
	return String(FacilitySystem.def(fid).get("spot", ""))


## Spot of a training colour symbol ("" = no tile → neutral).
static func spot_of_color(symbol: String) -> String:
	return String(COLOR_SPOTS.get(symbol, SPOT_NEUTRAL))


## Spot of a training facility (`TrainingBoard.day_groups` / week log row `facility`): an
## authored spot name (`training_tiles.csv` `facility`: H E C D G M Q W) or a colour symbol.
static func spot_of_facility(facility: String) -> String:
	return SPOT_GROWTH if facility == SPOT_GROWTH else spot_of_color(facility)


func _ready() -> void:
	_tokens.draw.connect(_draw_markers)
	var shapes: CanvasItem = get_node_or_null("Buildings") as CanvasItem
	if shapes != null:
		shapes.visible = false
	if UiPreview.is_standalone(self):
		_fill_preview()


## Adds `map` to `holder` (a plain Control, not a container — a container would take the
## map's 1200 minimum width and widen the page) at `DESIGN_SIZE`, centred horizontally on
## the holder, top-aligned, and keeps it centred when the holder resizes. Hosts give the
## holder a screen-centred rect, so the overflow is cropped equally left / right.
static func mount(map: BaseMap, holder: Control) -> void:
	holder.add_child(map)
	map.size = DESIGN_SIZE
	map._center_in(holder)
	var cb: Callable = map._center_in.bind(holder)
	if not holder.resized.is_connected(cb):
		holder.resized.connect(cb)


func _center_in(holder: Control) -> void:
	if not is_instance_valid(holder) or get_parent() != holder:
		return
	var w: float = holder.size.x if holder.size.x > 0.0 else VIEW_WIDTH
	position = Vector2(roundf((w - DESIGN_SIZE.x) * 0.5), 0.0)


## Map-local rect that is on screen: the map is centred on the viewport (`mount`), so the
## crop is `(DESIGN_SIZE.x − viewport width) / 2` on each side (none on a viewport wider
## than the map, e.g. a tablet). Full height. Tokens / bubbles that must stay visible
## clamp to this instead of the whole map rect.
func visible_rect() -> Rect2:
	var vw: float = get_viewport_rect().size.x if is_inside_tree() else VIEW_WIDTH
	var crop: float = maxf(0.0, (DESIGN_SIZE.x - vw) * 0.5)
	return Rect2(crop, 0.0, DESIGN_SIZE.x - crop * 2.0, DESIGN_SIZE.y)


## Map-local point of a spot. A missing marker falls back to the neutral spot, then
## to the map centre.
func spot_point(spot: String) -> Vector2:
	var m: Node2D = get_node_or_null("Spots/Spot_" + spot) as Node2D
	if m == null:
		m = get_node_or_null("Spots/Spot_" + SPOT_NEUTRAL) as Node2D
	if m == null:
		return size * 0.5
	return m.position


## Does this map have the facility's `Spot_Fac_*` marker? (The stadium has none.)
func has_facility_spot(fid: String) -> bool:
	var spot: String = facility_spot_name(fid)
	return spot != "" and get_node_or_null("Spots/" + spot) is Node2D


## Map-local point of a facility's spot. A missing marker falls back to the neutral spot.
func facility_point(fid: String) -> Vector2:
	var spot: String = facility_spot_name(fid)
	var m: Node2D = get_node_or_null("Spots/" + spot) as Node2D if spot != "" else null
	if m == null:
		return spot_point(SPOT_NEUTRAL)
	return m.position


## The facility bubble layer (`%Facilities`, under the pilot tokens); null on a map
## without one (the stadium).
func facility_layer() -> Control:
	return get_node_or_null("%Facilities") as Control


## Puts `node` so that its local point `anchor` stands on the facility's spot, clamped
## inside the on-screen part of the map (`visible_rect`; a bubble near the top edge slides
## down over its spot).
func place_at_facility(node: Control, fid: String, anchor: Vector2) -> void:
	node.position = clamp_into(facility_point(fid) - anchor, node.size, visible_rect())


func clear_tokens() -> void:
	for c in _tokens.get_children():
		_tokens.remove_child(c)
		c.queue_free()


## Adds `node` to the token layer (call `place_tokens` once all are in).
func add_token(node: Control) -> void:
	_tokens.add_child(node)


## Places tokens on their spots. `entries` = `[{node: Control, spot: String, anchor: Vector2,
## key: Variant, portrait: Texture2D, ring: Color}]` — `anchor` = the token-local portrait
## centre, `key` = who it is (kept for `walk_from`; default the entry index), `ring` = the
## outline and tail colour (default black; the picked pilot passes an accent colour).
## Seating (`BaseMapSeating.pick_seats`, map only): every spot is one point (its road point
## when the map has `Roads`); one pilot stands above it, 2–5 sit around it as a regular
## polygon (seat 0 at the top, clockwise in entry order), rotated / grown when it would touch
## portraits or tails of spots placed before; seats are clamped into `visible_rect`. The
## portrait disc, outline, tail (pointing at the point) and shadow are drawn on the token
## layer (`_draw_markers`, shadows → tails → portraits); the token Control carries what lies
## on top (mask, bubble, away chip, rising texts, tap target).
func place_tokens(entries: Array) -> void:
	stop_walks()
	_placed.clear()
	var groups: Dictionary = {}
	var order: Array = []
	for i in entries.size():
		var e: Dictionary = entries[i]
		var spot: String = String(e.get("spot", SPOT_NEUTRAL))
		if not groups.has(spot):
			groups[spot] = []
			order.append(spot)
		(groups[spot] as Array).append(i)
	var r: float = MARKER_RADIUS
	var area: Rect2 = visible_rect().grow(-BaseMapSeating.outer_radius(r))
	var discs: Array = []
	var tails: Array = []
	for spot in order:
		var group: Array = groups[spot]
		var center: Vector2 = ground_point(spot_point(String(spot)))
		var seats: Array = BaseMapSeating.pick_seats(center, group.size(), r, area, discs, tails)
		for k in group.size():
			var e2: Dictionary = entries[int(group[k])]
			var vec: Vector2 = seats[k]
			discs.append(center + vec)
			var tail: PackedVector2Array = BaseMapSeating.tail_outline(center + vec, center, r)
			if not tail.is_empty():
				tails.append(tail)
			var key: Variant = e2.get("key", int(group[k]))
			_placed[key] = {"node": e2["node"], "anchor": e2.get("anchor", Vector2.ZERO),
					"portrait": e2.get("portrait", null),
					"ring": e2.get("ring", Color.BLACK),
					"ground": center, "vec": vec}
			_set_marker(_placed[key], center, vec)
	_tokens.queue_redraw()


## The point a spot's pilots stand on: the road point nearest it (`Roads`), else the spot.
func ground_point(at: Vector2) -> Vector2:
	if _roads != null and not _roads.is_empty():
		return _roads.snap(at)
	return at


## Moves a placed token so its portrait centre is `ground + vec` (token scale / pivot
## included) and remembers where it stands now for the marker drawing.
func _set_marker(p: Dictionary, ground: Vector2, vec: Vector2) -> void:
	var node: Control = p["node"]
	var anchor: Vector2 = p["anchor"]
	var centre: Vector2 = ground + vec
	node.position = centre - node.pivot_offset - (anchor - node.pivot_offset) * node.scale
	p["ground_now"] = ground
	p["centre_now"] = centre


## Shadows → tails → portraits of every placed token; a raised token (z_index > 0, the
## picked pilot) lays its tail with the others and its disc last. Called from `%Tokens`'
## draw (under the tokens' own children).
func _draw_markers() -> void:
	var all: Array = []
	var lifted: Array = []
	for key in _placed:
		var p: Dictionary = _placed[key]
		if not is_instance_valid(p["node"]) or not (p["node"] as Control).visible:
			continue
		all.append(p)
		if (p["node"] as Control).z_index > 0:
			lifted.append(p)
	for p in all:
		_draw_shadow(p, _tail_outline(p),
				PilotMarker.ShadowPart.TAIL if lifted.has(p) else PilotMarker.ShadowPart.FULL)
	for p in all:
		_draw_tail(p)
	for p in all:
		if not lifted.has(p):
			_draw_disc(p)
	for p in lifted:
		_draw_shadow(p, PackedVector2Array(), PilotMarker.ShadowPart.DISC)
		_draw_disc(p)


func _draw_shadow(p: Dictionary, tail: PackedVector2Array, part: PilotMarker.ShadowPart) -> void:
	var dr: float = MARKER_RADIUS * _em(p)
	PilotMarker.draw_shadow(_tokens, p["centre_now"], dr, tail, 1.0, part,
			dr + BaseMapSeating.OUTLINE_W * _em(p))


## Solid tail in the outline colour (no team fill).
func _draw_tail(p: Dictionary) -> void:
	var poly: PackedVector2Array = _tail_outline(p)
	if poly.is_empty():
		return
	var col: Color = p["ring"]
	_tokens.draw_colored_polygon(poly, col)
	_tokens.draw_polyline(PilotMarker.close_polygon(poly), col, 1.0, true)


## Outline disc (`ring` colour, `BaseMapSeating.OUTLINE_W`), a white backing (some
## `*_circle.png` are transparent inside), the portrait. No HP / team ring.
func _draw_disc(p: Dictionary) -> void:
	var em: float = _em(p)
	var dr: float = MARKER_RADIUS * em
	var c: Vector2 = p["centre_now"]
	_tokens.draw_circle(c, dr + BaseMapSeating.OUTLINE_W * em, p["ring"], true, -1.0, true)
	_tokens.draw_circle(c, maxf(1.0, dr - 1.0), Color.WHITE)
	var portrait: Texture2D = p["portrait"]
	if portrait != null:
		_tokens.draw_texture_rect(portrait, Rect2(c - Vector2(dr, dr), Vector2(dr, dr) * 2.0), false)


static func _em(p: Dictionary) -> float:
	return (p["node"] as Control).scale.x


static func _tail_outline(p: Dictionary) -> PackedVector2Array:
	return BaseMapSeating.tail_outline(p["centre_now"], p["ground_now"], MARKER_RADIUS, _em(p))


## Where the tokens stand now, for a later `walk_from`: key → {ground, vec}.
func token_state() -> Dictionary:
	var out: Dictionary = {}
	for key in _placed:
		var p: Dictionary = _placed[key]
		out[key] = {"ground": p["ground"], "vec": p["vec"]}
	return out


## Walks every placed token whose key is in `prev` (a `token_state` of the same map) from
## where it stood to where it stands now, along the roads, after `delay`, taking at most
## `max_time` (shorter walks take `length / WALK_SPEED`). Like the battlefield's glide, the
## point moves along the path and the seat offset blends from the old seat to the new one.
func walk_from(prev: Dictionary, max_time: float, delay: float = 0.0) -> void:
	stop_walks()
	for key in _placed:
		if not prev.has(key):
			continue
		var p: Dictionary = _placed[key]
		var was: Dictionary = prev[key]
		var a: Vector2 = was["ground"]
		var b: Vector2 = p["ground"]
		var vec_from: Vector2 = was["vec"]
		var vec_to: Vector2 = p["vec"]
		if a.distance_to(b) < 1.0 and vec_from.distance_to(vec_to) < 1.0:
			continue
		var path := PackedVector2Array([a, b])
		if _roads != null and not _roads.is_empty():
			path = _roads.route(a, b)
		path[0] = a
		path[path.size() - 1] = b
		var length: float = BaseMapRoads.path_length(path)
		var time: float = clampf(length / WALK_SPEED, WALK_MIN_TIME, maxf(WALK_MIN_TIME, max_time))
		var step: Callable = _walk_step.bind(p, path, length, vec_from, vec_to)
		step.call(0.0)
		var tw: Tween = (p["node"] as Control).create_tween()
		if delay > 0.0:
			tw.tween_interval(delay)
		tw.tween_method(step, 0.0, 1.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_walks.append(tw)


func _walk_step(f: float, p: Dictionary, path: PackedVector2Array, length: float,
		vec_from: Vector2, vec_to: Vector2) -> void:
	if not is_instance_valid(p["node"]):
		return
	_set_marker(p, BaseMapRoads.point_along(path, f * length), vec_from.lerp(vec_to, f))
	_tokens.queue_redraw()


## Tokens or lighting still moving.
func is_animating() -> bool:
	for raw in _walks:
		var tw: Tween = raw
		if tw.is_valid() and tw.is_running():
			return true
	return _lighting != null and _lighting.is_playing()


## Jumps every walk and the clock to their end.
func finish_animation() -> void:
	for raw in _walks:
		var tw: Tween = raw
		if tw.is_valid():
			tw.custom_step(1000.0)
	_walks.clear()
	if _lighting != null:
		_lighting.finish()


func stop_walks() -> void:
	for raw in _walks:
		var tw: Tween = raw
		if tw.is_valid():
			tw.kill()
	_walks.clear()


## Time of day (0 … 24) of the map's lighting, now. No-op without a `Lighting` node.
func set_hour(h: float) -> void:
	if _lighting != null:
		_lighting.set_hour(h)


## Runs the lighting clock `from_h` → `to_h` (past 24 = through the night) over `time` s.
func play_hour(from_h: float, to_h: float, time: float) -> void:
	if _lighting != null:
		_lighting.play(from_h, to_h, time)


## Top-left `at` of a box of `box` size moved inside `area` (a box larger than the area
## sticks to its top-left corner).
static func clamp_into(at: Vector2, box: Vector2, area: Rect2) -> Vector2:
	return at.clamp(area.position, (area.end - box).max(area.position))


## F6 preview, as the week screen shows the map (no facility bubbles): five tokens with the
## portraits of five random pilots (not mobs), on random token spots. Then a demo loop
## (`_preview_tick`): every `_PREVIEW_STEP` s each pilot walks to a new random spot and the
## clock moves to the next stage hour (`_PREVIEW_HOURS`, the last one through the night).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.ensure_run()  # players.csv mob ids → PilotImages
	var scene: PackedScene = load(_PREVIEW_TOKEN) as PackedScene
	var spots: Array = []
	for m in get_node("Spots").get_children():
		if not String(m.name).begins_with("Spot_Fac_"):  # facility spots carry the bubbles
			spots.append(String(m.name).trim_prefix("Spot_"))
	var pool: Array = []
	for pid in PilotImages.POOL_SIZE:
		if not PilotImages.is_mob(pid):
			pool.append(pid)
	pool.shuffle()
	var entries: Array = []
	for i in mini(_PREVIEW_PILOTS, pool.size()):
		var pid: int = int(pool[i])
		var tok: Control = scene.instantiate() as Control
		add_token(tok)
		(tok.get_node("%Away") as Control).visible = false
		(tok.get_node("%Bubble") as Control).visible = false
		(tok.get_node("%BubbleTail") as CanvasItem).visible = false
		var hold: Control = tok.get_node("%Portrait")
		entries.append({"node": tok, "spot": "", "key": pid,
				"portrait": PilotImages.circle_for(pid), "anchor": hold.position + hold.size * 0.5})
	_preview_spots(entries, spots)
	place_tokens(entries)
	set_hour(float(_PREVIEW_HOURS[0]))
	var timer := Timer.new()
	timer.wait_time = _PREVIEW_STEP
	add_child(timer)
	timer.timeout.connect(_preview_tick.bind(entries, spots))
	timer.start()


func _preview_tick(entries: Array, spots: Array) -> void:
	_preview_round += 1
	var prev: Dictionary = token_state()
	_preview_spots(entries, spots)
	place_tokens(entries)
	var n: int = _PREVIEW_HOURS.size()
	var from_h: float = float(_PREVIEW_HOURS[(_preview_round - 1) % n])
	var to_h: float = float(_PREVIEW_HOURS[_preview_round % n])
	var night: bool = to_h < from_h
	if night:
		to_h += 24.0
	var time: float = 2.6 if night else 1.4
	play_hour(from_h, to_h, time)
	walk_from(prev, time * (0.55 if night else 1.0), time * 0.45 if night else 0.0)


## Random spots, the first `_PREVIEW_CROWDS[round]` pilots on one shared spot.
func _preview_spots(entries: Array, spots: Array) -> void:
	var crowd: int = int(_PREVIEW_CROWDS[_preview_round % _PREVIEW_CROWDS.size()])
	var shared: String = String(spots.pick_random())
	for i in entries.size():
		(entries[i] as Dictionary)["spot"] = shared if i < crowd else String(spots.pick_random())
