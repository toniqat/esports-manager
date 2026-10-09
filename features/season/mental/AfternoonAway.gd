class_name AfternoonAway
extends RefCounted

# ── Afternoon away states (Mon–Fri) ──────────────────────────────────────────
# When a training day turns to the afternoon (week screen, after the morning
# settlement), some of my pilots are not around for an interview / outing:
#
#   1. self outing (혼자 외출): a pilot with stress ≥ STRESS_SELF_OUTING_MIN rolls
#      STRESS_SELF_OUTING_CHANCE to go out alone; stress drops by STRESS_SELF_OUTING_RELIEF.
#   2. otherwise dorm (숙소 휴식): every pilot rolls AFTERNOON_DORM_CHANCE to stay in the
#      dorm (no stress change). An empty training cell does not matter (it is the basic course).
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


## Start the afternoon of `day`: roll once and record. A second call returns the
## stored record untouched. Outside the week (0..6) → {}. Saturday / a plain Sunday
## have an afternoon too (no training that day).
static func begin(state: Dictionary, day: int) -> Dictionary:
	if not CalendarSystem.is_week_day(day):
		return {}
	var rec: Dictionary = MentalSystem.day_record(state, day)
	if rec.get(_KEY, null) is Dictionary:
		return rec[_KEY]
	var away: Dictionary = {}
	var relief: Dictionary = {}
	var min_stress: int = ConstTable.int_of("STRESS_SELF_OUTING_MIN")
	var chance: float = ConstTable.num("STRESS_SELF_OUTING_CHANCE")
	var dorm_chance: float = ConstTable.num("AFTERNOON_DORM_CHANCE")
	for raw in MentalSystem.my_pilot_ids(state):
		var pid: int = int(raw)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([int(state.get("run_seed", 0)), MentalSystem.week_key(state), day,
				"afternoon_away", pid])
		# Two draws in a fixed order, whatever the stress, so one result never shifts the other.
		var out_roll: float = rng.randf()
		var dorm_roll: float = rng.randf()
		if StressSystem.value(state, pid) >= min_stress and out_roll < chance:
			away[str(pid)] = AWAY_SELF_OUTING
			relief[str(pid)] = StressSystem.add(state, pid, -ConstTable.int_of("STRESS_SELF_OUTING_RELIEF"))
		elif dorm_roll < dorm_chance:
			away[str(pid)] = AWAY_DORM
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


## The pilot is around this afternoon and the day's action is not used yet (a visit
## is always possible; there are no weekly count limits). A visit already started
## (menu or dialog open) uses the day's action too.
static func can_request(state: Dictionary, day: int, pilot_id: int) -> bool:
	if not started(state, day) or not MentalSystem.evening(state, day).is_empty() \
			or MentalSystem.dusk_started(state, day):
		return false
	return away_of(state, day, pilot_id) == ""


## Some pilot can still be asked this afternoon (the week screen's skip warning).
static func any_request(state: Dictionary, day: int) -> bool:
	for raw in MentalSystem.my_pilot_ids(state):
		if can_request(state, day, int(raw)):
			return true
	return false
