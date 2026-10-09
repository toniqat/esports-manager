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
#   └ %Tokens  Control, code adds the pilot tokens here
#
# A training colour group has one spot (`COLOR_SPOTS`, the colour table of
# `features/season/training/README.md`); `Dorm` and `Entrance` are the afternoon
# away spots. Which map a team uses is data (`teams.csv` `map_id` → `SCENES`).
# Tokens that share a spot are fanned out in rows (`place_tokens`) so they never
# overlap, and every token is kept inside the map rect.

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

## `map_id` → scene. The order is the image numbering in `resources/images/base_map/`.
const SCENES: Array = [
	"res://features/season/week/base_map/UI_Comp_BaseMap_SchaleOffice.tscn",
	"res://features/season/week/base_map/UI_Comp_BaseMap_SchaleDorm.tscn",
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

## Fan-out of tokens sharing a spot: column / row step and tokens per row. The step is
## also a token's footprint: tokens on nearby spots are pushed apart until their
## footprints no longer overlap (`_separate`, at most `SEPARATE_PASSES` passes).
## The token (`UI_Comp_WeekMapPilot`) is 152 × 152: portrait 84 + the three gauge panels
## under it; the step leaves an 8 px gap. Tokens keep this pixel size whatever the map's scale.
const TOKEN_STEP: Vector2 = Vector2(160, 160)
const TOKENS_PER_ROW: int = 3
const SEPARATE_PASSES: int = 32

const _PREVIEW_TOKEN: String = "res://features/season/week/UI_Comp_WeekMapPilot.tscn"

@onready var _tokens: Control = %Tokens


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
## inside the map rect (a bubble near the top edge slides down over its spot).
func place_at_facility(node: Control, fid: String, anchor: Vector2) -> void:
	var area: Vector2 = size if size.x > 0.0 else DESIGN_SIZE
	var at: Vector2 = facility_point(fid) - anchor
	node.position = at.clamp(Vector2.ZERO, (area - node.size).max(Vector2.ZERO))


func clear_tokens() -> void:
	for c in _tokens.get_children():
		_tokens.remove_child(c)
		c.queue_free()


## Adds `node` to the token layer (call `place_tokens` once all are in).
func add_token(node: Control) -> void:
	_tokens.add_child(node)


## Places tokens on their spots. `entries` = `[{node: Control, spot: String, anchor: Vector2}]`,
## `anchor` = the token-local point that stands on the spot (the portrait centre).
## Tokens sharing a spot fan out in rows of `TOKENS_PER_ROW`, centred on the spot,
## in `entries` order; tokens of nearby spots are then pushed apart (`_separate`), and
## every token is clamped inside the map rect.
func place_tokens(entries: Array) -> void:
	var groups: Dictionary = {}
	var order: Array = []
	for raw in entries:
		var e: Dictionary = raw
		var spot: String = String(e.get("spot", SPOT_NEUTRAL))
		if not groups.has(spot):
			groups[spot] = []
			order.append(spot)
		(groups[spot] as Array).append(e)
	var area: Vector2 = size if size.x > 0.0 else DESIGN_SIZE
	var nodes: Array = []
	for spot in order:
		var group: Array = groups[spot]
		var base: Vector2 = spot_point(String(spot))
		for k in group.size():
			var e2: Dictionary = group[k]
			var node: Control = e2["node"]
			var row: int = floori(float(k) / float(TOKENS_PER_ROW))
			var col: int = k % TOKENS_PER_ROW
			var in_row: int = mini(TOKENS_PER_ROW, group.size() - row * TOKENS_PER_ROW)
			var off := Vector2((float(col) - float(in_row - 1) * 0.5) * TOKEN_STEP.x,
					float(row) * TOKEN_STEP.y)
			var at: Vector2 = base + off - (e2.get("anchor", Vector2.ZERO) as Vector2)
			node.position = at.clamp(Vector2.ZERO, (area - node.size).max(Vector2.ZERO))
			nodes.append(node)
	_separate(nodes, area)


## Pushes overlapping token footprints (`TOKEN_STEP`, centred on each token) apart along
## the axis of least overlap, half each, clamped inside `area`. Tokens fanned out on one
## spot already sit a footprint apart, so this only moves tokens of nearby spots.
static func _separate(nodes: Array, area: Vector2) -> void:
	for _pass in SEPARATE_PASSES:
		var moved: bool = false
		for i in nodes.size():
			for j in range(i + 1, nodes.size()):
				var a: Control = nodes[i]
				var b: Control = nodes[j]
				var d: Vector2 = (b.position + b.size * 0.5) - (a.position + a.size * 0.5)
				var over := Vector2(TOKEN_STEP.x - absf(d.x), TOKEN_STEP.y - absf(d.y))
				if over.x <= 0.0 or over.y <= 0.0:
					continue
				var push := Vector2.ZERO
				if over.x <= over.y:
					push.x = over.x * 0.5 * (1.0 if d.x >= 0.0 else -1.0)
				else:
					push.y = over.y * 0.5 * (1.0 if d.y >= 0.0 else -1.0)
				a.position = (a.position - push).clamp(Vector2.ZERO, (area - a.size).max(Vector2.ZERO))
				b.position = (b.position + push).clamp(Vector2.ZERO, (area - b.size).max(Vector2.ZERO))
				moved = true
		if not moved:
			return


## F6 preview: one token per spot named after it (spot check), plus two more on the
## neutral spot to show the fan-out, and the facility bubbles of an in-memory run.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm != null:
		ResearchBubble.populate(self, gm.season_state, false)
	var scene: PackedScene = load(_PREVIEW_TOKEN) as PackedScene
	var entries: Array = []
	# Every marker of this scene (team maps and the stadium alike), two extra on W.
	var spots: Array = []
	for m in get_node("Spots").get_children():
		if String(m.name).begins_with("Spot_Fac_"):
			continue  # facility spots carry the bubbles, not tokens
		spots.append(String(m.name).trim_prefix("Spot_"))
	spots.append_array([SPOT_NEUTRAL, SPOT_NEUTRAL])
	for spot in spots:
		var tok: Control = scene.instantiate() as Control
		add_token(tok)
		(tok.get_node("%Name") as Label).text = String(spot)
		(tok.get_node("%Away") as Control).visible = true
		(tok.get_node("%Bubble") as Control).visible = false
		(tok.get_node("%BubbleTail") as CanvasItem).visible = false
		var hold: Control = tok.get_node("%Portrait")
		entries.append({"node": tok, "spot": spot, "anchor": hold.position + hold.size * 0.5})
	place_tokens(entries)
