class_name StaffSystem
extends RefCounted

# ── Manager · staff effective stats (M3) — the single entry point inside a run ──
# Every read of a manager stat goes through `effective(state, stat)`
# (`docs/outgame_dev_plan.md` §2.3 · §11).
#
#   effective(stat) = max(manager[stat] + temporary mods, assistant[stat], dedicated staff[stat])
#
# - Regular staff: **one per field** (`JOB_STAT`). The assistant manager is one per
#   team and covers several stats at once. Only the manager and the assistant fill
#   several gaps at the same time.
# - Mental is the exception: interviews · outings read `manager_value(state, "mental")`
#   (manager only); only incidents read `effective_for_incident` (highest mental of anyone).
# - When `owner(state, stat)` is not "manager" the area is **delegated** — the basis
#   for the screens' auto buttons (training auto-arrange · research auto-assign ·
#   analysis interpretation · budget auto-split), see `is_delegated`.
#
# Input is always the `season_state` dictionary (no autoload dependency — so it can
# be unit-checked headlessly). `snapshot_for_run` freezes the snapshot into
# `run_setup` at run start: `run_setup.manager_type` / `.manager_stats` / `.staff`.

const STATS: Array = ["training", "tactics", "knowledge", "mental", "analysis", "finance"]
## Stat → l10n key. Values are keys — show them with `stat_label(stat)`, never raw.
const STAT_LABELS: Dictionary = {  # l10n-keys: term.manager_stat.*
	"training": L.TERM_MANAGER_STAT_TRAINING, "tactics": L.TERM_MANAGER_STAT_TACTICS, "knowledge": L.TERM_MANAGER_STAT_KNOWLEDGE,
	"mental": L.TERM_MANAGER_STAT_MENTAL, "analysis": L.TERM_MANAGER_STAT_ANALYSIS, "finance": L.TERM_MANAGER_STAT_FINANCE,
}
const STAT_MIN: int = 1
const STAT_MAX: int = 20

## Regular staff job → the stat it covers. The assistant is not here — it has all stats.
const JOB_STAT: Dictionary = {
	"coach_training": "training",
	"coach_tactics": "tactics",
	"coach_knowledge": "knowledge",
	"analyst": "analysis",
	"finance": "finance",
}
const JOB_ASSISTANT: String = "assistant"
## Job → l10n key. Values are keys — show them with `job_label(job)`, never raw.
const JOB_LABELS: Dictionary = {  # l10n-keys: staff.job.*
	"assistant": L.STAFF_JOB_ASSISTANT,
	"coach_training": L.STAFF_JOB_COACH_TRAINING,
	"coach_tactics": L.STAFF_JOB_COACH_TACTICS,
	"coach_knowledge": L.STAFF_JOB_COACH_KNOWLEDGE,
	"analyst": L.STAFF_JOB_ANALYST,
	"finance": L.STAFF_JOB_FINANCE,
}

const OWNER_MANAGER: String = "manager"
const OWNER_ASSISTANT: String = "assistant"
const OWNER_STAFF: String = "staff"

static var _types: Array = []          # manager_types rows
static var _staff: Dictionary = {}     # int id → staff row {id, name_key, job, stats{}, salary}
static var _team_staff: Dictionary = {}  # int team_id → Array[int] staff ids
static var _loaded: bool = false


# ── Tables ───────────────────────────────────────────────────────────────────
## `[{id, name_key, gender, stats{stat: int}, desc_key}]`, by id (text = l10n keys,
## `manager.type.*.name` / `.desc` — show with `Loc.t`).
static func manager_types() -> Array:
	_ensure_loaded()
	return _types


static func manager_type_row(type_id: int) -> Dictionary:
	for t in manager_types():
		if int((t as Dictionary)["id"]) == type_id:
			return t
	return {}


## `{id, name_key, job, stats{stat: int}, salary}` (`name_key` = l10n key — `staff_name`).
## Empty Dictionary when missing.
static func staff_row(staff_id: int) -> Dictionary:
	_ensure_loaded()
	return _staff.get(staff_id, {})


static func team_staff_ids(team_id: int) -> Array:
	_ensure_loaded()
	return (_team_staff.get(team_id, []) as Array).duplicate()


# ── Run snapshot ─────────────────────────────────────────────────────────────
## The piece merged into `run_setup` at run start. Manager stats = `manager_stats`
## when given (M9 — the preset's stats incl. trait bonuses, `GameManager.start_run`),
## else the type's initial values; staff = the team's initial staff as-is
## (nobody leaves during a run).
## → `{manager_type, manager_stats{stat: int}, staff: [{id, name_key, job, stats{}, salary}]}`
static func snapshot_for_run(team_id: int, manager_type: int, manager_stats: Dictionary = {}) -> Dictionary:
	var row: Dictionary = manager_type_row(manager_type)
	if row.is_empty() and not manager_types().is_empty():
		row = manager_types()[0]
	var mstats: Dictionary = {}
	for s in STATS:
		var v: int = int((row.get("stats", {}) as Dictionary).get(s, STAT_MIN))
		if manager_stats.has(s):
			v = int(manager_stats[s])
		mstats[s] = clampi(v, STAT_MIN, STAT_MAX)
	var staff: Array = []
	for sid in team_staff_ids(team_id):
		var e: Dictionary = staff_row(int(sid))
		if not e.is_empty():
			staff.append(e.duplicate(true))
	return {
		"manager_type": int(row.get("id", manager_type)),
		"manager_stats": mstats,
		"staff": staff,
	}


# ── Judgement ────────────────────────────────────────────────────────────────
## The manager's snapshot value (before mods).
static func manager_base(state: Dictionary, stat: String) -> int:
	var setup: Dictionary = state.get("run_setup", {})
	var m: Dictionary = setup.get("manager_stats", {})
	return int(m.get(stat, STAT_MIN))


## Sum of temporary mods on this stat (`staff_mods`).
static func mod_total(state: Dictionary, stat: String) -> int:
	var total: int = 0
	for raw in (state.get("staff_mods", []) as Array):
		var m: Dictionary = raw
		if String(m.get("stat", "")) == stat:
			total += int(m.get("delta", 0))
	return total


## Manager value = snapshot + temporary mods, clamped to [STAT_MIN, STAT_MAX].
static func manager_value(state: Dictionary, stat: String) -> int:
	return clampi(manager_base(state, stat) + mod_total(state, stat), STAT_MIN, STAT_MAX)


## The assistant manager (empty Dictionary when none).
static func assistant(state: Dictionary) -> Dictionary:
	for raw in _run_staff(state):
		var e: Dictionary = raw
		if String(e.get("job", "")) == JOB_ASSISTANT:
			return e
	return {}


## The dedicated regular staff for this stat (one per field; empty when none).
static func staff_for(state: Dictionary, stat: String) -> Dictionary:
	for raw in _run_staff(state):
		var e: Dictionary = raw
		if String(JOB_STAT.get(String(e.get("job", "")), "")) == stat:
			return e
	return {}


static func effective(state: Dictionary, stat: String) -> int:
	return int(_best(state, stat)["value"])


## Who covers this stat — "manager" / "assistant" / "staff". Ties go
## staff → assistant → manager (the delegated side wins: same result, less hands-on work).
static func owner(state: Dictionary, stat: String) -> String:
	return String(_best(state, stat)["owner"])


## Display name of whoever covers it (`term.person.manager` for the manager).
static func owner_name(state: Dictionary, stat: String) -> String:
	var b: Dictionary = _best(state, stat)
	if String(b["owner"]) == OWNER_MANAGER:
		return Loc.t(L.TERM_PERSON_MANAGER)
	return staff_name(b["who"] as Dictionary)


## Display name of a stat key (`STATS`), current locale. Unknown key → "?".
static func stat_label(stat: String) -> String:
	if not STAT_LABELS.has(stat):
		return "?"
	return Loc.t(String(STAT_LABELS[stat]))  # l10n-dynamic: term.manager_stat.*


## Display name of a staff job (`JOB_LABELS` keys), current locale. Unknown job → `term.person.staff`.
static func job_label(job: String) -> String:
	if not JOB_LABELS.has(job):
		return Loc.t(L.TERM_PERSON_STAFF)
	return Loc.t(String(JOB_LABELS[job]))  # l10n-dynamic: staff.job.*


## Display text of a `staff_mods.source` id (D7 — the saved value is an id, never text):
## `finance:<special id>` → that special's name, `mental:<event id>` → the event's kind
## (interview / outing / press / incident). Empty → "", anything else → unchanged.
static func mod_source_text(source: String) -> String:
	if source.begins_with(FinanceSystem.MOD_SOURCE_PREFIX):
		return FinanceSystem.mod_source_text(source)
	if source.begins_with(MentalEvents.MOD_SOURCE_PREFIX):
		return MentalEvents.mod_source_text(source)
	return source


## 스태프 한 명(`staff_row` · 런 스냅샷 `staff[]`)의 표시 이름. 행에는 l10n key 만 있다(D7).
static func staff_name(e: Dictionary) -> String:
	var key: String = String(e.get("name_key", ""))
	if key.is_empty():
		return "—"
	return Loc.t(key)  # l10n-dynamic: name.staff.*


## Is the area delegated — whether screens show their auto button.
static func is_delegated(state: Dictionary, stat: String) -> bool:
	return owner(state, stat) != OWNER_MANAGER


## Incident-handling mental — max of manager (with mods), assistant and **any** staff mental.
static func effective_for_incident(state: Dictionary) -> int:
	var v: int = manager_value(state, "mental")
	for raw in _run_staff(state):
		v = maxi(v, int(((raw as Dictionary).get("stats", {}) as Dictionary).get("mental", 0)))
	return v


## Sum of staff weekly salaries (finance expense).
static func weekly_salary_total(state: Dictionary) -> int:
	var total: int = 0
	for raw in _run_staff(state):
		total += int((raw as Dictionary).get("salary", 0))
	return total


## Analysis reveal tier 0..3 — how many `ANALYSIS_TIER_1..3` (const.csv) thresholds are met.
## 0 = name · role, 1 = + rough stats, 2 = + top-mastery mechs, 3 = + pilot cards.
## M8 — the `analysis_tier` traits shift the result (clamped 0..3).
static func analysis_tier(state: Dictionary) -> int:
	var v: int = effective(state, "analysis")
	var tier: int = 0
	for i in range(1, 4):
		if v >= ConstTable.int_of("ANALYSIS_TIER_%d" % i):
			tier = i
	return clampi(tier + TraitSystem.run_mod(state, "analysis_tier"), 0, 3)


# ── Temporary mods ───────────────────────────────────────────────────────────
## Temporary manager-stat mod for `weeks` weeks (minus one per week end, gone at 0).
static func add_mod(state: Dictionary, stat: String, delta: int, weeks: int, source: String = "") -> void:
	if not STATS.has(stat) or delta == 0 or weeks <= 0:
		return
	var mods: Array = state.get("staff_mods", [])
	mods.append({"stat": stat, "delta": delta, "weeks_left": weeks, "source": source})
	state["staff_mods"] = mods


## Once per week end (`SeasonHub._end_week`).
static func decay_mods(state: Dictionary) -> void:
	var kept: Array = []
	for raw in (state.get("staff_mods", []) as Array):
		var m: Dictionary = (raw as Dictionary).duplicate()
		m["weeks_left"] = int(m.get("weeks_left", 0)) - 1
		if int(m["weeks_left"]) > 0:
			kept.append(m)
	state["staff_mods"] = kept


# ── Coach points (§15 D, afternoon visit focus training) ─────────────────────
# A weekly budget: `COACH_POINTS_BASE + COACH_POINTS_PER × effective(training)`
# (floored), granted when a week starts and never carried over. State:
# `season_state.coach_points` (int, this week) + `coach_week` (the week key it was
# granted for). A read in a new week grants it lazily, so old saves and a week that
# started without `grant_coach_points` still get their points exactly once.

## The week's grant for the current training stat (display: "주간 N").
static func coach_points_grant(state: Dictionary) -> int:
	return maxi(0, ConstTable.int_of("COACH_POINTS_BASE")
			+ floori(ConstTable.num("COACH_POINTS_PER") * float(effective(state, "training"))))


## Start-of-week grant (`SeasonHub.on_training_confirmed`): resets the balance.
static func grant_coach_points(state: Dictionary) -> void:
	state["coach_points"] = coach_points_grant(state)
	state["coach_week"] = MentalSystem.week_key(state)


## Points left this week (granted lazily on the first read of a new week).
static func coach_points(state: Dictionary) -> int:
	if String(state.get("coach_week", "")) != MentalSystem.week_key(state):
		grant_coach_points(state)
	return int(state.get("coach_points", 0))


## Spend `n` points; false (nothing spent) when the balance is short.
static func spend_coach_points(state: Dictionary, n: int) -> bool:
	var have: int = coach_points(state)
	if n > have:
		return false
	state["coach_points"] = have - maxi(0, n)
	return true


# ── Internals ────────────────────────────────────────────────────────────────
static func _run_staff(state: Dictionary) -> Array:
	return (state.get("run_setup", {}) as Dictionary).get("staff", [])


# {value, owner, who} — ties are taken staff → assistant → manager.
static func _best(state: Dictionary, stat: String) -> Dictionary:
	var best: Dictionary = {"value": manager_value(state, stat), "owner": OWNER_MANAGER, "who": {}}
	var asst: Dictionary = assistant(state)
	if not asst.is_empty():
		var av: int = int((asst.get("stats", {}) as Dictionary).get(stat, 0))
		if av >= int(best["value"]):
			best = {"value": av, "owner": OWNER_ASSISTANT, "who": asst}
	var st: Dictionary = staff_for(state, stat)
	if not st.is_empty():
		var sv: int = int((st.get("stats", {}) as Dictionary).get(stat, 0))
		if sv >= int(best["value"]):
			best = {"value": sv, "owner": OWNER_STAFF, "who": st}
	return best


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_warning("StaffSystem: cannot open game.db")
		return
	db.query("SELECT * FROM manager_types ORDER BY id")
	for row in db.query_result:
		_types.append({
			"id": int(row["id"]), "name_key": String(row["name_key"]),
			"gender": String(row["gender"]), "stats": _stats_of(row),
			"desc_key": String(row["desc_key"]),
		})
	db.query("SELECT * FROM staff ORDER BY id")
	for row in db.query_result:
		_staff[int(row["id"])] = {
			"id": int(row["id"]), "name_key": String(row["name_key"]),
			"job": String(row["job"]), "stats": _stats_of(row),
			"salary": int(row["salary"]),
		}
	db.query("SELECT id, staff_ids FROM teams ORDER BY id")
	for row in db.query_result:
		var ids: Array = []
		for part in String(row.get("staff_ids", "")).split("|", false):
			if (part as String).strip_edges().is_valid_int():
				ids.append(int(part))
		_team_staff[int(row["id"])] = ids
	db.close_db()


static func _stats_of(row: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for s in STATS:
		out[s] = int(row.get(s, STAT_MIN))
	return out
