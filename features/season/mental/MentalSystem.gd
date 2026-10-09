class_name MentalSystem
extends RefCounted

# ── Mental — trust · interviews · outings · incidents · press (M7) ────────────
# Contract: `docs/outgame_dev_plan.md` §11. State lives in `season_state`:
#   trust   {"<pid>": int}   my 5 pilots, [TRUST_MIN, TRUST_MAX]
#   outings {"<pid>": int}   outings taken this run (true ending counter)
#   mental  {week, days{"<day>": {...}}, fatigue{}, press{}}
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
const ACTION_TALK: String = "talk"


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


## Week end (`SeasonHub._end_week`, before the calendar moves) — the weekday
## records reset; a Friday outing's fatigue moves on to next Monday.
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


# ── Action gates ─────────────────────────────────────────────────────────────
# No weekly count limits: an interview is always possible, an outing once the
# pilot's trust reaches `TRUST_OUTING_MIN`. The only cap is one action per afternoon.
static func outing_unlocked(state: Dictionary, pilot_id: int) -> bool:
	return trust(state, pilot_id) >= ConstTable.int_of("TRUST_OUTING_MIN")


static func can_outing(state: Dictionary, pilot_id: int) -> bool:
	return outing_unlocked(state, pilot_id)


# ── Evening (one action per Mon–Fri) ─────────────────────────────────────────
## That weekday's evening record, or {} when nothing was chosen yet.
## `{action, pilot_id, event, choice(-1 = dialog open), outcome{}}`.
static func evening(state: Dictionary, day: int) -> Dictionary:
	return (_day(state, day).get("evening", {}) as Dictionary)


static func evening_done(state: Dictionary, day: int) -> bool:
	var e: Dictionary = evening(state, day)
	return not e.is_empty() and (String(e.get("action", "")) == ACTION_PASS or int(e.get("choice", -1)) >= 0)


## Start the evening action. Returns a session (`session_view` draws it) or {}
## when refused (trust gate, already used, pass). Re-calling on a day whose dialog
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
	if String(e["action"]) == ACTION_OUTING:
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


# ── Morning talk (훈련 소감, one per Mon–Fri morning) ─────────────────────────
# Right after the morning training is settled the manager may meet one pilot (no
# outing). A pilot who trained in the same placed tile as others (joint training,
# `week_day_log` row `group`) brings one of them along: a `talk_pair` row is drawn
# first, both appear and both receive the single-pilot clauses.
# Record `days["<day>"].talk`: `{}` = the morning is open (nothing chosen yet),
# `{action: talk|pass, pilot_id, partner_id, event, choice(-1 = open), outcome{}}`.

## Open the morning (the week screen calls it when the result FX ends). Idempotent.
static func begin_morning(state: Dictionary, day: int) -> void:
	if not CalendarSystem.is_training_day(day):
		return
	var rec: Dictionary = _day(state, day)
	if not (rec.get("talk", null) is Dictionary):
		rec["talk"] = {}


## The morning of `day` is open (its talk record exists).
static func morning_started(state: Dictionary, day: int) -> bool:
	return _day(state, day).get("talk", null) is Dictionary


static func talk(state: Dictionary, day: int) -> Dictionary:
	var t: Variant = _day(state, day).get("talk", null)
	return t if t is Dictionary else {}


## The morning's talk is settled (answered or passed).
static func talk_done(state: Dictionary, day: int) -> bool:
	var t: Dictionary = talk(state, day)
	return String(t.get("action", "")) == ACTION_PASS or int(t.get("choice", -1)) >= 0


## That pilot can be met this morning: the morning is open, the afternoon has not
## started and no talk was used yet.
static func can_talk(state: Dictionary, day: int, pilot_id: int) -> bool:
	return morning_started(state, day) and not AfternoonAway.started(state, day) \
			and talk(state, day).is_empty() and my_pilot_ids(state).has(pilot_id)


## Who trained in the same tile as `pilot_id` on `day` (joint training), or -1.
## With several mates one is drawn (seeded per pilot, so it never changes).
static func talk_partner(state: Dictionary, day: int, pilot_id: int) -> int:
	var log: Dictionary = state.get("week_day_log", {})
	var rows: Variant = log.get(day, log.get(str(day), []))
	if not (rows is Array):
		return -1
	var group: int = -1
	for raw in (rows as Array):
		if raw is Dictionary and int((raw as Dictionary).get("pilot_id", -1)) == pilot_id:
			group = int((raw as Dictionary).get("group", -1))
	if group < 0:
		return -1
	var mates: Array = []
	for raw in (rows as Array):
		var r: Dictionary = raw
		var pid: int = int(r.get("pilot_id", -1))
		if pid != pilot_id and int(r.get("group", -1)) == group:
			mates.append(pid)
	if mates.is_empty():
		return -1
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(state, day, "talk_partner", pilot_id)
	return int(mates[rng.randi_range(0, mates.size() - 1)])


## Meet `pilot_id` this morning. Returns a session (`session_view` draws it) or {}.
## Re-calling while the dialog is open returns the same session.
static func begin_talk(state: Dictionary, day: int, pilot_id: int) -> Dictionary:
	var t: Dictionary = talk(state, day)
	if String(t.get("action", "")) == ACTION_TALK and int(t.get("choice", -1)) < 0:
		return _talk_session(t)
	if not can_talk(state, day, pilot_id):
		return {}
	var partner: int = talk_partner(state, day, pilot_id)
	var r: Dictionary = {}
	if partner >= 0:
		r = _draw(state, MentalEvents.KIND_TALK_PAIR, pilot_id, _seed(state, day, "talk_pair", pilot_id))
	if r.is_empty():
		partner = -1
		r = _draw(state, MentalEvents.KIND_TALK, pilot_id, _seed(state, day, "talk", pilot_id))
	if r.is_empty():
		return {}
	t = {"action": ACTION_TALK, "pilot_id": pilot_id, "partner_id": partner,
			"event": String(r["id"]), "choice": -1, "outcome": {}}
	_day(state, day)["talk"] = t
	return _talk_session(t)


## Settle the morning talk with answer `choice` (manager's own mental). Idempotent.
static func finish_talk(state: Dictionary, day: int, choice: int) -> Dictionary:
	var t: Dictionary = talk(state, day)
	if String(t.get("action", "")) != ACTION_TALK:
		return {}
	if int(t.get("choice", -1)) >= 0:
		return t.get("outcome", {})
	var r: Dictionary = MentalEvents.row(String(t["event"]))
	var pid: int = int(t["pilot_id"])
	var partner: int = int(t.get("partner_id", -1))
	var out: Dictionary = MentalEvents.apply_choice(state, r, choice, pid,
			StaffSystem.manager_value(state, "mental"), _seed(state, day, "talk_check", choice), partner)
	for who in [pid, partner]:
		if int(who) < 0:
			continue
		var relief: int = StressSystem.relieve(state, int(who), ACTION_TALK)
		if relief != 0:
			(out["notes"] as Array).append({"type": "stress", "pid": int(who), "delta": relief})
	t["choice"] = choice
	t["outcome"] = out
	return out


## Leave the morning without a talk (records a pass; a used talk stays).
static func pass_talk(state: Dictionary, day: int) -> void:
	if morning_started(state, day) and talk(state, day).is_empty():
		_day(state, day)["talk"] = {"action": ACTION_PASS, "pilot_id": -1, "partner_id": -1,
				"event": "", "choice": -1, "outcome": {}}


static func _talk_session(t: Dictionary) -> Dictionary:
	var r: Dictionary = MentalEvents.row(String(t.get("event", "")))
	return {"kind": String(r.get("kind", MentalEvents.KIND_TALK)), "event": String(t["event"]),
			"pilot_id": int(t["pilot_id"]), "partner_id": int(t.get("partner_id", -1))}


# ── Evening (저녁) — the incident phase ───────────────────────────────────────
# After the afternoon the day turns to the evening: the incident is rolled there (it
# happens to the team — the player answers it but does not start it). Record marker
# `days["<day>"].dusk = true` (the afternoon action keeps its old record name `evening`).

## Start the evening of `day`: mark it and roll the incident once. Returns the incident
## record ({} = a quiet evening).
static func begin_dusk(state: Dictionary, day: int) -> Dictionary:
	if not CalendarSystem.is_training_day(day):
		return {}
	_day(state, day)["dusk"] = true
	return ensure_incident(state, day)


static func dusk_started(state: Dictionary, day: int) -> bool:
	return bool(_day(state, day).get("dusk", false))


# ── Incidents (rolled when a weekday's evening starts) ───────────────────────
## Roll that weekday's incident once (`begin_dusk`) (chance `MENTAL_INCIDENT_CHANCE` ×
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


## This week's press question has been answered (the week's training plan is next).
static func press_answered(state: Dictionary) -> bool:
	var p: Dictionary = _mental(state).get("press", {})
	return String(p.get("week", "")) == week_key(state) and int(p.get("choice", -1)) >= 0


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
## `{kind, event, pilot_id, partner_id, tag, lines[], choices[], previews[]}` — translated,
## `{name}` / `{name2}` filled; `previews[i]` = answer i's chance + direction line (may be "").
## The `@text` line (press outlet / incident name) becomes `tag`, not a line.
static func session_view(state: Dictionary, session: Dictionary) -> Dictionary:
	var r: Dictionary = MentalEvents.row(String(session.get("event", "")))
	if r.is_empty():
		return {}
	var pid: int = int(session.get("pilot_id", -1))
	var partner: int = int(session.get("partner_id", -1))
	var tag: String = ""
	var lines: Array = []
	for k in (r["lines"] as Array):
		var t: String = MentalEvents.text(state, String(k), pid, partner).strip_edges()
		if t.begins_with("@"):
			tag = t.substr(1).strip_edges()
		elif t != "":
			lines.append(t)
	var choices: Array = []
	var previews: Array = []
	# The activity's own stress relief (talk / interview / outing) is the same for every
	# answer, so the preview shows only what the answer itself changes.
	var judge: int = judge_for(state, String(r["kind"]))
	for i in (r["choices"] as Array).size():
		choices.append(MentalEvents.text(state, String((r["choices"] as Array)[i]), pid, partner))
		previews.append(MentalEvents.preview_text(MentalEvents.choice_preview(state, r, i, judge)))
	return {"kind": String(r["kind"]), "event": String(r["id"]), "pilot_id": pid,
			"partner_id": partner, "tag": tag, "lines": lines, "choices": choices, "previews": previews}


## The mental value a `kind`'s check is judged with: incidents may be covered by staff
## (`StaffSystem.effective_for_incident`), everything else uses the manager's own mental.
static func judge_for(state: Dictionary, kind: String) -> int:
	if kind == MentalEvents.KIND_INCIDENT:
		return StaffSystem.effective_for_incident(state)
	return StaffSystem.manager_value(state, "mental")


# ── Internals ────────────────────────────────────────────────────────────────
## Week identity — per-week fields are reset when it changes (defensive; the
## normal reset is `end_week`).
static func week_key(state: Dictionary) -> String:
	return "%d-%d" % [int(state.get("current_phase", 0)), int(state.get("phase_week", 1))]


static func _fresh_mental() -> Dictionary:
	return {"week": "", "days": {}, "fatigue": {}, "press": {}}


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
