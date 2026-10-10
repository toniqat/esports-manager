class_name TraitUi
extends RefCounted

# Shared trait display helpers (§14 T3): the single rarity → colour table every
# screen that colours a trait by rarity uses (run result, hub staff sheet, trait
# picker, shop). Pure UI — rules stay in `TraitSystem`.
#
# Rarity 0..4 (`traits.rarity`, names `TraitSystem.rarity_name`):
#   0 grey · 1 green · 2 blue · 3 purple · 4 amber
# (1 is `CARD_TINTS` green, a shade off the `POSITIVE` polarity green.)
# The shop also uses this table for its pilot rows (`ShopPopup.rarity_color`
# delegates here), so gacha results read the same on both pools.


## Rarity 0..4 → fill colour (all from `OutgameTheme`). Out-of-range clamps.
static func rarity_color(rarity: int) -> Color:
	match clampi(rarity, 0, 4):
		0: return OutgameTheme.TEXT_SUB
		1: return OutgameTheme.CARD_TINTS[4]
		2: return OutgameTheme.CARD_TINTS[3]
		3: return OutgameTheme.CARD_TINTS[2]
	return OutgameTheme.ACCENT


## A filled rarity chip (rarity name on the rarity colour, white text).
static func add_rarity_chip(parent: Control, rarity: int, pos: Vector2, sz: Vector2,
		font_size: int = 20) -> Panel:
	return OutgameTheme.add_chip(parent, TraitSystem.rarity_name(rarity), pos, sz,
			rarity_color(rarity), OutgameTheme.TEXT_ON_FILL, font_size)
