class_name TrainingCourses
extends RefCounted

# Owned training courses — the run's course inventory. Courses are items: the
# board can hold as many copies of a tile as the run owns (no per-grade limit).
#
# ── Lines ────────────────────────────────────────────────────────────────────
# `training_tiles.csv` `line` groups the levels of one course (`basic` =
# 기초 훈련 I~IV, `field_hit` = 사격 훈련 I~III …; empty = the tile is its own
# line). A line is owned at **one level**: every owned copy counts as the
# highest grade acquired, so acquiring a higher level replaces the lower one,
# and acquiring a lower level adds a copy at the owned level
# (own 사격 훈련 II ×1, gain 사격 훈련 I → 사격 훈련 II ×2).
# Levels of one line must keep the same shape — an upgrade rewrites the tiles
# already on the board in place (`grant`).
#
# ── State ────────────────────────────────────────────────────────────────────
# `season_state["training_courses"]` = `{line: {"tile": tile_id, "count": int}}`.
# `count` -1 = unlimited: the basic line, whose owned level also fills every
# empty board cell (`filler_tile_id`). A new run owns Basic Training I only.

const STATE_KEY: String = "training_courses"
const BASIC_LINE: String = "basic"
## Basic Training I — the starting course and the filler when nothing is owned.
const START_TILE_ID: String = "T01"
const UNLIMITED: int = -1


## Inventory of a new run: Basic Training I only.
static func new_inventory() -> Dictionary:
	return {BASIC_LINE: {"tile": START_TILE_ID, "count": UNLIMITED}}


## The run's inventory, created (Basic Training I only) when missing — runs
## saved before course ownership load without it.
static func inventory(state: Dictionary) -> Dictionary:
	var inv: Variant = state.get(STATE_KEY)
	if not (inv is Dictionary) or (inv as Dictionary).is_empty():
		inv = new_inventory()
		state[STATE_KEY] = inv
	return inv


## Line of a tile id (`line` column, "" = its own id).
static func line_of(tile_id: String) -> String:
	var def: Dictionary = _def(tile_id)
	var line: String = String(def.get("line", ""))
	return tile_id if line.is_empty() else line


## Copies of exactly this tile the run owns: -1 = unlimited, 0 = none (also
## when its line is owned at another level).
static func owned_count(state: Dictionary, tile_id: String) -> int:
	var e: Dictionary = inventory(state).get(line_of(tile_id), {})
	if String(e.get("tile", "")) != tile_id:
		return 0
	return int(e.get("count", 0))


## Owned tile ids (one per line, at its owned level), in `training_tiles.csv` load order.
static func owned_tile_ids(state: Dictionary) -> Array:
	var out: Array = []
	for def in _gm().training_tiles:
		var id: String = String((def as Dictionary)["id"])
		if owned_count(state, id) != 0:
			out.append(id)
	return out


## The basic course at the owned level — fills every empty board cell.
static func filler_tile_id(state: Dictionary) -> String:
	var e: Dictionary = inventory(state).get(BASIC_LINE, {})
	var id: String = String(e.get("tile", ""))
	return START_TILE_ID if id.is_empty() else id


static func is_basic(tile_id: String) -> bool:
	return line_of(tile_id) == BASIC_LINE


## Acquires `n` copies of `tile_id`. The line ends at the higher of the owned
## and the acquired level; copies on the board follow an upgrade. Returns
## `{line, tile, count, from}` (`from` = the replaced tile id, "" when none),
## or {} for an unknown tile.
static func grant(state: Dictionary, tile_id: String, n: int = 1) -> Dictionary:
	var def: Dictionary = _def(tile_id)
	if def.is_empty():
		return {}
	var inv: Dictionary = inventory(state)
	var line: String = line_of(tile_id)
	var e: Dictionary = inv.get(line, {})
	var from: String = ""
	if e.is_empty():
		e = {"tile": tile_id, "count": UNLIMITED if line == BASIC_LINE else 0}
	elif int(def.get("grade", 0)) > int(_def(String(e["tile"])).get("grade", -1)):
		from = String(e["tile"])
		e["tile"] = tile_id
		_retarget_board(state, from, tile_id)
	if int(e["count"]) != UNLIMITED:
		e["count"] = int(e["count"]) + maxi(0, n)
	inv[line] = e
	return {"line": line, "tile": String(e["tile"]), "count": int(e["count"]), "from": from}


## Every course at its top level, `n` copies each — previews and dev checks only.
static func grant_all(state: Dictionary, n: int = 1) -> void:
	for def in _gm().training_tiles:
		grant(state, String((def as Dictionary)["id"]), n)


# Placed copies of the replaced level become the new level.
static func _retarget_board(state: Dictionary, from_id: String, to_id: String) -> void:
	for e_raw in (state.get("training_board", []) as Array):
		var e: Dictionary = e_raw
		if String(e.get("tile", "")) == from_id:
			e["tile"] = to_id


static func _def(tile_id: String) -> Dictionary:
	return _gm().training_tile_def(tile_id)


static func _gm() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("/root/GameManager")
