class_name ResearchBubble
extends Control

# One facility's research speech bubble on a team base map (§16 decision 11).
#
# **Layout lives in `UI_Comp_ResearchBubble.tscn`** (bubble body · tail · name · icon · percent ·
# `%Hit`). The icon is the active research's quirk image (`ResearchSystem.row_icon`, else the
# facility's own icon) drawn through `research_ring.gdshader`: masked to a circle, with a
# radial progress ring, the icon full colour only inside the filled sector. This script only
# fills it from the run state and places it.
#
# States (exactly one, in this order):
#   vacant  — nobody seated (`FacilitySystem.occupant == ""`): grey icon, `공석` in red.
#   idle    — nobody researching (`ResearchSystem.active` empty): facility icon grey, `대기`.
#   paused  — the active row is blocked (`ResearchSystem.block_reason` ≠ ""): grey, `정지`.
#   running — the percentage of the active research (`ResearchSystem.progress`).
#
# `populate(map, state, interactive)` puts one bubble on every `Spot_Fac_*` marker of a
# `BaseMap` (its `%Facilities` layer, under the pilot tokens), reusing existing bubbles.
# Hub: interactive → `pressed(fid)`. Week screen: read-only (no input at all).

signal pressed(fid: String)

const SCENE_PATH: String = "res://features/season/facility/UI_Comp_ResearchBubble.tscn"
## Node name prefix of a bubble on the map layer (`ResearchBubble_<fid>`).
const NODE_PREFIX: String = "ResearchBubble_"

## The facility this bubble shows ("" before the first `show_state`).
var facility_id: String = ""


## Instantiates the scene. `ResearchBubble.new()` is an empty Control — don't use it.
static func create() -> ResearchBubble:
	return (load(SCENE_PATH) as PackedScene).instantiate() as ResearchBubble


## One bubble per facility spot of `map` (skips facilities whose marker the map lacks;
## a map without the `%Facilities` layer, e.g. the stadium, gets none). Bubbles already on
## the layer are refilled in place. Returns them in `FacilitySystem.FACILITIES` order.
static func populate(map: BaseMap, state: Dictionary, interactive: bool) -> Array:
	var out: Array = []
	var layer: Control = map.facility_layer()
	if layer == null:
		return out
	for raw in FacilitySystem.FACILITIES:
		var fid: String = String(raw)
		if not map.has_facility_spot(fid):
			continue
		var b: ResearchBubble = layer.get_node_or_null(NODE_PREFIX + fid) as ResearchBubble
		if b == null:
			b = create()
			b.name = NODE_PREFIX + fid
			layer.add_child(b)
		b.set_interactive(interactive)
		b.show_state(state, fid)
		map.place_at_facility(b, fid, b.anchor())
		out.append(b)
	return out


func _ready() -> void:
	(%Hit as Button).pressed.connect(_on_hit)
	if UiPreview.is_standalone(self):
		_fill_preview()


## Bubble-local point that stands on the facility spot (the tail tip).
func anchor() -> Vector2:
	return (%TailTip as Node2D).position


## Tappable (hub) or read-only (week screen: ignores the mouse entirely, so the pilot
## tokens and the scroll underneath keep every touch).
func set_interactive(on: bool) -> void:
	var hit: Button = %Hit
	hit.disabled = not on
	hit.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


## Fills the bubble from the run state.
func show_state(state: Dictionary, fid: String) -> void:
	facility_id = fid
	(%Name as Label).text = FacilitySystem.facility_name(fid)
	var act: Dictionary = ResearchSystem.active(state, fid)
	var icon: Texture2D = null
	var p: float = 0.0
	if not act.is_empty():
		icon = ResearchSystem.row_icon(String(act["rid"]))
		p = ResearchSystem.progress(state, fid)
	if icon == null:
		icon = FacilitySystem.icon_texture(String(FacilitySystem.def(fid).get("icon", "")))
	var word: String = ""
	var col: Color = OutgameTheme.TEXT
	if FacilitySystem.occupant(state, fid) == FacilitySystem.OCC_NONE:
		word = Loc.t(L.FACILITY_UI_BUBBLE_VACANT)
		col = OutgameTheme.NEGATIVE
	elif act.is_empty():
		word = Loc.t(L.FACILITY_UI_BUBBLE_IDLE)
		col = OutgameTheme.TEXT_SUB
	elif ResearchSystem.block_reason(state, fid, ResearchSystem.row(String(act["rid"]))) != "":
		word = Loc.t(L.FACILITY_UI_BUBBLE_PAUSED)
		col = OutgameTheme.TEXT_SUB
	set_look(icon, p, word, col)


## Draws one look directly (also used by the preview): `word` "" = running, the
## percentage of `ratio` is shown and the icon is in colour inside the filled sector.
func set_look(icon: Texture2D, ratio: float, word: String, col: Color) -> void:
	var tex: TextureRect = %Icon
	tex.texture = icon
	var mat := tex.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(&"progress", clampf(ratio, 0.0, 1.0))
		mat.set_shader_parameter(&"all_grey", word != "")
		mat.set_shader_parameter(&"fill_color", OutgameTheme.ACCENT)
		mat.set_shader_parameter(&"track_color", OutgameTheme.BORDER)
	var pct: Label = %Percent
	pct.text = word if word != "" else percent_text(ratio)
	pct.add_theme_color_override(&"font_color", col)


## "40%" — the progress ratio as a whole percent (floored, so 100% only when complete).
static func percent_text(ratio: float) -> String:
	return "%d%%" % floori(clampf(ratio, 0.0, 1.0) * 100.0)


func _on_hit() -> void:
	if facility_id != "":
		pressed.emit(facility_id)


## F6 단독 실행 미리보기 — 진행 중 40% 말풍선 (`resources/UiPreview.gd`). 누르면 출력만 한다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(pressed)
	facility_id = "train_field"
	(%Name as Label).text = FacilitySystem.facility_name(facility_id)
	set_interactive(true)
	set_look(FacilitySystem.icon_texture("Desecrator"), 0.4, "", OutgameTheme.TEXT)
