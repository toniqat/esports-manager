class_name AfternoonAway
extends RefCounted

# ── Afternoon away states (Mon–Fri) ──────────────────────────────────────────
# When a training day turns to the afternoon (week screen, after the morning
# settlement), some of my pilots are not around for an interview / outing:
#
#   • dorm (숙소 휴식): the pilot had no tile on that day's row of the training
#     board (the caller passes them in `resting`).
#   • self outing (혼자 외출): a pilot with stress ≥ STRESS_SELF_OUTING_MIN rolls
#     STRESS_SELF_OUTING_CHANCE to go out alone; stress drops by STRESS_SELF_OUTING_RELIEF.
#
# Rolled **once** per weekday and recorded before it is shown, seeded from
# run seed + week + day + pilot (like `MentalSystem`), so re-entering the day or
# reloading never rerolls or relieves twice. Record:
#   mental.days["<day>"].afternoon = {"away": {"<pid>": "dorm"|"self_outing"},
#                                     "relief": {"<pid>": int}}
# It lives in the weekday record, so `MentalSystem.end_week` clears it.
# Rules in `features/season/mental/README.md` "Afternoon away states".

const AWAY_DORM: String = "dorm"
const AWAY_SELF_OUTING: String = "self_outing"
const _KEY: String = "afternoon"


## The afternoon of `day` has started (its away states are rolled and recorded).
static func started(state: Dictionary, day: int) -> bool:
	return MentalSystem.day_record(state, day).get(_KEY, null) is Dictionary


## Start the afternoon of `day`: roll once and record. `resting` = my pilots with no
## tile on that day's row (they rest in the dorm, no roll). A second call returns the
## stored record untouched. Not a training day → {}.
static func begin(state: Dictionary, day: int, resting: Array) -> Dictionary:
	if not CalendarSystem.is_training_day(day):
		return {}
	var rec: Dictionary = MentalSystem.day_record(state, day)
	if rec.get(_KEY, null) is Dictionary:
		return rec[_KEY]
	var away: Dictionary = {}
	var relief: Dictionary = {}
	var min_stress: int = ConstTable.int_of("STRESS_SELF_OUTING_MIN")
	var chance: float = ConstTable.num("STRESS_SELF_OUTING_CHANCE")
	for raw in MentalSystem.my_pilot_ids(state):
		var pid: int = int(raw)
		if resting.has(pid):
			away[str(pid)] = AWAY_DORM
			continue
		if StressSystem.value(state, pid) < min_stress:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([int(state.get("run_seed", 0)), MentalSystem.week_key(state), day,
				"self_outing", pid])
		if rng.randf() < chance:
			away[str(pid)] = AWAY_SELF_OUTING
			relief[str(pid)] = StressSystem.add(state, pid, -ConstTable.int_of("STRESS_SELF_OUTING_RELIEF"))
	var out: Dictionary = {"away": away, "relief": relief}
	rec[_KEY] = out
	return out


## Where that pilot is this afternoon: "" (around), `AWAY_DORM` or `AWAY_SELF_OUTING`.
static func away_of(state: Dictionary, day: int, pilot_id: int) -> String:
	var r: Variant = MentalSystem.day_record(state, day).get(_KEY, null)
	if not (r is Dictionary):
		return ""
	return String(((r as Dictionary).get("away", {}) as Dictionary).get(str(pilot_id), ""))


## Stress change recorded for a self outing (≤ 0), 0 when none.
static func relief_of(state: Dictionary, day: int, pilot_id: int) -> int:
	var r: Variant = MentalSystem.day_record(state, day).get(_KEY, null)
	if not (r is Dictionary):
		return 0
	return int(((r as Dictionary).get("relief", {}) as Dictionary).get(str(pilot_id), 0))


## The pilot is around this afternoon and an interview or an outing with them is
## still allowed (weekly limits, trust unlock, the day's action not used yet).
static func can_request(state: Dictionary, day: int, pilot_id: int) -> bool:
	if not started(state, day) or MentalSystem.evening_done(state, day):
		return false
	if away_of(state, day, pilot_id) != "":
		return false
	return MentalSystem.can_interview(state) or MentalSystem.can_outing(state, pilot_id)


## Some pilot can still be asked this afternoon (the week screen's skip warning).
static func any_request(state: Dictionary, day: int) -> bool:
	for raw in MentalSystem.my_pilot_ids(state):
		if can_request(state, day, int(raw)):
			return true
	return false
