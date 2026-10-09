class_name FacilitySystem
extends RefCounted

# ── Facilities (§16) — levels, occupants, the stat a facility reads ──────────
# Contract: `docs/outgame_dev_plan.md` §16 and `features/season/facility/README.md`.
# **Frozen API** (base commit) — feature agents ask for changes, they do not edit it.
#
# Seven facilities per team (`FACILITIES`, rows in `data/csv/facility_defs.csv`), all
# built from the start. Each holds at most one occupant: "" (nobody), "manager", or a
# run staff id as a string. The manager may occupy up to `MANAGER_SLOTS` facilities
# (one seat per facility); a staff member occupies at most one.
#
# State `season_state.facilities = {fid: {"level": int, "occupant": String}}` (string
# keys, JSON round trip → every read is `int()` / `String()`-wrapped).
#
# Levels 1..`max_level()`. **No facility may exceed the front's level** (upgrade check,
# and `set_level` clamps the others when the front goes down). The front itself only needs
# the money (its research was removed, user decision 2026-10-09).
# Upgrades are paid like the old single facility: facility fund first, then balance
# (`FinanceSystem.pay_upgrade`).

const FRONT: String = "front"
## Facility ids in display order (map spots, sheet lists). Matches `facility_defs.csv`.
const FACILITIES: Array = ["train_field", "train_engage", "train_growth", "intel", "mech_lab",
		"front", "personnel"]
const OCC_NONE: String = ""
const OCC_MANAGER: String = "manager"
## Run-start auto assignment: staff job → preferred facility. A second staff of the same
## job (or a facility already taken) falls to the next free facility in `FACILITIES` order.
const JOB_FACILITY: Dictionary = {
	"coach_training": "train_field",
	"coach_tactics": "train_engage",
	"coach_knowledge": "mech_lab",
	"analyst": "intel",
	"finance": "front",
	"assistant": "personnel",
}
## Run-start: the manager's slots go to facilities still empty after the staff, in this
## order — growth first (it owns the basic course every empty training cell uses), then the front.
const MANAGER_AUTO_ORDER: Array = ["train_growth", "front", "train_field", "train_engage", "mech_lab", "intel", "personnel"]
const ICON_DIR: String = "res://resources/images/facilities/"

static var _defs: Dictionary = {}   # fid → {id, kind, name_key, desc_key, stat, spot, icon, cost_pct}
static var _loaded: bool = false


# ── Definitions ──────────────────────────────────────────────────────────────
## `{id, kind, name_key, desc_key, stat, spot, icon, cost_pct}`; {} for an unknown id.
static func def(fid: String) -> Dictionary:
	_ensure_loaded()
	return _defs.get(fid, {})


static func is_facility(fid: String) -> bool:
	return FACILITIES.has(fid) and not def(fid).is_empty()


## Display name (current locale). Unknown id → the id itself.
static func facility_name(fid: String) -> String:
	var d: Dictionary = def(fid)
	if d.is_empty():
		return fid
	return Loc.t(String(d["name_key"]))  # l10n-dynamic: facility.def.*.name


static func facility_desc(fid: String) -> String:
	var d: Dictionary = def(fid)
	if d.is_empty():
		return ""
	return Loc.t(String(d["desc_key"]))  # l10n-dynamic: facility.def.*.desc


## The manager stat this facility reads (`StaffSystem.STATS`).
static func stat_of(fid: String) -> String:
	return String(def(fid).get("stat", ""))


## Research kind of the facility (`training` / `intel` / `mech` / `front` / `personnel`).
static func kind_of(fid: String) -> String:
	return String(def(fid).get("kind", ""))


## Facilities whose occupant supplies `stat`, in `FACILITIES` order (empty for `tactics`).
static func facilities_for_stat(stat: String) -> Array:
	var out: Array = []
	for fid in FACILITIES:
		if stat_of(String(fid)) == stat:
			out.append(fid)
	return out


## Icon texture for an `icon` cell (`facility_defs.csv` — a temporary pictogram
## `resources/images/facilities/fac_<icon>.svg`). null when missing.
static func icon_texture(icon: String) -> Texture2D:
	if icon.is_empty():
		return null
	var path: String = ICON_DIR + "fac_" + icon + ".svg"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## The facility's own icon (`icon_texture` of its `facility_defs.csv` row).
static func icon_of(fid: String) -> Texture2D:
	return icon_texture(String(def(fid).get("icon", "")))


# ── Run lifecycle ────────────────────────────────────────────────────────────
## Once at run start (`GameManager.start_run`, after the staff snapshot and
## `FinanceSystem.init_run`): every facility at the team package `facility_level`,
## team staff auto-assigned by job, manager slots empty, research / intel / scout reset.
static func init_run(state: Dictionary, team_id: int) -> void:
	var lvl: int = clampi(int(_team_package(team_id).get("facility_level", 1)), 1, max_level())
	_build(state, lvl)
	state["research"] = {"active": {}, "points": {}, "done": {}}
	state["intel_rank"] = {}
	state["scout"] = {"candidates": [], "week": ""}
	ResearchSystem.ensure_auto(state)


## Lazy migration of a run saved before §16 (`SaveSystem.load_run` calls it; every read
## also calls it through `_facs`). Old `finance.facility_level` → every facility's level
## (the key is then dropped), staff auto-assigned as at run start. Idempotent.
static func migrate(state: Dictionary) -> void:
	if not (state.get("facilities", {}) as Dictionary).is_empty():
		_fill_missing_keys(state)
		_normalize(state)
		ResearchSystem.ensure_auto(state)
		return
	if not bool(state.get("active", false)):
		return
	var fin: Dictionary = state.get("finance", {})
	var lvl: int = clampi(int(fin.get("facility_level", 1)), 1, max_level())
	fin.erase("facility_level")
	_build(state, lvl)
	_fill_missing_keys(state)
	ResearchSystem.ensure_auto(state)


# ── Levels ───────────────────────────────────────────────────────────────────
static func max_level() -> int:
	return clampi(ConstTable.int_of("FACILITY_LEVEL_MAX"), 1, FinanceSystem.max_level())


static func level(state: Dictionary, fid: String) -> int:
	var e: Dictionary = (_facs(state).get(fid, {}) as Dictionary)
	if e.is_empty():
		# No run state (or an unknown id) — the pre-§16 single level, else 1.
		return clampi(int((state.get("finance", {}) as Dictionary).get("facility_level", 1)), 1, max_level())
	return clampi(int(e.get("level", 1)), 1, max_level())


## Sets a level (clamped 1..max; a non-front facility also to the front's level).
## Lowering the front clamps every other facility down to it (the cap is an invariant).
static func set_level(state: Dictionary, fid: String, lvl: int) -> void:
	var facs: Dictionary = _facs(state)
	if not facs.has(fid):
		return
	var v: int = clampi(lvl, 1, max_level())
	if fid != FRONT:
		v = mini(v, level(state, FRONT))
	(facs[fid] as Dictionary)["level"] = v
	if fid == FRONT:
		for other in FACILITIES:
			if String(other) != FRONT and facs.has(other) and level(state, String(other)) > v:
				(facs[other] as Dictionary)["level"] = v


## Money to go from the current level to the next (0 at max):
## `facilities.csv upgrade_cost(level) × cost_pct / 100`, rounded.
static func upgrade_cost(state: Dictionary, fid: String) -> int:
	var lvl: int = level(state, fid)
	if lvl >= max_level():
		return 0
	var base: float = float(FinanceSystem.facility_row(lvl).get("upgrade_cost", 0))
	return int(round(base * float(def(fid).get("cost_pct", 100)) / 100.0))


## "" when `fid` can be upgraded now, else the reason (current locale), in order:
## unknown · max level · front cap · funds short.
static func upgrade_block_reason(state: Dictionary, fid: String) -> String:
	if not is_facility(fid):
		return Loc.t(L.FACILITY_BLOCK_UNKNOWN_FACILITY)
	var lvl: int = level(state, fid)
	if lvl >= max_level():
		return Loc.t(L.UI_WORD_MAX_LEVEL)
	if fid != FRONT and lvl >= level(state, FRONT):
		return Loc.t(L.FACILITY_BLOCK_FRONT_CAP, {"level": level(state, FRONT)})
	if FinanceSystem.upgrade_funds(state) < upgrade_cost(state, fid):
		return Loc.t(L.FINANCE_BLOCK_NO_FUNDS)
	return ""


static func can_upgrade(state: Dictionary, fid: String) -> bool:
	return upgrade_block_reason(state, fid) == ""


## Upgrades one level, paying fund first then balance. "" on success, else the reason.
static func upgrade(state: Dictionary, fid: String) -> String:
	var why: String = upgrade_block_reason(state, fid)
	if why != "":
		return why
	FinanceSystem.pay_upgrade(state, upgrade_cost(state, fid))
	set_level(state, fid, level(state, fid) + 1)
	return ""


# ── Occupants ────────────────────────────────────────────────────────────────
## "" (nobody) · "manager" · "<staff id>".
static func occupant(state: Dictionary, fid: String) -> String:
	return String((_facs(state).get(fid, {}) as Dictionary).get("occupant", OCC_NONE))


static func manager_slots() -> int:
	return maxi(0, ConstTable.int_of("MANAGER_SLOTS"))


static func manager_slots_used(state: Dictionary) -> int:
	return manager_facilities(state).size()


## Facilities the manager occupies, `FACILITIES` order.
static func manager_facilities(state: Dictionary) -> Array:
	var out: Array = []
	for fid in FACILITIES:
		if occupant(state, String(fid)) == OCC_MANAGER:
			out.append(fid)
	return out


## The facility a staff member occupies ("" when free).
static func facility_of_staff(state: Dictionary, staff_id: int) -> String:
	var who: String = str(staff_id)
	for fid in FACILITIES:
		if occupant(state, String(fid)) == who:
			return String(fid)
	return ""


## "" when `who` ("manager" or a staff id string) may take `fid`, else the reason.
## Taking a seat replaces whoever sits there; a staff member already elsewhere moves.
static func assign_block_reason(state: Dictionary, fid: String, who: String) -> String:
	if not is_facility(fid):
		return Loc.t(L.FACILITY_BLOCK_UNKNOWN_FACILITY)
	if who == OCC_MANAGER:
		if occupant(state, fid) != OCC_MANAGER and manager_slots_used(state) >= manager_slots():
			return Loc.t(L.FACILITY_BLOCK_MANAGER_SLOTS,
					{"used": manager_slots_used(state), "max": manager_slots()})
		return ""
	if not who.is_valid_int() or run_staff(state, int(who)).is_empty():
		return Loc.t(L.FACILITY_BLOCK_UNKNOWN_PERSON)
	return ""


## Seats `who` in `fid`. "" on success, else the reason (nothing changed).
static func assign(state: Dictionary, fid: String, who: String) -> String:
	if who == OCC_NONE:
		unassign(state, fid)
		return ""
	var why: String = assign_block_reason(state, fid, who)
	if why != "":
		return why
	if who != OCC_MANAGER:
		var old: String = facility_of_staff(state, int(who))
		if old != "" and old != fid:
			unassign(state, old)
	(_facs(state)[fid] as Dictionary)["occupant"] = who
	return ""


static func unassign(state: Dictionary, fid: String) -> void:
	var facs: Dictionary = _facs(state)
	if facs.has(fid):
		(facs[fid] as Dictionary)["occupant"] = OCC_NONE


## Run staff not seated anywhere (`run_setup.staff` entries).
static func free_staff(state: Dictionary) -> Array:
	var out: Array = []
	for raw in _run_staff(state):
		var e: Dictionary = raw
		if facility_of_staff(state, int(e.get("id", -1))) == "":
			out.append(e)
	return out


## The run staff entry with this id ({} when not on the team).
static func run_staff(state: Dictionary, staff_id: int) -> Dictionary:
	for raw in _run_staff(state):
		var e: Dictionary = raw
		if int(e.get("id", -1)) == staff_id:
			return e
	return {}


## The occupant's value of the facility's stat: manager → `StaffSystem.manager_value`
## (with `staff_mods`), staff → their snapshot stat, nobody → `StaffSystem.STAT_MIN`.
static func stat_value(state: Dictionary, fid: String) -> int:
	var stat: String = stat_of(fid)
	var occ: String = occupant(state, fid)
	if stat.is_empty() or occ == OCC_NONE:
		return StaffSystem.STAT_MIN
	if occ == OCC_MANAGER:
		return StaffSystem.manager_value(state, stat)
	var e: Dictionary = run_staff(state, int(occ)) if occ.is_valid_int() else {}
	if e.is_empty():
		return StaffSystem.STAT_MIN
	return clampi(int((e.get("stats", {}) as Dictionary).get(stat, StaffSystem.STAT_MIN)),
			StaffSystem.STAT_MIN, StaffSystem.STAT_MAX)


## Is the facility run by staff (not the manager, not empty)?
static func is_delegated_fid(state: Dictionary, fid: String) -> bool:
	var occ: String = occupant(state, fid)
	return occ != OCC_NONE and occ != OCC_MANAGER


## Display name of the occupant: `term.person.manager`, the staff name, or `ui.word.none`.
static func occupant_name(state: Dictionary, fid: String) -> String:
	var occ: String = occupant(state, fid)
	if occ == OCC_NONE:
		return Loc.t(L.UI_WORD_NONE)
	if occ == OCC_MANAGER:
		return Loc.t(L.TERM_PERSON_MANAGER)
	return StaffSystem.staff_name(run_staff(state, int(occ)) if occ.is_valid_int() else {})


# ── Internals ────────────────────────────────────────────────────────────────
# The facilities dict, migrated lazily for an active pre-§16 run.
static func _facs(state: Dictionary) -> Dictionary:
	if (state.get("facilities", {}) as Dictionary).is_empty() and bool(state.get("active", false)):
		migrate(state)
	return state.get("facilities", {})


static func _build(state: Dictionary, lvl: int) -> void:
	var facs: Dictionary = {}
	for fid in FACILITIES:
		facs[fid] = {"level": lvl, "occupant": OCC_NONE}
	state["facilities"] = facs
	for raw in _run_staff(state):
		var e: Dictionary = raw
		var fid: String = String(JOB_FACILITY.get(String(e.get("job", "")), ""))
		if fid == "" or String((facs[fid] as Dictionary)["occupant"]) != OCC_NONE:
			fid = ""
			for f in FACILITIES:
				if String((facs[f] as Dictionary)["occupant"]) == OCC_NONE:
					fid = String(f)
					break
		if fid != "":
			(facs[fid] as Dictionary)["occupant"] = str(int(e.get("id", -1)))
	# The manager's slots fill what the staff left empty, in `MANAGER_AUTO_ORDER`
	# (user decision 2026-10-09: a facility nobody sits in reads its stat as 1).
	var left: int = manager_slots()
	for f in MANAGER_AUTO_ORDER:
		if left <= 0:
			break
		if String((facs[f] as Dictionary)["occupant"]) == OCC_NONE:
			(facs[f] as Dictionary)["occupant"] = OCC_MANAGER
			left -= 1


static func _fill_missing_keys(state: Dictionary) -> void:
	var facs: Dictionary = state.get("facilities", {})
	for fid in FACILITIES:
		if not facs.has(fid):
			facs[fid] = {"level": 1, "occupant": OCC_NONE}
	var r: Dictionary = state.get("research", {})
	for k in ["active", "points", "done"]:
		if not r.has(k):
			r[k] = {}
	r.erase("boosts")  # front research boosts were removed (2026-10-09)
	state["research"] = r
	if not state.has("intel_rank"):
		state["intel_rank"] = {}
	if not state.has("scout"):
		state["scout"] = {"candidates": [], "week": ""}


# After a JSON load every number is a float — turn the §16 state back into ints
# (reads are `int()`-wrapped anyway; this keeps saved and live states identical).
static func _normalize(state: Dictionary) -> void:
	for raw in (state.get("facilities", {}) as Dictionary).values():
		var e: Dictionary = raw
		e["level"] = int(e.get("level", 1))
		e["occupant"] = String(e.get("occupant", OCC_NONE))
	var r: Dictionary = state.get("research", {})
	for k in ["points", "done"]:
		var d: Dictionary = r.get(k, {})
		for key in d.keys():
			d[key] = int(d[key])
	var ranks: Dictionary = state.get("intel_rank", {})
	for key in ranks.keys():
		ranks[key] = int(ranks[key])


static func _run_staff(state: Dictionary) -> Array:
	return (state.get("run_setup", {}) as Dictionary).get("staff", [])


static func _team_package(team_id: int) -> Dictionary:
	for raw in RunRules.team_packages():
		var t: Dictionary = raw
		if int(t.get("id", -1)) == team_id:
			return t
	return {"facility_level": 1}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_warning("FacilitySystem: cannot open game.db")
		return
	db.query("SELECT * FROM facility_defs")
	for row in db.query_result:
		_defs[String(row["id"])] = {
			"id": String(row["id"]), "kind": String(row["kind"]),
			"name_key": String(row["name_key"]), "desc_key": String(row["desc_key"]),
			"stat": String(row["stat"]), "spot": String(row["spot"]),
			"icon": String(row["icon"]), "cost_pct": int(row["cost_pct"]),
		}
	db.close_db()
