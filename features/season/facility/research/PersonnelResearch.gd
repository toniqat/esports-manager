class_name PersonnelResearch
extends RefCounted

# ── Research kind handler: `personnel` (§16, decision 10) ──
# Rows of facility `personnel` with `p1 = scout` (`p2` = extra candidates, "" = 0).
# Completion draws `SCOUT_BASE + level × SCOUT_PER_LEVEL + p2` staff from the scouting pool
# (`staff.csv` rows on no team's `staff_ids`, minus anyone already on the run team) and
# stores their ids in `season_state.scout = {candidates: [int], week: String}` — a new list
# replaces an unanswered one. The draw is seeded per run · week · row · completion count,
# so a reload gives the same list.
# The player answers in the facility sheet body (`staff/PersonnelBody`): hire one
# (`hire_candidate` → `StaffSystem.hire`, the list is consumed) or pass on all (`pass_all`).
# Contract: `features/season/facility/README.md` "Kind handlers" + "PersonnelResearch".

const P1_SCOUT: String = "scout"
const FACILITY: String = "personnel"


## Targets offered for `row`: none (scouting has no target).
static func targets(_state: Dictionary, _row: Dictionary) -> Array:
	return []


## "" when `row` may be researched now; a scout row is blocked while the pool is empty.
static func row_available(state: Dictionary, row: Dictionary) -> String:
	if String(row.get("p1", "")) == P1_SCOUT and pool(state).is_empty():
		return Loc.t(L.RESEARCH_PERSONNEL_BLOCK_NO_POOL)
	return ""


## Scout completed → a fresh candidate list. Note = "영입 후보 n명" (or "찾은 후보 없음").
static func on_complete(state: Dictionary, row: Dictionary, _target: String) -> Dictionary:
	if String(row.get("p1", "")) != P1_SCOUT:
		return {"text_key": "", "args": {}}
	var rid: String = String(row.get("id", ""))
	var seed_text: String = "%d|%s|%s|%d" % [int(state.get("run_seed", 0)), MentalSystem.week_key(state),
			rid, ResearchSystem.done_count(state, rid, "")]
	var ids: Array = draw(state, candidate_count(state, row), hash(seed_text))
	var sc: Dictionary = _scout(state)
	sc["candidates"] = ids
	sc["week"] = MentalSystem.week_key(state)
	if ids.is_empty():
		return {"text_key": L.RESEARCH_PERSONNEL_NOTE_NONE, "args": {}}
	return {"text_key": L.RESEARCH_PERSONNEL_NOTE_CANDIDATES, "args": {"n": ids.size()}}


## Personnel section of the facility sheet: staff list (dismiss) + candidates (hire / pass).
## The body emits `changed` after any of them — the host refreshes its occupant picker.
static func make_body(state: Dictionary, _fid: String) -> Control:
	var body := PersonnelBody.create()
	body.bind(state)
	return body


# ── Scouting ─────────────────────────────────────────────────────────────────
## Candidates a scout row yields now: `SCOUT_BASE + level × SCOUT_PER_LEVEL + p2`.
static func candidate_count(state: Dictionary, row: Dictionary = {}) -> int:
	return maxi(0, ConstTable.int_of("SCOUT_BASE")
			+ FacilitySystem.level(state, FACILITY) * ConstTable.int_of("SCOUT_PER_LEVEL")
			+ String(row.get("p2", "")).to_int())


## The scouting pool: free agents (`StaffSystem.free_agent_ids`) not on the run team.
static func pool(state: Dictionary) -> Array:
	var out: Array = []
	for sid in StaffSystem.free_agent_ids():
		if not StaffSystem.is_hired(state, int(sid)):
			out.append(int(sid))
	return out


## `n` distinct ids from the pool, shuffled with `seed_value` (fewer when the pool is small).
static func draw(state: Dictionary, n: int, seed_value: int) -> Array:
	var ids: Array = pool(state)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(ids.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp
	return ids.slice(0, mini(n, ids.size()))


## Unanswered candidate ids (anyone hired meanwhile is skipped), as ints.
static func candidates(state: Dictionary) -> Array:
	var out: Array = []
	for raw in (_scout(state).get("candidates", []) as Array):
		var sid: int = int(raw)
		if not StaffSystem.staff_row(sid).is_empty() and not StaffSystem.is_hired(state, sid):
			out.append(sid)
	return out


## Hires one candidate (`StaffSystem.hire`) and consumes the list. "" on success, else the
## reason (nothing changed).
static func hire_candidate(state: Dictionary, staff_id: int) -> String:
	if not candidates(state).has(staff_id):
		return Loc.t(L.STAFF_BLOCK_UNKNOWN)
	var why: String = StaffSystem.hire(state, staff_id)
	if why == "":
		pass_all(state)
	return why


## Passes on every candidate (the list is emptied; the next scout draws again).
static func pass_all(state: Dictionary) -> void:
	_scout(state)["candidates"] = []


static func _scout(state: Dictionary) -> Dictionary:
	if not (state.get("scout", null) is Dictionary):
		state["scout"] = {"candidates": [], "week": ""}
	var sc: Dictionary = state["scout"]
	if not sc.has("candidates"):
		sc["candidates"] = []
	return sc
