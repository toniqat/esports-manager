class_name TrainingLevel
extends RefCounted

# ── Run-only 깨달음 레벨 (awakening level, §15 B + C merged 2026-10-09) ────────
# Each of my pilots has one level 1..TLEVEL_MAX and a training EXP bar (`docs/outgame_dev_plan.md`
# §15.0 "2026-10-09 decision"). EXP sources: the training board (sum of that day's stat EXP),
# focus training / story `tlexp` clauses, and the former awakening-gauge sources converted at
# LEVEL_EXP_PER_AWAKEN EXP per old gauge point (matches, story / incident `awaken` clauses,
# focus training). When the bar fills the level goes up by one at once (excess EXP carries
# into the next bar) and **one awakening is queued** (`Awakening.queue`, the 1-of-3 screen).
# Reaching an even level below the cap (2, 4, 6, 8) **locks the bar**: no EXP until the limit
# break (`LimitBreak.complete`: stats up, bar unlocked, level unchanged). Lv TLEVEL_MAX = no EXP.
# State: season_state.training_level = {"<pid>": entry}, entry =
#   {"v": 2, "level": int 1..MAX, "exp": int (inside the level), "broken": bool (limit break of
#    this even level done), "goal": {} | LimitBreak goal, "offer": [goal ids], "event": "",
#    "event_week": week key, "event_day": int (-1 = none), "note": {} | LimitBreak result note}
# An entry without "v" is a pre-merge save — `ensure` migrates it once (`_migrate`).
# Rules · numbers: `features/season/training/README.md` "깨달음 레벨"; keys `TLEVEL_*`.
#
# Every function is static and only edits the dictionary it is handed. Values read back
# from the run save may be floats — every read goes through `int()`.

const STATE_KEY: String = "training_level"
## Entry format version (2 = merged level, even-level lock).
const VERSION: int = 2

## Level cap — no EXP and no awakening / limit break at this level.
static var MAX_LEVEL: int = ConstTable.int_of("TLEVEL_MAX")


## `GameManager.start_run` hook — every one of my pilots starts at Lv1 with an empty bar.
static func init_run(state: Dictionary) -> void:
	var d: Dictionary = {}
	for raw in MentalSystem.my_pilot_ids(state):
		d[str(int(raw))] = fresh_entry()
	state[STATE_KEY] = d


## A level-1 entry with an empty bar.
static func fresh_entry() -> Dictionary:
	return {"v": VERSION, "level": 1, "exp": 0, "broken": false, "goal": {}, "offer": [], "event": "",
			"event_week": "", "event_day": -1, "note": {}}


## The pilot's entry, or {} when `pid` is not one of my run pilots (AI pilots have none).
## A run saved before §15 gets entries on first read (`ensure`).
static func entry(state: Dictionary, pid: int) -> Dictionary:
	var d: Dictionary = ensure(state)
	var e: Variant = d.get(str(pid), null)
	return e if e is Dictionary else {}


## `state.training_level`, created for my pilots when missing (older saves); pre-merge entries
## are migrated (`_migrate`).
static func ensure(state: Dictionary) -> Dictionary:
	var d: Variant = state.get(STATE_KEY, null)
	if not (d is Dictionary):
		d = {}
		state[STATE_KEY] = d
	var dd := d as Dictionary
	for raw in MentalSystem.my_pilot_ids(state):
		var k: String = str(int(raw))
		var e: Variant = dd.get(k, null)
		if not (e is Dictionary):
			dd[k] = fresh_entry()
		elif int((e as Dictionary).get("v", 0)) < VERSION:
			_migrate(state, int(raw), e as Dictionary)
	return dd


## Level of my pilot `pid` (1 outside a run / unknown pilot).
static func level(state: Dictionary, pid: int) -> int:
	var e: Dictionary = entry(state, pid)
	return clampi(int(e.get("level", 1)), 1, MAX_LEVEL) if not e.is_empty() else 1


## Whether `pid` has a level at all (my run pilots only).
static func has_level(state: Dictionary, pid: int) -> bool:
	return not entry(state, pid).is_empty()


## Training EXP inside the current level (0 while locked / at the cap).
static func exp_of(state: Dictionary, pid: int) -> int:
	return int(entry(state, pid).get("exp", 0))


## EXP that fills the current level's bar (0 at the cap). While locked it is the bar that opens
## after the limit break.
static func exp_need(state: Dictionary, pid: int) -> int:
	return need_for_level(level(state, pid))


## EXP that fills the bar of `lv` (`TLEVEL_EXP_<lv>`), 0 at the cap.
static func need_for_level(lv: int) -> int:
	if lv >= MAX_LEVEL or lv < 1:
		return 0
	return maxi(1, ConstTable.int_of("TLEVEL_EXP_%d" % lv))


## Bar fill 0..1 (1 while locked or at the cap).
static func progress(state: Dictionary, pid: int) -> float:
	if is_capped(state, pid):
		return 1.0
	var need: int = exp_need(state, pid)
	if need <= 0:
		return 1.0
	return clampf(float(exp_of(state, pid)) / float(need), 0.0, 1.0)


## The level is the cap.
static func is_max(state: Dictionary, pid: int) -> bool:
	return level(state, pid) >= MAX_LEVEL


## Whether reaching `lv` locks the bar until a limit break (even levels below the cap).
static func is_lock_level(lv: int) -> bool:
	return lv % 2 == 0 and lv < MAX_LEVEL


## The bar takes no EXP: locked (limit break due) or the level is the cap.
static func is_capped(state: Dictionary, pid: int) -> bool:
	if not has_level(state, pid):
		return false
	return is_max(state, pid) or awaiting_break(state, pid)


## Locked at an even level below the cap — a limit break is due (event / goal / focus training).
static func awaiting_break(state: Dictionary, pid: int) -> bool:
	var e: Dictionary = entry(state, pid)
	if e.is_empty():
		return false
	return is_lock_level(level(state, pid)) and not bool(e.get("broken", false))


## Add training EXP; returns the applied amount (0 when capped). Every filled bar = level + 1
## and one queued awakening; the rest carries into the next bar, unless the new level locks
## (even) or is the cap — then the rest is dropped and, on a lock, the limit-break event is
## stamped for the evening of the current week day (`season_state.week_day`;
## `LimitBreak.pending_event` opens it that evening or the next evening the week screen reaches).
## `source` = short id for the debug log.
static func add_exp(state: Dictionary, pid: int, amount: int, source: String = "") -> int:
	if amount <= 0 or is_capped(state, pid):
		return 0
	var e: Dictionary = entry(state, pid)
	var left: int = amount
	var applied: int = 0
	var ups: int = 0
	while left > 0 and not is_capped(state, pid):
		var need: int = exp_need(state, pid)
		var cur: int = int(e.get("exp", 0))
		var take: int = mini(left, need - cur)
		left -= take
		applied += take
		if cur + take < need:
			e["exp"] = cur + take
			break
		_level_up(state, pid, e)
		ups += 1
	if ups > 0 and OS.is_debug_build():
		print("TrainingLevel: pilot %d +%d level(s) → Lv%d (source %s)" % [pid, ups, level(state, pid), source])
	return applied


## `TrainingBoard.apply_day_training` hook — `rows` are that day's result rows
## (`exp` = `{stat: EXP earned}`); training EXP = the sum over the six stats. The applied EXP is
## written back on the row as `tlexp`, the levels gained as `level_up` (the week screen may show them).
static func on_training_day(state: Dictionary, rows: Array) -> void:
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var row := raw as Dictionary
		var pid: int = int(row.get("pilot_id", -1))
		var total: int = 0
		var ex: Variant = row.get("exp", {})
		if ex is Dictionary:
			for v in (ex as Dictionary).values():
				total += maxi(0, int(v))
		var lv0: int = level(state, pid)
		row["tlexp"] = add_exp(state, pid, total, "train") if total > 0 else 0
		row["level_up"] = level(state, pid) - lv0


## Former awakening-gauge points → training EXP (LEVEL_EXP_PER_AWAKEN per point).
static func exp_of_awaken(points: int) -> int:
	return maxi(0, points) * maxi(0, ConstTable.int_of("LEVEL_EXP_PER_AWAKEN"))


## The limit break of the current (even) level is done: the bar unlocks, the level stays
## (`LimitBreak.complete`). Returns false when no limit break was due.
static func break_done(state: Dictionary, pid: int) -> bool:
	if not awaiting_break(state, pid):
		return false
	var e: Dictionary = entry(state, pid)
	e["broken"] = true
	e["exp"] = 0
	e["event_week"] = ""
	e["event_day"] = -1
	return true


## "Lv2" — the compact chip text (hub card, training-screen portraits).
static func chip_text(state: Dictionary, pid: int) -> String:
	return Loc.t(L.TRAINING_LEVEL_CHIP, {"n": level(state, pid)})


# ── Internals ────────────────────────────────────────────────────────────────
## Level + 1 with an empty bar, one awakening queued; a lock level stamps the limit-break event.
static func _level_up(state: Dictionary, pid: int, e: Dictionary) -> void:
	var lv: int = mini(level(state, pid) + 1, MAX_LEVEL)
	e["level"] = lv
	e["exp"] = 0
	e["broken"] = false
	Awakening.queue(state, pid)
	if is_lock_level(lv):
		e["event_week"] = MentalSystem.week_key(state)
		e["event_day"] = maxi(0, int(state.get("week_day", 0)))
		e["offer"] = []
	else:
		e["event_week"] = ""
		e["event_day"] = -1


## Pre-merge entry (no "v": a level rose only by a limit break, a full bar waited for one) →
## the merged rules, keeping the level number:
## - an even level was reached by a limit break → `broken` (not locked again);
## - a full bar (the old "limit break due") is a level-up now: level + 1, one awakening queued,
##   empty bar. Landing on an even level locks it and **keeps** an offered / chosen goal (it is
##   that level's limit break now, the event stamp stays); landing on an odd level drops the goal.
## Also drops the old awakening gauge (`season_state.awakening`, a pid → int dict): its points
## are not converted (pending awakenings in the queue stay).
static func _migrate(state: Dictionary, pid: int, e: Dictionary) -> void:
	var lv: int = clampi(int(e.get("level", 1)), 1, MAX_LEVEL)
	var cur: int = maxi(0, int(e.get("exp", 0)))
	var need: int = need_for_level(lv)
	e["v"] = VERSION
	e["level"] = lv
	e["broken"] = lv % 2 == 0
	if not e.has("event"):
		e["event"] = ""
	if not (e.get("note", null) is Dictionary):
		e["note"] = {}
	if need > 0 and cur >= need:
		var nlv: int = mini(lv + 1, MAX_LEVEL)
		e["level"] = nlv
		e["exp"] = 0
		e["broken"] = false
		Awakening.queue(state, pid)
		if not is_lock_level(nlv):
			e["goal"] = {}
			e["offer"] = []
			e["event"] = ""
			e["event_week"] = ""
			e["event_day"] = -1
	elif need <= 0:
		e["exp"] = 0
	if state.get(Awakening.KEY_LEGACY_GAUGE, null) is Dictionary:
		state.erase(Awakening.KEY_LEGACY_GAUGE)
