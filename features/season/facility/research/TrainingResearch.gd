class_name TrainingResearch
extends RefCounted

# ── Research kind handler: `training` (§16) ──
# Training-course research for `train_field` / `train_engage` / `train_growth`.
# Row `p1` = a `training_tiles.id`; completion = `TrainingCourses.grant(state, p1, 1)`
# (same line → one more copy at the owned level, higher grade → the line is upgraded,
# copies on the board follow). Contract: `features/season/facility/README.md` "Kind
# handlers" and "TrainingResearch" (rules, ladder, per-facility training stat).
#
# ── Which facility owns a course ─────────────────────────────────────────────
# A course line belongs to the training facility whose research rows grant it
# (`research.csv`, `p1` → `TrainingCourses.line_of`). Everything no row grants (the
# basic course's Basic Training I) falls back to `DEFAULT_FACILITY`. `TrainingBoard`
# reads it to pick **which facility's training stat** multiplies a cell's EXP.

## The training facilities, in `FacilitySystem.FACILITIES` order.
const FACILITIES: Array = ["train_field", "train_engage", "train_growth"]
## Owner of course lines no research row grants (Basic Training I) — the growth
## facility also researches Basic Training II~IV, so the whole basic line is its.
const DEFAULT_FACILITY: String = "train_growth"

static var _line_fac: Dictionary = {}   # course line → facility id (built from research rows)
static var _line_fac_built: bool = false


# ── Kind-handler interface (ResearchSystem dispatches here) ──────────────────
## Training rows take no target.
static func targets(_state: Dictionary, _row: Dictionary) -> Array:
	return []


## "" when researching `row` still gives something, else why not (current locale):
## the course's line is already owned at a **higher** grade (a lower row would only
## add a copy the higher row also adds) — or, for the basic line (unlimited copies),
## at this grade or higher. The facility level gate (`min_level`) is ResearchSystem's.
static func row_available(state: Dictionary, row: Dictionary) -> String:
	var tile_id: String = String(row.get("p1", ""))
	var def: Dictionary = _tile_def(tile_id)
	if def.is_empty():
		return Loc.t(L.FACILITY_RESEARCH_BLOCK_UNKNOWN)
	var line: String = TrainingCourses.line_of(tile_id)
	var e: Dictionary = TrainingCourses.inventory(state).get(line, {})
	if e.is_empty():
		return ""
	var owned_id: String = String(e.get("tile", ""))
	var owned_grade: int = int(_tile_def(owned_id).get("grade", -1))
	var grade: int = int(def.get("grade", 0))
	var pointless: bool = owned_grade > grade
	if line == TrainingCourses.BASIC_LINE:
		pointless = owned_grade >= grade
	if pointless:
		return Loc.t(L.RESEARCH_TRAINING_BLOCK_OWNED_HIGHER, {"tile": _tile_name(owned_id)})
	return ""


## Grants one copy of the row's course. Note: basic upgrade / line upgrade / one more copy.
static func on_complete(state: Dictionary, row: Dictionary, _target: String) -> Dictionary:
	var g: Dictionary = TrainingCourses.grant(state, String(row.get("p1", "")), 1)
	if g.is_empty():
		return {"text_key": "", "args": {}}
	var tile: String = _tile_name(String(g["tile"]))
	if String(g["line"]) == TrainingCourses.BASIC_LINE:
		return {"text_key": L.RESEARCH_TRAINING_NOTE_BASIC, "args": {"tile": tile}}
	if String(g["from"]) != "":
		return {"text_key": L.RESEARCH_TRAINING_NOTE_UPGRADE,
				"args": {"from": _tile_name(String(g["from"])), "tile": tile, "count": int(g["count"])}}
	return {"text_key": L.RESEARCH_TRAINING_NOTE_GAIN, "args": {"tile": tile, "count": int(g["count"])}}


## Facility screen body: the facility's research rows as course cards with a per-week
## progress bar, select on tap, owned courses modal (`TrainingResearchBody`).
static func make_body(state: Dictionary, fid: String) -> Control:
	if not FACILITIES.has(fid):
		return null
	var body: TrainingResearchBody = TrainingResearchBody.create()
	body.fill(state, fid)
	return body


# ── Facility of a course (per-facility training stat) ────────────────────────
## Training facility that owns `tile_id`'s line (`DEFAULT_FACILITY` when no row grants it).
static func facility_of_tile(tile_id: String) -> String:
	return facility_of_line(TrainingCourses.line_of(tile_id))


static func facility_of_line(line: String) -> String:
	_build_line_map()
	return String(_line_fac.get(line, DEFAULT_FACILITY))


## Training EXP multiplier of the courses `fid` owns: its occupant's training stat
## (`FacilitySystem.stat_value`) through `TrainingTile.training_exp_mult`.
static func exp_mult(state: Dictionary, fid: String) -> float:
	return TrainingTile.training_exp_mult(FacilitySystem.stat_value(state, fid))


## Lines `fid` researches, CSV order: `[{line, steps: [{rid, tile, grade, min_level}]}]`.
static func ladder(fid: String) -> Array:
	var out: Array = []
	var at: Dictionary = {}   # line → index in out
	for raw in ResearchSystem.rows_for(fid):
		var r: Dictionary = raw
		if String(r.get("kind", "")) != "training":
			continue
		var tile_id: String = String(r.get("p1", ""))
		var def: Dictionary = _tile_def(tile_id)
		if def.is_empty():
			continue
		var line: String = TrainingCourses.line_of(tile_id)
		if not at.has(line):
			at[line] = out.size()
			out.append({"line": line, "steps": []})
		((out[int(at[line])] as Dictionary)["steps"] as Array).append({
			"rid": String(r["id"]), "tile": tile_id,
			"grade": int(def.get("grade", 0)), "min_level": int(r.get("min_level", 1)),
		})
	return out


# ── Internals ────────────────────────────────────────────────────────────────
static func _build_line_map() -> void:
	if _line_fac_built:
		return
	_line_fac_built = true
	for raw in ResearchSystem.rows():
		var r: Dictionary = raw
		if String(r.get("kind", "")) != "training":
			continue
		var line: String = TrainingCourses.line_of(String(r.get("p1", "")))
		if not _line_fac.has(line):
			_line_fac[line] = String(r.get("facility", DEFAULT_FACILITY))


static func _tile_def(tile_id: String) -> Dictionary:
	if tile_id == "":
		return {}
	var gm: Node = (Engine.get_main_loop() as SceneTree).root.get_node("/root/GameManager")
	return gm.training_tile_def(tile_id)


static func _tile_name(tile_id: String) -> String:
	var key: String = String(_tile_def(tile_id).get("name_key", ""))
	return tile_id if key == "" else Loc.t(key)  # l10n-dynamic: training.tile.*.name
