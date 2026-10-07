class_name ShopRevealItem
extends Panel

# One gacha / purchase result card inside `ShopPopup`'s reveal grid
# (rarity band · pilot face or trait +/− mark · name · NEW / 돌파 n / 파편 +n / 재료 +n tag).
#
# **Layout lives in `ShopRevealItem.tscn`** (fixed 168 × 300 tile, children placed by position).
# This script only fills `%` nodes and paints the data-driven colours: the card border and
# band take the rarity colour (`ShopPopup.rarity_color`), the trait mark is POSITIVE / NEGATIVE,
# the tag chip colour follows the result kind — none of those are theme variations.

const SCENE_PATH: String = "res://features/meta/shop/ShopRevealItem.tscn"


static func create() -> ShopRevealItem:
	return (load(SCENE_PATH) as PackedScene).instantiate() as ShopRevealItem


## `e` = one entry of `Gacha.pull(...).results` — `{pool, id, rarity, result, stage, shards, amount}`.
func show_result(e: Dictionary) -> void:
	var rar: int = int(e.get("rarity", 0))
	var col: Color = ShopPopup.rarity_color(rar)
	add_theme_stylebox_override("panel", OutgameTheme.flat_style(OutgameTheme.SURFACE, 14, col, 3))
	var band_sb: StyleBoxFlat = OutgameTheme.flat_style(col, 0)
	band_sb.corner_radius_top_left = 12
	band_sb.corner_radius_top_right = 12
	%Band.add_theme_stylebox_override("panel", band_sb)
	%Rarity.text = TraitSystem.rarity_name(rar)
	%Rarity.add_theme_color_override("font_color", OutgameTheme.TEXT_ON_FILL)

	var id: int = int(e.get("id", -1))
	var is_pilot: bool = String(e.get("pool", "")) == Gacha.POOL_PILOT
	%Face.visible = is_pilot
	%Mark.visible = not is_pilot
	if is_pilot:
		%Name.text = String(Gacha.pilot_row(id).get("name", "?"))
		%Face.texture = PilotImages.face_for(id)
	else:
		%Name.text = String(TraitSystem.row(id).get("name", "?"))
		var pos_trait: bool = TraitSystem.is_positive(id)
		%Mark.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
				OutgameTheme.POSITIVE if pos_trait else OutgameTheme.NEGATIVE, 56))
		%MarkText.text = "+" if pos_trait else "−"
		%MarkText.add_theme_color_override("font_color", OutgameTheme.TEXT_ON_FILL)
	_show_tag(e)


func _show_tag(e: Dictionary) -> void:
	var tag: String = ""
	var tag_bg: Color = OutgameTheme.SURFACE_SUNK
	var tag_fg: Color = OutgameTheme.TEXT_SUB
	match String(e.get("result", "")):
		"new":
			tag = "NEW"
			tag_bg = OutgameTheme.ACCENT
			tag_fg = OutgameTheme.TEXT_ON_FILL
		"breakthrough":
			tag = "돌파 %d" % int(e.get("stage", 0))
			tag_bg = OutgameTheme.CARD_TINTS[3]
			tag_fg = OutgameTheme.TEXT_ON_FILL
		"shard":
			tag = "파편 +%d" % int(e.get("shards", 0))
		"material":
			tag = "재료 +%d" % int(e.get("amount", 0))
	var chip: Panel = %Tag
	chip.visible = tag != ""
	if tag == "":
		return
	# Chip = pill (radius = half the height), like `OutgameTheme.add_chip`.
	chip.add_theme_stylebox_override("panel", OutgameTheme.flat_style(tag_bg, int(chip.size.y * 0.5)))
	%TagText.text = tag
	%TagText.add_theme_color_override("font_color", tag_fg)
