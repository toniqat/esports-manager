class_name RunTeamBanner
extends Control

# The chosen team's banner during run setup (after the 팀 step): banner art as the background
# (`TeamLogos.banner`, fallback field `TeamLogos.color`), the team logo and its names — short
# name (big) + full name (small). Nothing else (no budget / facility).
#
# **The layout is `UI_Comp_RunTeamBanner.tscn`**, which holds two head arrangements:
#   - `%HeadStrip` — logo + names left-aligned, vertically centred (감독 step: a strip at the top
#     of the body);
#   - `%HeadTop` — compact logo + names centred along the top edge (편성 step: the banner is the
#     backdrop of the 5 picked pilots, which sit under that head).
# `centered` picks one, `square` swaps the rounded mask for a square one (full-bleed backdrop).
# Code fills the art / colour / logo / names (`fill`). Construct with `RunTeamBanner.create()`.

const SCENE_PATH: String = "res://features/meta/run_setup/UI_Comp_RunTeamBanner.tscn"
## Gap between `%HeadTop` and content laid on the banner under it (`top_head_bottom`).
const TOP_HEAD_GAP: float = 8.0

## true = `%HeadTop` (centred along the top), false = `%HeadStrip` (left, vertically centred).
@export var centered: bool = false:
	set(v):
		centered = v
		_apply_layout()
## true = square mask (`RunTeamBannerMaskSquare`), false = rounded (`RunTeamBannerMask`).
@export var square: bool = false:
	set(v):
		square = v
		_apply_layout()

var team_id: int = -1


static func create() -> RunTeamBanner:
	return (load(SCENE_PATH) as PackedScene).instantiate() as RunTeamBanner


func _ready() -> void:
	_apply_layout()
	if UiPreview.is_standalone(self):
		_fill_preview()


## Bottom edge of the centred head area (`%HeadTop` bottom + its gap) — content placed on the
## banner (lineup slot row) starts here.
func top_head_bottom() -> float:
	return (%HeadTop as Control).offset_bottom + TOP_HEAD_GAP


func fill(p_team_id: int) -> void:
	team_id = p_team_id
	var row: Dictionary = {}
	for raw in RunRules.team_packages():
		if int((raw as Dictionary).get("id", -1)) == p_team_id:
			row = raw
			break
	var short_name: String = Loc.t(String(row.get("short_name_key", "")))  # l10n-dynamic: name.team.*.short
	var full_name: String = Loc.t(String(row.get("name_key", "")))  # l10n-dynamic: name.team.*.name
	var logo: Texture2D = TeamLogos.texture(p_team_id) if p_team_id >= 0 else null
	(%Fill as ColorRect).color = TeamLogos.color(p_team_id)
	(%Art as TextureRect).texture = TeamLogos.banner(p_team_id) if p_team_id >= 0 else null
	for pre in ["Strip", "Top"]:
		(get_node("%" + pre + "Logo") as TextureRect).texture = logo
		(get_node("%" + pre + "Short") as Label).text = short_name
		(get_node("%" + pre + "Name") as Label).text = full_name


func _apply_layout() -> void:
	if not is_node_ready():
		return
	(%HeadStrip as Control).visible = not centered
	(%HeadTop as Control).visible = centered
	(%Mask as Control).theme_type_variation = \
			&"RunTeamBannerMaskSquare" if square else &"RunTeamBannerMask"


## F6 standalone preview (`resources/UiPreview.gd`) — team 3, strip layout.
func _fill_preview() -> void:
	UiPreview.stage(self)
	fill(3)
