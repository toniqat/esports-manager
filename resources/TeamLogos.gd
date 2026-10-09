class_name TeamLogos
extends RefCounted

# Team art lookup — only this file knows where a team's logo, banner and signature colours come
# from. **The data is `teams.csv` / `intl_teams.csv`** (game.db `teams` · `intl_teams`):
#   color_main / color_sub — the two signature colours (`#RRGGBB`; main = the shield fill, sub =
#       its glyph / accent). Main colours are distinct across all 12 teams.
#   logo_path   — `res://resources/images/team_logos/team_<id>.svg` (**temporary** shield emblems)
#   banner_path — `res://resources/images/team_banners/banner_<id>.svg` (main field, sub stripes /
#       edge bands, faint logo watermark; PREP card-row banner, 1000×320)
# Read once per run of the game (static cache, both tables). Safe fallback when the table, the row
# or a file is missing: logo / banner → `team_<id % 8>.svg` / `banner_<id % 8>.svg` if it exists,
# else null; colours → `FALLBACK_MAIN` / `FALLBACK_SUB`.
#
# Never `load()` blindly — check `ResourceLoader.exists()` first (`MechImages`).

const DIR: String = "res://resources/images/team_logos/"
const BANNER_DIR: String = "res://resources/images/team_banners/"
const SHARED: int = 8
const FALLBACK_MAIN: Color = Color("#4E5868")
const FALLBACK_SUB: Color = Color("#D9DEE6")

## team id → row Dictionary (color_main, color_sub, logo_path, banner_path), filled on first use.
static var _rows: Dictionary = {}
static var _loaded: bool = false


static func texture(team_id: int) -> Texture2D:
	return _load_first([String(_row(team_id).get("logo_path", "")),
			DIR + "team_%d.svg" % posmod(team_id, SHARED)])


## The team's banner image (main colour field, sub-colour stripes, logo watermark).
static func banner(team_id: int) -> Texture2D:
	return _load_first([String(_row(team_id).get("banner_path", "")),
			BANNER_DIR + "banner_%d.svg" % posmod(team_id, SHARED)])


## The team's main signature colour (`color_main`).
static func color(team_id: int) -> Color:
	return _hex(String(_row(team_id).get("color_main", "")), FALLBACK_MAIN)


## The team's sub signature colour (`color_sub`).
static func color_sub(team_id: int) -> Color:
	return _hex(String(_row(team_id).get("color_sub", "")), FALLBACK_SUB)


static func _row(team_id: int) -> Dictionary:
	_ensure_loaded()
	return _rows.get(team_id, {})


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		return
	for table in ["teams", "intl_teams"]:
		db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='%s'" % table)
		if db.query_result.is_empty():
			continue
		db.query("SELECT * FROM %s" % table)
		for row in db.query_result:
			var r: Dictionary = row
			_rows[int(r["id"])] = {
				"color_main": String(r.get("color_main", "")),
				"color_sub": String(r.get("color_sub", "")),
				"logo_path": String(r.get("logo_path", "")),
				"banner_path": String(r.get("banner_path", "")),
			}
	db.close_db()


static func _load_first(paths: Array) -> Texture2D:
	for raw in paths:
		var p: String = String(raw)
		if not p.is_empty() and ResourceLoader.exists(p):
			return load(p) as Texture2D
	return null


static func _hex(text: String, fallback: Color) -> Color:
	return Color.from_string(text, fallback) if not text.is_empty() else fallback
