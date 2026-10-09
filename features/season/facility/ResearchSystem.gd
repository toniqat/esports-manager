class_name ResearchSystem
extends RefCounted

# ── Research (§16) — rows, selection, the weekly gauge, kind-handler dispatch ─
# Contract: `docs/outgame_dev_plan.md` §16 and `features/season/facility/README.md`.
# **Frozen API** (base commit) — feature agents ask for changes, they do not edit it.
#
# Rows live in `data/csv/research.csv` (`id, facility, kind, name_key, desc_key, weeks,
# min_level, repeatable, p1, p2, icon`). A row's cost is `weeks × RESEARCH_BASE_POINTS`.
# Research is **chosen / changed only at HUB** (week not opened, `can_select`); at the
# week end (`tick_week`, from `SeasonHub._end_week` after the finance settlement) every
# facility with an occupant and an active research gains
#
#   points = RESEARCH_BASE_POINTS × level_mult(level) × stat_mult(stat) × boost_mult
#   level_mult(l) = 1 + (l − 1) × RESEARCH_LEVEL_STEP_PCT / 100
#   stat_mult(v)  = max(RESEARCH_STAT_MULT_MIN, 1 + (v − RESEARCH_STAT_PIVOT) × RESEARCH_STAT_STEP_PCT / 100)
#   boost_mult    = 1 + Σ research.boosts[].pct / 100          (rounded to int at the end)
#
# Progress is kept **per research + target** (`"<rid>|<target>"`); switching pauses the
# old one. Completion → the kind handler's `on_complete`, a HUB toast, then the facility
# goes idle unless the row is repeatable and still available (handler `row_available`
# and, for targeted rows, the target still offered by `targets`).
#
# State `season_state.research = {"active": {fid: {"rid", "target"}}, "points": {key: int},
# "done": {key: int}, "boosts": [{"pct", "weeks_left"}]}` — JSON round trip, `int()` reads.

## Research kind → handler script (static interface, see README): `targets`,
## `row_available`, `on_complete`, `make_body`.
const KINDS: Array = ["training", "intel", "mech", "front", "personnel"]
const KEY_SEP: String = "|"

static var _rows: Array = []          # research rows, CSV order
static var _by_id: Dictionary = {}    # rid → row
static var _loaded: bool = false


# ── Rows ─────────────────────────────────────────────────────────────────────
## Every row: `{id, facility, kind, name_key, desc_key, weeks, min_level, repeatable: bool,
## p1, p2, icon}` (p1 / p2 strings — meaning per kind).
static func rows() -> Array:
	_ensure_loaded()
	return _rows


static func row(rid: String) -> Dictionary:
	_ensure_loaded()
	return _by_id.get(rid, {})


## Rows of one facility, CSV order.
static func rows_for(fid: String) -> Array:
	var out: Array = []
	for raw in rows():
		if String((raw as Dictionary)["facility"]) == fid:
			out.append(raw)
	return out


static func row_name(rid: String) -> String:
	var r: Dictionary = row(rid)
	if r.is_empty():
		return rid
	return Loc.t(String(r["name_key"]))  # l10n-dynamic: research_*.**


static func row_desc(rid: String) -> String:
	var r: Dictionary = row(rid)
	if r.is_empty():
		return ""
	return Loc.t(String(r["desc_key"]))  # l10n-dynamic: research_*.**


static func row_icon(rid: String) -> Texture2D:
	return FacilitySystem.icon_texture(String(row(rid).get("icon", "")))


## Points a row costs: `weeks × RESEARCH_BASE_POINTS`.
static func cost(r: Dictionary) -> int:
	return maxi(1, int(r.get("weeks", 1)) * base_points())


static func base_points() -> int:
	return maxi(1, ConstTable.int_of("RESEARCH_BASE_POINTS"))


## Progress / done key of one research + target.
static func key_of(rid: String, target: String) -> String:
	return rid + KEY_SEP + target


# ── Availability ─────────────────────────────────────────────────────────────
## Research may be chosen / changed only at HUB, before the week opens
## (`season_state.week_day == -1`). The UI calls this to enable its pickers.
static func can_select(state: Dictionary) -> bool:
	return int(state.get("week_day", -1)) < 0


## "" when `r` can be researched in `fid` now (target aside), else the reason:
## unknown / wrong facility · min level · non-repeatable already done (untargeted rows)
## · the handler's `row_available`.
static func block_reason(state: Dictionary, fid: String, r: Dictionary) -> String:
	if r.is_empty() or String(r.get("facility", "")) != fid:
		return Loc.t(L.FACILITY_RESEARCH_BLOCK_UNKNOWN)
	if FacilitySystem.level(state, fid) < int(r.get("min_level", 1)):
		return Loc.t(L.FACILITY_RESEARCH_BLOCK_MIN_LEVEL, {"level": int(r.get("min_level", 1))})
	if not bool(r.get("repeatable", false)) and targets(state, r).is_empty() \
			and done_count(state, String(r["id"]), "") > 0:
		return Loc.t(L.FACILITY_RESEARCH_BLOCK_DONE)
	return _handler_row_available(state, r)


## Rows of `fid` that can be chosen now (`block_reason == ""`), CSV order.
static func available(state: Dictionary, fid: String) -> Array:
	var out: Array = []
	for raw in rows_for(fid):
		if block_reason(state, fid, raw) == "":
			out.append(raw)
	return out


## Targets the kind handler offers for `r`: `[{id: String, label: String, icon?: Texture2D}]`.
## Empty = the row takes no target (`target` is "").
static func targets(state: Dictionary, r: Dictionary) -> Array:
	match String(r.get("kind", "")):
		"training":
			return TrainingResearch.targets(state, r)
		"intel":
			return IntelResearch.targets(state, r)
		"mech":
			return MechResearch.targets(state, r)
		"front":
			return FrontResearch.targets(state, r)
		"personnel":
			return PersonnelResearch.targets(state, r)
	return []


## Display label of a target id for row `r` ("" for no target / unknown).
static func target_label(state: Dictionary, r: Dictionary, target: String) -> String:
	if target == "":
		return ""
	for raw in targets(state, r):
		var t: Dictionary = raw
		if String(t.get("id", "")) == target:
			return String(t.get("label", target))
	return target


# ── Selection ────────────────────────────────────────────────────────────────
## "" when `select(state, fid, rid, target)` would succeed, else the reason.
static func select_block_reason(state: Dictionary, fid: String, rid: String, target: String) -> String:
	if not can_select(state):
		return Loc.t(L.FACILITY_RESEARCH_BLOCK_WEEK_RUNNING)
	var r: Dictionary = row(rid)
	var why: String = block_reason(state, fid, r)
	if why != "":
		return why
	var offered: Array = targets(state, r)
	if offered.is_empty():
		return "" if target == "" else Loc.t(L.FACILITY_RESEARCH_BLOCK_BAD_TARGET)
	if target == "":
		return Loc.t(L.FACILITY_RESEARCH_BLOCK_NEED_TARGET)
	for raw in offered:
		if String((raw as Dictionary).get("id", "")) == target:
			return ""
	return Loc.t(L.FACILITY_RESEARCH_BLOCK_BAD_TARGET)


## Makes `rid` (+ `target`) the facility's active research. Progress of the previous
## one is kept (paused). "" on success, else the reason (nothing changed). HUB only.
static func select(state: Dictionary, fid: String, rid: String, target: String = "") -> String:
	var why: String = select_block_reason(state, fid, rid, target)
	if why != "":
		return why
	(_res(state)["active"] as Dictionary)[fid] = {"rid": rid, "target": target}
	return ""


## Stops the facility's research (progress kept). "" on success, else the reason. HUB only.
static func clear(state: Dictionary, fid: String) -> String:
	if not can_select(state):
		return Loc.t(L.FACILITY_RESEARCH_BLOCK_WEEK_RUNNING)
	(_res(state)["active"] as Dictionary).erase(fid)
	return ""


## `{rid, target}` of the facility's active research, {} when idle.
static func active(state: Dictionary, fid: String) -> Dictionary:
	var a: Variant = (_res(state)["active"] as Dictionary).get(fid, null)
	if not a is Dictionary or String((a as Dictionary).get("rid", "")) == "":
		return {}
	return {"rid": String(a["rid"]), "target": String((a as Dictionary).get("target", ""))}


# ── Progress ─────────────────────────────────────────────────────────────────
static func points(state: Dictionary, rid: String, target: String) -> int:
	return int((_res(state)["points"] as Dictionary).get(key_of(rid, target), 0))


static func done_count(state: Dictionary, rid: String, target: String) -> int:
	return int((_res(state)["done"] as Dictionary).get(key_of(rid, target), 0))


## Stored progress 0..1 of `rid` + `target` (`rid` "" = the facility's active research).
static func progress(state: Dictionary, fid: String, rid: String = "", target: String = "") -> float:
	if rid == "":
		var a: Dictionary = active(state, fid)
		if a.is_empty():
			return 0.0
		rid = String(a["rid"])
		target = String(a["target"])
	var r: Dictionary = row(rid)
	if r.is_empty():
		return 0.0
	return clampf(float(points(state, rid, target)) / float(cost(r)), 0.0, 1.0)


static func level_mult(lvl: int) -> float:
	return 1.0 + float(maxi(0, lvl - 1)) * ConstTable.num("RESEARCH_LEVEL_STEP_PCT") / 100.0


static func stat_mult(value: int) -> float:
	return maxf(ConstTable.num("RESEARCH_STAT_MULT_MIN"),
			1.0 + (float(value) - ConstTable.num("RESEARCH_STAT_PIVOT")) * ConstTable.num("RESEARCH_STAT_STEP_PCT") / 100.0)


## Summed percent of running research boosts (front `boost` research).
static func boost_pct(state: Dictionary) -> int:
	var total: int = 0
	for raw in (_res(state)["boosts"] as Array):
		total += int((raw as Dictionary).get("pct", 0))
	return total


static func boost_mult(state: Dictionary) -> float:
	return maxf(0.0, 1.0 + float(boost_pct(state)) / 100.0)


## Adds a research boost for `weeks` week ends (used by `FrontResearch.on_complete`).
static func add_boost(state: Dictionary, pct: int, weeks: int) -> void:
	if pct == 0 or weeks <= 0:
		return
	(_res(state)["boosts"] as Array).append({"pct": pct, "weeks_left": weeks})


## Points the facility would add at this week end (0 with nobody seated). Independent
## of what is selected.
static func weekly_points(state: Dictionary, fid: String) -> int:
	return _weekly_points_with(state, fid, boost_pct(state))


## Week ends until `rid` + `target` completes in `fid` at the current rate (rid "" = the
## active research). 0 = already full, -1 = never (nobody seated / unknown row).
static func weeks_left(state: Dictionary, fid: String, rid: String = "", target: String = "") -> int:
	if rid == "":
		var a: Dictionary = active(state, fid)
		if a.is_empty():
			return -1
		rid = String(a["rid"])
		target = String(a["target"])
	var r: Dictionary = row(rid)
	var per: int = weekly_points(state, fid)
	if r.is_empty() or per <= 0:
		return -1
	var need: int = cost(r) - points(state, rid, target)
	if need <= 0:
		return 0
	return ceili(float(need) / float(per))


# ── Week tick ────────────────────────────────────────────────────────────────
## Once per week end (`SeasonHub._end_week`, after `FinanceSystem.settle_week`).
## Boosts running this week apply, then lose a week (a boost bought by a completion in
## this same tick starts next week). Returns the HUB toasts (translated, never saved).
static func tick_week(state: Dictionary) -> Array:
	var res: Dictionary = _res(state)
	var bpct: int = boost_pct(state)
	var kept: Array = []
	for raw in (res["boosts"] as Array):
		var b: Dictionary = (raw as Dictionary).duplicate()
		b["weeks_left"] = int(b.get("weeks_left", 0)) - 1
		if int(b["weeks_left"]) > 0:
			kept.append(b)
	res["boosts"] = kept

	var toasts: Array = []
	var acts: Dictionary = res["active"]
	var pts: Dictionary = res["points"]
	var done: Dictionary = res["done"]
	for fid_raw in FacilitySystem.FACILITIES:
		var fid: String = String(fid_raw)
		var a: Dictionary = active(state, fid)
		if a.is_empty() or FacilitySystem.occupant(state, fid) == FacilitySystem.OCC_NONE:
			continue
		var rid: String = String(a["rid"])
		var target: String = String(a["target"])
		var r: Dictionary = row(rid)
		if r.is_empty():
			acts.erase(fid)
			continue
		if block_reason(state, fid, r) != "":
			continue  # paused (level dropped, handler blocks) — progress kept
		var key: String = key_of(rid, target)
		pts[key] = int(pts.get(key, 0)) + _weekly_points_with(state, fid, bpct)
		if int(pts[key]) < cost(r):
			continue
		pts.erase(key)
		done[key] = int(done.get(key, 0)) + 1
		var note: Dictionary = _handler_on_complete(state, r, target)
		var label: String = row_name(rid)
		var tl: String = target_label(state, r, target)
		if tl != "":
			label += " (%s)" % tl
		var line: String = Loc.t(L.FACILITY_TOAST_RESEARCH_DONE,
				{"facility": FacilitySystem.facility_name(fid), "research": label})
		var note_key: String = String(note.get("text_key", ""))
		if note_key != "":
			line += " · " + Loc.t(note_key, note.get("args", {}))  # l10n-dynamic: research_*.**
		toasts.append(line)
		if not _repeats(state, fid, r, target):
			acts.erase(fid)
	return toasts


# ── Kind-specific sheet section ──────────────────────────────────────────────
## The facility kind's extra sheet body (may be null).
static func make_body(state: Dictionary, fid: String) -> Control:
	match FacilitySystem.kind_of(fid):
		"training":
			return TrainingResearch.make_body(state, fid)
		"intel":
			return IntelResearch.make_body(state, fid)
		"mech":
			return MechResearch.make_body(state, fid)
		"front":
			return FrontResearch.make_body(state, fid)
		"personnel":
			return PersonnelResearch.make_body(state, fid)
	return null


# ── Internals ────────────────────────────────────────────────────────────────
static func _weekly_points_with(state: Dictionary, fid: String, bpct: int) -> int:
	if FacilitySystem.occupant(state, fid) == FacilitySystem.OCC_NONE:
		return 0
	var v: float = float(base_points()) * level_mult(FacilitySystem.level(state, fid)) \
			* stat_mult(FacilitySystem.stat_value(state, fid)) * maxf(0.0, 1.0 + float(bpct) / 100.0)
	return maxi(0, int(round(v)))


# Repeatable row still available (and its target still offered) → stays selected.
static func _repeats(state: Dictionary, fid: String, r: Dictionary, target: String) -> bool:
	if not bool(r.get("repeatable", false)):
		return false
	if block_reason(state, fid, r) != "":
		return false
	var offered: Array = targets(state, r)
	if offered.is_empty():
		return target == ""
	for raw in offered:
		if String((raw as Dictionary).get("id", "")) == target:
			return true
	return false


static func _handler_row_available(state: Dictionary, r: Dictionary) -> String:
	match String(r.get("kind", "")):
		"training":
			return TrainingResearch.row_available(state, r)
		"intel":
			return IntelResearch.row_available(state, r)
		"mech":
			return MechResearch.row_available(state, r)
		"front":
			return FrontResearch.row_available(state, r)
		"personnel":
			return PersonnelResearch.row_available(state, r)
	return Loc.t(L.FACILITY_RESEARCH_BLOCK_UNKNOWN)


static func _handler_on_complete(state: Dictionary, r: Dictionary, target: String) -> Dictionary:
	match String(r.get("kind", "")):
		"training":
			return TrainingResearch.on_complete(state, r, target)
		"intel":
			return IntelResearch.on_complete(state, r, target)
		"mech":
			return MechResearch.on_complete(state, r, target)
		"front":
			return FrontResearch.on_complete(state, r, target)
		"personnel":
			return PersonnelResearch.on_complete(state, r, target)
	return {}


# The research dict, with missing keys filled (old saves, states that never ran init).
static func _res(state: Dictionary) -> Dictionary:
	var r: Variant = state.get("research", null)
	if not r is Dictionary:
		r = {}
		state["research"] = r
	var d: Dictionary = r
	for k in ["active", "points", "done"]:
		if not d.get(k, null) is Dictionary:
			d[k] = {}
	if not d.get("boosts", null) is Array:
		d["boosts"] = []
	return d


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_warning("ResearchSystem: cannot open game.db")
		return
	db.query("SELECT * FROM research")
	for row_raw in db.query_result:
		var e: Dictionary = {
			"id": String(row_raw["id"]), "facility": String(row_raw["facility"]),
			"kind": String(row_raw["kind"]),
			"name_key": String(row_raw["name_key"]), "desc_key": String(row_raw["desc_key"]),
			"weeks": int(row_raw["weeks"]), "min_level": int(row_raw["min_level"]),
			"repeatable": int(row_raw["repeatable"]) != 0,
			"p1": String(row_raw["p1"]), "p2": String(row_raw["p2"]), "icon": String(row_raw["icon"]),
		}
		if not KINDS.has(String(e["kind"])):
			push_warning("ResearchSystem: unknown kind '%s' on row %s" % [e["kind"], e["id"]])
		_rows.append(e)
		_by_id[String(e["id"])] = e
	db.close_db()
