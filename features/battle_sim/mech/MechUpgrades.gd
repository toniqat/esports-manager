class_name MechUpgrades
extends RefCounted

# ── Mech upgrades (돌파형, §15 A) ─────────────────────────────────────────────
# Reaching mech mastery Lv3 / Lv4 / Lv5 (`MechMastery.level_of`) on a mech unlocks
# one upgrade step each — cumulative, so Lv5 holds all three. Table
# `data/csv/mech_upgrades.csv` (`id, mech_id, level, target, param, card_id, value,
# desc_key`):
#   target `passive` — `param` (p1 | p2) of the mech's passive row += `value`
#                      (`passive_def`; MechSkillSystem reads the result as usual).
#   target `card`    — mech card `card_id` is replaced by its `mech_cards.upgrade_id`
#                      row (a separate "+" row, `count = 0`). A "+" row may itself
#                      carry an `upgrade_id` ("++"): `card_def_for` follows the chain
#                      while each link's own step is unlocked.
# BattleSim gets the level per pilot from `match_ctx.mech_levels`
# (`BattleSim.mech_level_for`); outgame screens pass the level directly.
#
# Static, pure: reads its table from game.db once, the card / passive rows from
# `GameManager` (`mech_card_def`, `mech_passive_def`).

const TARGET_PASSIVE: String = "passive"
const TARGET_CARD: String = "card"

static var _steps_by_mech: Dictionary = {}   # int mech_id → Array[Dictionary] (level order)
static var _loaded: bool = false


## Every step of a mech, level order — `[{id, mech_id, level, target, param, card_id, value, desc_key}]`.
static func steps(mech_id: int) -> Array:
	_ensure_loaded()
	return _steps_by_mech.get(mech_id, [])


## Steps unlocked at mastery `level` (step.level <= level).
static func unlocked(mech_id: int, level: int) -> Array:
	var out: Array = []
	for s in steps(mech_id):
		if int((s as Dictionary)["level"]) <= level:
			out.append(s)
	return out


static func is_unlocked(step: Dictionary, level: int) -> bool:
	return int(step.get("level", 99)) <= level


## The first step still locked at `level` ({} = all unlocked / none).
static func next_step(mech_id: int, level: int) -> Dictionary:
	for s in steps(mech_id):
		if int((s as Dictionary)["level"]) > level:
			return s
	return {}


## The passive row with the unlocked passive steps applied (a copy; the input is
## returned untouched when nothing applies). Empty in → empty out.
static func passive_def(base_def: Dictionary, mech_id: int, level: int) -> Dictionary:
	if base_def.is_empty():
		return base_def
	var out: Dictionary = base_def
	for s in unlocked(mech_id, level):
		var st: Dictionary = s
		if String(st["target"]) != TARGET_PASSIVE:
			continue
		if out == base_def:
			out = base_def.duplicate()
		var p: String = String(st["param"])
		out[p] = int(out.get(p, 0)) + int(st["value"])
	return out


## Mech card row `card_id`, swapped along its upgrade chain for every link whose
## step is unlocked at `level` on `mech_id`. Unknown id → {}.
static func card_def_for(card_id: int, mech_id: int, level: int) -> Dictionary:
	var gm: Node = _gm()
	if gm == null:
		return {}
	var def: Dictionary = gm.mech_card_def(card_id)
	if def.is_empty() or level <= 0:
		return def
	var open: Dictionary = {}   # source card id → true
	for s in unlocked(mech_id, level):
		var st: Dictionary = s
		if String(st["target"]) == TARGET_CARD:
			open[int(st["card_id"])] = true
	var guard: int = 0
	while open.has(int(def.get("id", -1))) and int(def.get("upgrade_id", -1)) >= 0 and guard < 4:
		var nxt: Dictionary = gm.mech_card_def(int(def["upgrade_id"]))
		if nxt.is_empty():
			break
		def = nxt
		guard += 1
	return def


## Display line of one step — `desc_key` with `{from}` / `{to}` = the passive
## param (cumulative over the earlier steps) or the card cost before / after.
static func step_text(step: Dictionary) -> String:
	var key: String = String(step.get("desc_key", ""))
	if key.is_empty():
		return ""
	var fr: int = 0
	var to: int = 0
	var gm: Node = _gm()
	var mech_id: int = int(step.get("mech_id", -1))
	if String(step.get("target", "")) == TARGET_PASSIVE:
		var base: Dictionary = gm.mech_passive_def(mech_id) if gm != null else {}
		var before: Dictionary = passive_def(base, mech_id, int(step["level"]) - 1)
		fr = int(before.get(String(step["param"]), 0))
		to = fr + int(step.get("value", 0))
	elif gm != null:
		var src: Dictionary = gm.mech_card_def(int(step.get("card_id", -1)))
		fr = int(src.get("cost", 0))
		var up: Dictionary = gm.mech_card_def(int(src.get("upgrade_id", -1)))
		to = int(up.get("cost", fr))
	return Loc.t(key, {"from": fr, "to": to})  # l10n-dynamic: mastery.upgrade.*.desc


## The upgraded card row a card step unlocks ({} for a passive step).
static func step_card_def(step: Dictionary) -> Dictionary:
	if String(step.get("target", "")) != TARGET_CARD:
		return {}
	var gm: Node = _gm()
	if gm == null:
		return {}
	var src: Dictionary = gm.mech_card_def(int(step.get("card_id", -1)))
	return gm.mech_card_def(int(src.get("upgrade_id", -1)))


static func _gm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("GameManager")


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_warning("MechUpgrades: cannot open game.db")
		return
	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='mech_upgrades'")
	if db.query_result.is_empty():
		db.close_db()
		return
	db.query("SELECT * FROM mech_upgrades ORDER BY mech_id, level, id")
	for row in db.query_result:
		var e: Dictionary = {
			"id": int(row["id"]), "mech_id": int(row["mech_id"]), "level": int(row["level"]),
			"target": String(row["target"]), "param": String(row["param"]),
			"card_id": int(row["card_id"]), "value": int(row["value"]),
			"desc_key": String(row["desc_key"]),
		}
		if not _steps_by_mech.has(e["mech_id"]):
			_steps_by_mech[e["mech_id"]] = []
		(_steps_by_mech[e["mech_id"]] as Array).append(e)
	db.close_db()
