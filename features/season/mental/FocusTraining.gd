class_name FocusTraining
extends RefCounted

# ── Focus training (집중 훈련, §15 D) — one afternoon visit option ─────────────
# The manager trains one pilot personally for coach points (`StaffSystem.coach_points`).
# A course feeds two stats with `FOCUS_STAT_EXP` stat EXP each, through the same
# EXP → point rule as the training board (`season_state.training_exp_carry`, the
# week's leftover bank, `TRAINING_EXP_PER_POINT` EXP = 1 point), and that EXP also
# counts as training EXP (`TrainingLevel.add_exp`). It also raises the awakening gauge
# (`FOCUS_AWAKEN`) and stress (`FOCUS_STRESS`). 한계돌파 (only while a limit-break goal
# is active) finishes the goal at once (`LimitBreak.complete`).
#
# The shared helpers below are used by the story clauses too (`MentalEvents`
# `train_bonus` / `tlexp` / `mastery`). Every result is a list of **note dicts**
# (keys / ids only, saved in the afternoon record) — `MentalEvents.note_text` draws them.
# Static, takes `season_state` (no autoloads), like `MentalSystem`.

const COURSE_LIMIT_BREAK: String = "limit_break"

## Course id → the two stats it feeds (`PlayerData.STAT_KEYS`) + its name key. Order = menu order.
const COURSES: Array = [
	{"id": "aggression", "stats": ["field_hit", "engage_hit"], "name": L.MENTAL_UI_VISIT_COURSE_AGGRESSION},
	{"id": "caution", "stats": ["field_eva", "engage_eva"], "name": L.MENTAL_UI_VISIT_COURSE_CAUTION},
	{"id": "operation", "stats": ["field_hit", "field_eva"], "name": L.MENTAL_UI_VISIT_COURSE_OPERATION},
	{"id": "combat", "stats": ["engage_hit", "engage_eva"], "name": L.MENTAL_UI_VISIT_COURSE_COMBAT},
	{"id": "growth", "stats": ["atk_growth", "hp_growth"], "name": L.MENTAL_UI_VISIT_COURSE_GROWTH},
	{"id": COURSE_LIMIT_BREAK, "stats": [], "name": L.MENTAL_UI_VISIT_COURSE_LIMIT_BREAK},
]


static func course(id: String) -> Dictionary:
	for c in COURSES:
		if String((c as Dictionary)["id"]) == id:
			return c
	return {}


static func course_name(id: String) -> String:
	var c: Dictionary = course(id)
	return Loc.t(String(c["name"])) if not c.is_empty() else id  # l10n-dynamic: mental.ui.visit.course.*


## Coach points a course costs.
static func cost_of(id: String) -> int:
	return ConstTable.int_of("FOCUS_COST_LIMIT_BREAK") if id == COURSE_LIMIT_BREAK \
			else ConstTable.int_of("FOCUS_COST")


## Why `pid` cannot take course `id` now ("" = it can): unknown course, no active
## limit-break goal (한계돌파), or too few coach points.
static func refusal(state: Dictionary, pid: int, id: String) -> String:
	if course(id).is_empty():
		return "?"
	if id == COURSE_LIMIT_BREAK and not LimitBreak.goal_active(state, pid):
		return Loc.t(L.MENTAL_UI_VISIT_NEED_GOAL)
	if StaffSystem.coach_points(state) < cost_of(id):
		return Loc.t(L.MENTAL_UI_VISIT_NEED_POINTS, {"n": cost_of(id)})
	return ""


## Menu rows: `[{id, name, stats (display), cost, enabled, reason}]`. 한계돌파 is listed only
## while that pilot has an active limit-break goal.
static func courses_view(state: Dictionary, pid: int) -> Array:
	var out: Array = []
	for c_raw in COURSES:
		var c: Dictionary = c_raw
		var id: String = String(c["id"])
		if id == COURSE_LIMIT_BREAK and not LimitBreak.goal_active(state, pid):
			continue
		var stats: PackedStringArray = PackedStringArray()
		for st in (c["stats"] as Array):
			stats.append(MentalEvents.stat_label(String(st)))
		var line: String = Loc.t(L.UI_LIST_SEPARATOR).join(stats) if not stats.is_empty() \
				else LimitBreak.goal_text(state, pid)
		var why: String = refusal(state, pid, id)
		out.append({"id": id, "name": course_name(id), "stats": line, "cost": cost_of(id),
				"enabled": why == "", "reason": why})
	return out


## Run course `id` on `pid` (cost paid here). → outcome `{checked: false, ok: true, chance: -1,
## pilot_id, partner_id: -1, say: [], notes: [note dict], course}` — the same shape as a mental
## outcome, so the afternoon record and `MentalEvents.outcome_view` read it unchanged.
## {} when refused (`refusal`).
static func apply(state: Dictionary, pid: int, id: String) -> Dictionary:
	if refusal(state, pid, id) != "":
		return {}
	var cost: int = cost_of(id)
	StaffSystem.spend_coach_points(state, cost)
	var notes: Array = [{"type": "coach", "delta": -cost}]
	if id == COURSE_LIMIT_BREAK:
		LimitBreak.complete(state, pid)
		notes.append({"type": "limit_break", "pid": pid, "level": TrainingLevel.level(state, pid)})
	else:
		var add: Dictionary = {}
		for st in (course(id)["stats"] as Array):
			add[String(st)] = ConstTable.int_of("FOCUS_STAT_EXP")
		notes.append_array(add_stat_exp(state, pid, add))
	var gauge: int = ConstTable.int_of("FOCUS_AWAKEN")
	if gauge != 0:
		Awakening.add_gauge(state, pid, gauge, "focus")
		notes.append({"type": "awaken", "pid": pid, "delta": gauge})
	var sd: int = StressSystem.add(state, pid, ConstTable.int_of("FOCUS_STRESS"))
	if sd != 0:
		notes.append({"type": "stress", "pid": pid, "delta": sd})
	return {"checked": false, "ok": true, "chance": -1, "pilot_id": pid, "partner_id": -1,
			"say": [], "notes": notes, "course": id}


# ── Shared helpers (focus training + story clauses) ──────────────────────────
## Stat EXP `{stat: amount}` into `pid`'s leftover bank (`training_exp_carry[seat]`), whole
## points raise the stats (the training board's rule), and the sum counts as training EXP.
## → notes: one `stat_up` per raised stat (none raised → one `stat_exp`), then `tlexp`.
static func add_stat_exp(state: Dictionary, pid: int, add: Dictionary) -> Array:
	var notes: Array = []
	var pd: PlayerData = MentalEvents.pilot_of(state, pid)
	if pd == null:
		return notes
	var per: int = maxi(1, ConstTable.int_of("TRAINING_EXP_PER_POINT"))
	var seat: int = GameEnums.role_seat(pd.role)
	var carry: Dictionary = state.get("training_exp_carry", {})
	state["training_exp_carry"] = carry
	var pocket: Dictionary = carry.get(seat, carry.get(str(seat), {}))
	carry.erase(str(seat))
	carry[seat] = pocket
	var total: int = 0
	for sk in PlayerData.STAT_KEYS:
		var key: String = String(sk)
		var earned: int = maxi(0, int(add.get(key, 0)))
		if earned == 0:
			continue
		total += earned
		var sum: int = int(pocket.get(key, 0)) + earned
		var up: int = floori(float(sum) / float(per))
		pocket[key] = sum - up * per
		if up != 0:
			pd.set(key, maxi(PlayerData.STAT_MIN, int(pd.get(key)) + up))
			notes.append({"type": "stat_up", "pid": pid, "stat": key, "delta": up})
	if total <= 0:
		return notes
	if notes.is_empty():
		notes.append({"type": "stat_exp", "pid": pid, "delta": total})
	notes.append(add_training_exp(state, pid, total))
	return notes


## Training EXP (`TrainingLevel.add_exp`) → a `tlexp` note with the amount applied
## (0 = the bar is full, the note says a limit break is needed).
static func add_training_exp(state: Dictionary, pid: int, amount: int) -> Dictionary:
	return {"type": "tlexp", "pid": pid, "delta": TrainingLevel.add_exp(state, pid, maxi(0, amount))}


## Mastery gain on the story mech (`story_mech`) → a `mastery` note with the points the bar
## actually moved, {} when there is no mech or nothing moved.
static func add_story_mastery(state: Dictionary, pid: int, amount: int) -> Dictionary:
	var mech: int = story_mech(state, pid)
	if mech < 0 or amount <= 0:
		return {}
	var before: int = MechMastery.value(state, pid, mech)
	MechMastery.gain(state, pid, mech, amount)
	var moved: int = MechMastery.value(state, pid, mech) - before
	if moved == 0:
		return {}
	return {"type": "mastery", "pid": pid, "mech": mech, "delta": moved}


## The mech a story's `mastery:` clause trains: the mech `pid` was given in this week's
## Saturday ban/pick (`pending_match.picks.player_assigned_mech_ids`, indexed by role), else
## the weekly research mech, else the coach's pick (`MechMastery.auto_research_mech`).
static func story_mech(state: Dictionary, pid: int) -> int:
	var pd: PlayerData = MentalEvents.pilot_of(state, pid)
	if pd == null:
		return -1
	var pm: Variant = state.get("pending_match", null)
	if pm is Dictionary and (pm as Dictionary).get("picks", null) is Dictionary:
		var ids: Variant = ((pm as Dictionary)["picks"] as Dictionary).get("player_assigned_mech_ids", [])
		if ids is Array and pd.role >= 0 and pd.role < (ids as Array).size() \
				and int((ids as Array)[pd.role]) >= 0:
			return int((ids as Array)[pd.role])
	var mech: int = MechMastery.research_mech(state, pid)
	if mech < 0:
		mech = MechMastery.auto_research_mech(state, pd)
	return mech
