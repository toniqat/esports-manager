class_name SkillImages
extends RefCounted

# Pilot skill icon lookup. Same role as `CardImages` / `MechImages` — only this
# file knows where a skill's picture comes from.
#
#   images/skill/skill_<English_Name>.png — Deadlock hero ability icons
#       (152, white glyph on transparent, 137² except Doorman Call Bell and the
#       four Victor ones at 68², Rain of Arrows at 200²). Taken from namu.wiki
#       "분류:Deadlock(게임)/영웅" → each hero page's 능력 section; spaces in the
#       English name became underscores, apostrophes kept.
#
# `ICON` pairs every `pilot_skills.csv` `key` with the ability whose effect
# reads closest to the skill. One ability per skill. Add a skill → add a row
# here (a missing key just returns null and the caller draws no icon).
#
# Never `load()` blindly — check `ResourceLoader.exists()` first (`MechImages`).

const DIR: String = "res://resources/images/skill/"
## pilot_skills.key → icon file name (without `skill_` and `.png`).
const ICON: Dictionary = {
	"roam":            "Traveler",
	"hold_position":   "Stone_Form",
	"performance":     "Audience_Participation",
	"opportunist":     "Stalker's_Mark",
	"accumulate":      "Pain_Battery",
	"ops_prep":        "Card_Trick",
	"scheme":          "Dazzling_Trick",
	"recall_order":    "Doorway",
	"veteran":         "Crackshot",
	"dragon_blessing": "Bookwyrm",
	"hunt_reward":     "Bloodscent",
	"unstable_cannon": "Powder_Keg",
	"backbone":        "Willpower",
	"rookie":          "Static_Charge",
	"surge":           "Full_Auto",
	"elation":         "Jumpstart",
	"fierce_battle":   "Bullet_Dance",
	"battle_order":    "Rallying_Charge",
	"plunderer":       "Essence_Theft",
	"loot_collector":  "Enchanter's_Satchel",
	"siege":           "Heavy_Barrage",
	"versatile":       "Paradoxical_Swap",
	"adc_hunter":      "Fixation",
	"aggressive_push": "Flawless_Advance",
	"rivalry":         "Riposte",
}


## Icon for a skill key (`pilot_skills.key`). null when unmapped or missing.
static func icon_for(skill_key: String) -> Texture2D:
	var file: String = String(ICON.get(skill_key, ""))
	if file.is_empty():
		return null
	var path: String = DIR + "skill_" + file + ".png"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## Corner radius of `make_icon_tile` as a fraction of its side.
const TILE_RADIUS_FRAC: float = 0.22
## Icon inset inside the tile, per side, as a fraction of its side.
const TILE_INSET_FRAC: float = 0.16


## A `px`×`px` rounded-square tile filled with `bg`, with a soft blurred drop
## shadow, and the skill icon centred inside tinted `icon_color` (icons are
## white glyphs, so `modulate` recolours them). No icon → the empty tile.
## Everything is MOUSE_FILTER_IGNORE — the tile never eats a tap.
## The shadow draws outside the rect; leave ~shadow_px room around it.
static func make_icon_tile(skill_key: String, px: float, bg: Color,
		icon_color: Color, shadow_color: Color, shadow_px: float = 14.0) -> Control:
	var tile := Panel.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.size = Vector2(px, px)
	tile.custom_minimum_size = Vector2(px, px)
	var sty := StyleBoxFlat.new()
	sty.bg_color = bg
	var r: int = int(round(px * TILE_RADIUS_FRAC))
	sty.corner_radius_top_left     = r
	sty.corner_radius_top_right    = r
	sty.corner_radius_bottom_left  = r
	sty.corner_radius_bottom_right = r
	sty.anti_aliasing = true
	sty.shadow_color = shadow_color
	sty.shadow_size = int(round(shadow_px))
	sty.shadow_offset = Vector2(0.0, shadow_px * 0.4)
	tile.add_theme_stylebox_override("panel", sty)

	var tex: Texture2D = icon_for(skill_key)
	if tex == null:
		return tile
	var inset: float = px * TILE_INSET_FRAC
	var icon := TextureRect.new()
	icon.texture = tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = icon_color
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(inset, inset)
	icon.size = Vector2(px - inset * 2.0, px - inset * 2.0)
	tile.add_child(icon)
	return tile
