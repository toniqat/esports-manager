class_name TeamLogos
extends RefCounted

# Team logo lookup — only this file knows where a team's logo comes from.
#
#   images/team_logos/team_<id>.svg — **temporary** placeholder emblems (a coloured shield with a
#       simple glyph), one per league team 0..7. Teams without their own file (the INTL pool, 100..)
#       borrow `team_<id % 8>.svg` until real art exists.
#
# Never `load()` blindly — check `ResourceLoader.exists()` first (`MechImages`).

const DIR: String = "res://resources/images/team_logos/"
const SHARED: int = 8


static func texture(team_id: int) -> Texture2D:
	var own: String = DIR + "team_%d.svg" % team_id
	if ResourceLoader.exists(own):
		return load(own) as Texture2D
	var shared: String = DIR + "team_%d.svg" % posmod(team_id, SHARED)
	if ResourceLoader.exists(shared):
		return load(shared) as Texture2D
	return null
