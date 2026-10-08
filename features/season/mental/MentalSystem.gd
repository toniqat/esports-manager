class_name MentalSystem
extends RefCounted

# ── Mental — trust · interviews · outings · incidents · press (M7) ────────────
# Contract: `docs/outgame_dev_plan.md` §11. State lives in `season_state`:
#   trust   {"<pid>": int}   my 5 pilots, [TRUST_MIN, TRUST_MAX]
#   outings {"<pid>": int}   outings taken this run (true ending counter)
#   mental  {week, interviews_used, outings_used, days{"<day>": {...}}, fatigue{}, press{}}
# Full shape in `features/season/mental/README.md`. All keys are strings and numbers
# may come back as floats after save/load — every read goes through int().
#
# Every action is **recorded before it is shown** and settled at most once:
# the week screen can be rebuilt on the same weekday (after a match, after
# load), so `days["<day>"]` keeps the drawn event and the chosen answer.
# Random draws are seeded from `run_seed` + week + day, so reloading never rerolls.

const ACTION_INTERVIEW: String = "interview"
const ACTION_OUTING: String = "outing"
const ACTION_PASS: String = "pass"


## Once at run start (`GameManager.start_run`) — trust baseline for my 5 pilots.
static func init_run(state: Dictionary) -> void:
	var trust_d: Dictionary = {}
	var outing_d: Dictionary = {}
	for pid in my_pilot_ids(state):
		trust_d[str(pid)] = ConstTable.int_of("TRUST_START")
		outing_d[str(pid)] = 0
	state["trust"] = trust_d
	state["outings"] = outing_d
	state["mental"] = _fresh_mental()
	StressSystem.init_run(state)


## Week end (`SeasonHub._end_week`, before the calendar moves) — weekly limits
## reset; a Friday outing's fatigue moves on to next Monday.
static func end_week(state: Dictionary) -> void:
	var m: Dictionary = _mental(state)
	var kept: Dictionary = {}
	var fat: Dictionary = m.get("fatigue", {})
	for k in fat.keys():
		var d: int = int(fat[k])
		if d >= CalendarSystem.TRAINING_DAYS:
			kept[str(k)] = d - CalendarSystem.TRAINING_DAYS
	m["fatigue"] = kept
	m["week"] = ""
	m["interviews_used"] = 0
	m["outings_used"] = 0
	m["days"] = {}


## Training EXP multiplier for that pilot on training day `day` (0 = Mon .. 4 = Fri).
## The day after an outing costs `MENTAL_OUTING_EXP_MULT`. `TrainingBoard` multiplies it.
static func training_exp_mult(state: Dictionary, pilot_id: int, day: int) -> float:
	var fat: Dictionary = (state.get("mental", {}) as Dictionary).get("fatigue", {})
	var key: String = str(pilot_id)
	if fat.has(key) and int(fat[key]) == day:
		return ConstTable.num("MENTAL_OUTING_EXP_MULT")
	return 1.0


static func trust(state: Dictionary, pilot_id: int) -> int:
	return int((state.get("trust", {}) as Dictionary).get(str(pilot_id), 0))


static func outings(state: Dictionary, pilot_id: int) -> int:
	return int((state.get("outings", {}) as Dictionary).get(str(pilot_id), 0))


## Pilots whose true ending is reached — **only meaningful when the run is
## cleared** (`RunResult` calls it for outcome "clear"): outings ≥ `TRUE_ENDING_OUTINGS`.
static func true_ending_pilots(state: Dictionary) -> Array:
	var need: int = ConstTable.int_of("TRUE_ENDING_OUTINGS")
	var out: Array = []
	for pid in my_pilot_ids(state):
		if outings(state, int(pid)) >= need:
			out.append(int(pid))
	return out


## My 5 pilots (`run_setup.pilot_ids`, fallback: player team roster).
static func my_pilot_ids(state: Dictionary) -> Array:
	var out: Array = []
	for raw in ((state.get("run_setup", {}) as Dictionary).get("pilot_ids", []) as Array):
		out.append(int(raw))
	if out.is_empty():
		var rosters: Dictionary = state.get("team_rosters", {})
		var tid: int = int(state.get("player_team_id", 0))
		var roster: Variant = rosters.get(tid, rosters.get(str(tid), []))
		if roster is Array:
			for raw in (roster as Array):
				out.append(int(raw))
	return out


## Change trust, clamped. Returns the delta actually applied.
static func add_trust(state: Dictionary, pilot_id: int, delta: int) -> int:
	# M8 trait `trust_gain`: only a rise is adjusted, and never below 0 (a rise
	# cannot turn into a loss). Drops pass through untouched.
	var applied: int = delta
	if delta > 0:
		applied = maxi(0, delta + TraitSystem.run_mod(state, "trust_gain"))
	var t: Dictionary = state.get("trust", {})
	var before: int = trust(state, pilot_id)
	var after: int = clampi(before + applied, ConstTable.int_of("TRUST_MIN"), ConstTable.int_of("TRUST_MAX"))
	t[str(pilot_id)] = after
	state["trust"] = t
	return after - before


# ── Weekly limits ────────────────────────────────────────────────────────────
## Interviews allowed per week — scales with the manager's own mental
## (`StaffSystem.manager_value`; staff never interview).
static func interviews_per_week(state: Dictionary) -> int:
	var mental_v: int = StaffSystem.manager_value(state, "mental")
	var per: int = maxi(1, ConstTable.int_of("MENTAL_INTERVIEWS_PER_STAT"))
	return clampi(ConstTable.int_of("MENTAL_INTERVIEWS_BASE") + floori(float(mental_v) / float(per)),
			0, ConstTable.int_of("MENTAL_INTERVIEWS_MAX"))


static func interviews_left(state: Dictionary) -> int:
	return maxi(0, interviews_per_week(state) - int(_week(state).get("interviews_used", 0)))


static func outings_left(state: Dictionary) -> int:
	return maxi(0, ConstTable.int_of("MENTAL_OUTINGS_PER_WEEK") - int(_week(state).get("outings_used", 0)))


static func outing_unlocked(state: Dictionary, pilot_id: int) -> bool:
	return trust(state, pilot_id) >= ConstTable.int_of("TRUST_OUTING_MIN")


static func can_interview(state: Dictionary) -> bool:
	return interviews_left(state) > 0


static func can_outing(state: Dictionary, pilot_id: int) -> bool:
	return outings_left(state) > 0 and outing_unlocked(state, pilot_id)


# ── Evening (one action per Mon–Fri) ─────────────────────────────────────────
## That weekday's evening record, or {} when nothing was chosen yet.
## `{action, pilot_id, event, choice(-1 = dialog open), outcome{}}`.
static func evening(state: Dictionary, day: int) -> Dictionary:
	return (_day(state, day).get("evening", {}) as Dictionary)


static func evening_done(state: Dictionary, day: int) -> bool:
	var e: Dictionary = evening(state, day)
	return not e.is_empty() and (String(e.get("action", "")) == ACTION_PASS or int(e.get("choice", -1)) >= 0)


## Start the evening action. Returns a session (`session_view` draws it) or {}
## when refused (limits, already used, pass). Re-calling on a day whose dialog
## is still open returns the same session (same event).
static func begin_evening(state: Dictionary, day: int, action: String, pilot_id: int) -> Dictionary:
	if not CalendarSystem.is_training_day(day):
		return {}
	var rec: Dictionary = _day(state, day)
	var e: Dictionary = rec.get("evening", {})
	if not e.is_empty():
		if int(e.get("choice", -1)) < 0 and String(e.get("action", "")) != ACTION_PASS:
			return _session_of(e)
		return {}
	if action == ACTION_PASS:
		rec["evening"] = {"action": ACTION_PASS, "pilot_id": -1, "event": "", "choice": -1, "outcome": {}}
		return {}
	if not my_pilot_ids(state).has(pilot_id):
		return {}
	var r: Dictionary = {}
	if action == ACTION_INTERVIEW:
		if not can_interview(state):
			return {}
		r = _draw(state, MentalEvents.KIND_INTERVIEW, pilot_id, _seed(state, day, "interview", pilot_id))
	elif action == ACTION_OUTING:
		if not can_outing(state, pilot_id):
			return {}
		r = outing_row(state, pilot_id)
	if r.is_empty():
		return {}
	e = {"action": action, "pilot_id": pilot_id, "event": String(r["id"]), "choice": -1, "outcome": {}}
	rec["evening"] = e
	return _session_of(e)


## Settle the evening dialog with answer `choice`. Idempotent — a second call
## returns the stored outcome without applying anything.
static func finish_evening(state: Dictionary, day: int, choice: int) -> Dictionary:
	var e: Dictionary = evening(state, day)
	if e.is_empty() or String(e.get("action", "")) == ACTION_PASS:
		return {}
	if int(e.get("choice", -1)) >= 0:
		return e.get("outcome", {})
	var r: Dictionary = MentalEvents.row(String(e["event"]))
	var pid: int = int(e["pilot_id"])
	var judge: int = StaffSystem.manager_value(state, "mental")
	var out: Dictionary = MentalEvents.apply_choice(state, r, choice, pid, judge,
			_seed(state, day, "evening_check", choice))
	# Base stress relief of the talk / outing itself, on top of the row's `stress:` clauses.
	var relief: int = StressSystem.relieve(state, pid, String(e["action"]))
	if relief != 0:
		(out["notes"] as Array).append({"type": "stress", "pid": pid, "delta": relief})
	var w: Dictionary = _week(state)
	if String(e["action"]) == ACTION_INTERVIEW:
		w["interviews_used"] = int(w.get("interviews_used", 0)) + 1
	else:
		w["outings_used"] = int(w.get("outings_used", 0)) + 1
		var o: Dictionary = state.get("outings", {})
		o[str(pid)] = outings(state, pid) + 1
		state["outings"] = o
		# The next training day pays for the night out (Friday → next Monday,
		# carried over by `end_week`).
		var fat: Dictionary = _mental(state).get("fatigue", {})
		fat[str(pid)] = day + 1
		_mental(state)["fatigue"] = fat
		(out["notes"] as Array).append({"type": "outing", "count": outings(state, pid)})
	e["choice"] = choice
	e["outcome"] = out
	return out


## Outing row for that pilot's next stage (`outings + 1`); a stage written for
## the run's manager type wins over the generic one. Past the last written
## stage the highest stage repeats.
static func outing_row(state: Dictionary, pilot_id: int) -> Dictionary:
	var want: int = outings(state, pilot_id) + 1
	var best: Dictionary = {}
	var best_stage: int = -1
	for r_raw in MentalEvents.rows_of(MentalEvents.KIND_OUTING):
		var r: Dictionary = r_raw
		if not MentalEvents.type_ok(state, r) or not MentalEvents.cond_ok(state, r, pilot_id):
			continue
		var st: int = int(r["stage"])
		if st > want:
			continue
		var typed: bool = int(r["manager_type"]) >= 0
		if st > best_stage or (st == best_stage and typed):
			best = r
			best_stage = st
	return best


# ── Incidents (rolled on Mon–Fri day screens) ────────────────────────────────
## Roll that weekday's incident once (chance `MENTAL_INCIDENT_CHANCE` ×
## `FinanceSystem.incident_mult` × trait `incident_pct`, M8). Returns the incident record or {} (none).
## `{event, pilot_id, choice(-1 = unresolved), outcome{}}`.
static func ensure_incident(state: Dictionary, day: int) -> Dictionary:
	if not CalendarSystem.is_training_day(day):
		return {}
	var rec: Dictionary = _day(state, day)
	if rec.has("incident"):
		return rec["incident"]
	var inc: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(state, day, "incident", 0)
	var chance: float = ConstTable.num("MENTAL_INCIDENT_CHANCE") * FinanceSystem.incident_mult(state) \
			* TraitSystem.run_pct_mult(state, "incident_pct")
	var mine: Array = my_pilot_ids(state)
	if rng.randf() < chance and not mine.is_empty():
		var pid: int = int(mine[rng.randi_range(0, mine.size() - 1)])
		var r: Dictionary = _draw(state, MentalEvents.KIND_INCIDENT, pid, rng.randi())
		if not r.is_empty():
			inc = {"event": String(r["id"]), "pilot_id": pid, "choice": -1, "outcome": {}}
	rec["incident"] = inc
	return inc


static func incident_pending(state: Dictionary, day: int) -> bool:
	var inc: Dictionary = _day(state, day).get("incident", {})
	return not inc.is_empty() and int(inc.get("choice", -1)) < 0


static func incident_session(state: Dictionary, day: int) -> Dictionary:
	var inc: Dictionary = _day(state, day).get("incident", {})
	if inc.is_empty():
		return {}
	return {"kind": MentalEvents.KIND_INCIDENT, "event": String(inc["event"]),
			"pilot_id": int(inc["pilot_id"])}


## Resolve the incident with answer `choice` — judged by `StaffSystem.effective_for_incident`
## (staff may cover). Idempotent.
static func resolve_incident(state: Dictionary, day: int, choice: int) -> Dictionary:
	var inc: Dictionary = _day(state, day).get("incident", {})
	if inc.is_empty():
		return {}
	if int(inc.get("choice", -1)) >= 0:
		return inc.get("outcome", {})
	var r: Dictionary = MentalEvents.row(String(inc["event"]))
	var out: Dictionary = MentalEvents.apply_choice(state, r, choice, int(inc["pilot_id"]),
			StaffSystem.effective_for_incident(state), _seed(state, day, "incident_check", choice))
	inc["choice"] = choice
	inc["outcome"] = out
	return out


# ── Press conference (once per week, before training) ────────────────────────
## This week's press session — drawn once and kept in `mental.press`.
## Rows with `mention=mvp|worst` target that pilot (and are skipped when there is
## no last match / no such pilot).
static func press_session(state: Dictionary) -> Dictionary:
	var m: Dictionary = _mental(state)
	var key: String = week_key(state)
	var p: Dictionary = m.get("press", {})
	if String(p.get("week", "")) == key and String(p.get("event", "")) != "":
		return {"kind": MentalEvents.KIND_PRESS, "event": String(p["event"]),
				"pilot_id": int(p.get("pilot_id", -1))}
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(state, -1, "press", 0)
	var cands: Array = []
	var targets: Dictionary = {}
	for r_raw in MentalEvents.rows_of(MentalEvents.KIND_PRESS):
		var r: Dictionary = r_raw
		if not MentalEvents.type_ok(state, r):
			continue
		var target: int = -1
		var mention: String = MentalEvents.mention_of(r)
		if mention != "":
			target = MentalEvents.mention_target(state, mention)
			if target < 0:
				continue
		if not MentalEvents.cond_ok(state, r, target):
			continue
		cands.append(r)
		targets[String(r["id"])] = target
	var pick: Dictionary = MentalEvents.weighted_pick(state, cands, rng)
	if pick.is_empty():
		return {}
	var pid: int = int(targets[String(pick["id"])])
	m["press"] = {"week": key, "event": String(pick["id"]), "pilot_id": pid, "choice": -1, "outcome": {}}
	return {"kind": MentalEvents.KIND_PRESS, "event": String(pick["id"]), "pilot_id": pid}


## Answer this week's press question. Idempotent per week. Checks (if the entry
## has gated clauses) use the manager's own mental.
static func resolve_press(state: Dictionary, choice: int) -> Dictionary:
	var p: Dictionary = _mental(state).get("press", {})
	if String(p.get("week", "")) != week_key(state) or String(p.get("event", "")) == "":
		return {}
	if int(p.get("choice", -1)) >= 0:
		return p.get("outcome", {})
	var r: Dictionary = MentalEvents.row(String(p["event"]))
	var out: Dictionary = MentalEvents.apply_choice(state, r, choice, int(p.get("pilot_id", -1)),
			StaffSystem.manager_value(state, "mental"), _seed(state, -1, "press_check", choice))
	p["choice"] = choice
	p["outcome"] = out
	return out


# ── Sessions → what a messenger screen draws ─────────────────────────────────
## `{kind, event, pilot_id, tag, lines[], choices[]}` — translated, `{name}` filled.
## The `@text` line (press outlet / incident name) becomes `tag`, not a line.
static func session_view(state: Dictionary, session: Dictionary) -> Dictionary:
	var r: Dictionary = MentalEvents.row(String(session.get("event", "")))
	if r.is_empty():
		return {}
	var pid: int = int(session.get("pilot_id", -1))
	var tag: String = ""
	var lines: Array = []
	for k in (r["lines"] as Array):
		var t: String = MentalEvents.text(state, String(k), pid).strip_edges()
		if t.begins_with("@"):
			tag = t.substr(1).strip_edges()
		elif t != "":
			lines.append(t)
	var choices: Array = []
	for k in (r["choices"] as Array):
		choices.append(MentalEvents.text(state, String(k), pid))
	return {"kind": String(r["kind"]), "event": String(r["id"]), "pilot_id": pid,
			"tag": tag, "lines": lines, "choices": choices}


# ── Internals ────────────────────────────────────────────────────────────────
## Week identity — per-week fields are reset when it changes (defensive; the
## normal reset is `end_week`).
static func week_key(state: Dictionary) -> String:
	return "%d-%d" % [int(state.get("current_phase", 0)), int(state.get("phase_week", 1))]


static func _fresh_mental() -> Dictionary:
	return {"week": "", "interviews_used": 0, "outings_used": 0, "days": {},
			"fatigue": {}, "press": {}}


static func _mental(state: Dictionary) -> Dictionary:
	var m: Variant = state.get("mental", null)
	if not (m is Dictionary):
		m = _fresh_mental()
		state["mental"] = m
	return m


## `mental` with per-week fields belonging to the current week.
static func _week(state: Dictionary) -> Dictionary:
	var m: Dictionary = _mental(state)
	var key: String = week_key(state)
	if String(m.get("week", "")) != key:
		m["week"] = key
		m["interviews_used"] = 0
		m["outings_used"] = 0
		m["days"] = {}
	if not (m.get("days", null) is Dictionary):
		m["days"] = {}
	return m


## That weekday's record dictionary `mental.days["<day>"]` (created empty when missing,
## reset with the week). Other mental helpers keep their own sub-records in it
## (`AfternoonAway` → `afternoon`).
static func day_record(state: Dictionary, day: int) -> Dictionary:
	return _day(state, day)


static func _day(state: Dictionary, day: int) -> Dictionary:
	var days: Dictionary = _week(state)["days"]
	var k: String = str(day)
	if not (days.get(k, null) is Dictionary):
		days[k] = {}
	return days[k]


static func _session_of(e: Dictionary) -> Dictionary:
	var kind: String = MentalEvents.KIND_INTERVIEW if String(e["action"]) == ACTION_INTERVIEW \
			else MentalEvents.KIND_OUTING
	return {"kind": kind, "event": String(e["event"]), "pilot_id": int(e["pilot_id"])}


## Weighted draw of a `kind` row whose cond holds for `pilot_id`.
static func _draw(state: Dictionary, kind: String, pilot_id: int, seed_v: int) -> Dictionary:
	var cands: Array = []
	for r_raw in MentalEvents.rows_of(kind):
		var r: Dictionary = r_raw
		if MentalEvents.type_ok(state, r) and MentalEvents.cond_ok(state, r, pilot_id):
			cands.append(r)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	return MentalEvents.weighted_pick(state, cands, rng)


## Deterministic seed per run · week · day · purpose.
static func _seed(state: Dictionary, day: int, purpose: String, extra: int) -> int:
	return hash([int(state.get("run_seed", 0)), week_key(state), day, purpose, extra])
