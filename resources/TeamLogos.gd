class_name TeamLogos
extends RefCounted

# Team logo lookup — only this file knows where a team's logo comes from.
#
#   images/team_logos/team_<id>.svg — **temporary** placeholder emblems (a coloured shield with a
#       simple glyph), one per league team 0..7. Teams without their own file (the INTL pool, 100..)
#       borrow `team_<id % 8>.svg` until real art exists.
#
# Signature colours: `color(team_id)` = the shield fill of that logo (`COLORS`, same index rule) —
# used where a side needs its team's colour (PREP card banners). Change both together.
#
# Never `load()` blindly — check `ResourceLoader.exists()` first (`MechImages`).

const DIR: String = "res://resources/images/team_logos/"
const SHARED: int = 8
## Team signature colour per league team 0..7 = the shield fill of `team_<id>.svg`.
const COLORS: Array[Color] = [
	Color("#2F6FD6"), Color("#D6453D"), Color("#2E9E6B"), Color("#8A4FD1"),
	Color("#E08A1E"), Color("#1F9BB0"), Color("#C2366F"), Color("#4E5868"),
]


static func texture(team_id: int) -> Texture2D:
	var own: String = DIR + "team_%d.svg" % team_id
	if ResourceLoader.exists(own):
		return load(own) as Texture2D
	var shared: String = DIR + "team_%d.svg" % posmod(team_id, SHARED)
	if ResourceLoader.exists(shared):
		return load(shared) as Texture2D
	return null


## The team's signature colour (INTL teams 100.. borrow `id % 8`, like the logo).
static func color(team_id: int) -> Color:
	return COLORS[posmod(team_id, SHARED)]
