class_name TrainingLevel
extends RefCounted

# ── Run-only training level (§15 B, `docs/outgame_dev_plan.md` §15) ─────────
# Each of my pilots has a training level 1..TLEVEL_MAX and training EXP. The EXP is
# the sum of stat EXP the pilot earned on the training board that day; when the bar
# is full the EXP stops and a limit break (`LimitBreak`) is needed for the next level.
# State: season_state.training_level = {"<pid>": entry}, entry =
#   {"level": int 1..MAX, "exp": int (inside the level), "goal": {} | LimitBreak goal,
#    "offer": [goal ids], "event_week": week key, "event_day": int (-1 = none),
#    "note": {} | LimitBreak result note}
# Rules · numbers: `features/season/training/README.md` "Training level"; keys `TLEVEL_*`.
#
# Every function is static and only edits the dictionary it is handed. Values read back
# from the run save may be floats — every read goes through `int()`.

const STATE_KEY: String = "training_level"

## Level cap — no EXP and no limit-break event at this level.
static var MAX_LEVEL: int = ConstTable.int_of("TLEVEL_MAX")


## `GameManager.start_run` hook — every one of my pilots starts at Lv1 with an empty bar.
static func init_run(state: Dictionary) -> void:
	var d: Dictionary = {}
	for raw in MentalSystem.my_pilot_ids(state):
		d[str(int(raw))] = fresh_entry()
	state[STATE_KEY] = d


## A level-1 entry with an empty bar.
static func fresh_entry() -> Dictionary:
	return {"level": 1, "exp": 0, "goal": {}, "offer": [], "event": "", "event_week": "", "event_day": -1,
			"note": {}}


## The pilot's entry, or {} when `pid` is not one of my run pilots (AI pilots have none).
## A run saved before §15 gets entries on first read (`ensure`).
static func entry(state: Dictionary, pid: int) -> Dictionary:
	var d: Dictionary = ensure(state)
	var e: Variant = d.get(str(pid), null)
	return e if e is Dictionary else {}


## `state.training_level`, created for my pilots when missing (older saves).
static func ensure(state: Dictionary) -> Dictionary:
	var d: Variant = state.get(STATE_KEY, null)
	if not (d is Dictionary):
		d = {}
		state[STATE_KEY] = d
	var dd := d as Dictionary
	for raw in MentalSystem.my_pilot_ids(state):
		var k: String = str(int(raw))
		if not (dd.get(k, null) is Dictionary):
			dd[k] = fresh_entry()
	return dd


## Training level of my pilot `pid` (1 outside a run / unknown pilot).
static func level(state: Dictionary, pid: int) -> int:
	var e: Dictionary = entry(state, pid)
	return clampi(int(e.get("level", 1)), 1, MAX_LEVEL) if not e.is_empty() else 1


## Whether `pid` has a training level at all (my run pilots only).
static func has_level(state: Dictionary, pid: int) -> bool:
	return not entry(state, pid).is_empty()


## Training EXP inside the current level.
static func exp_of(state: Dictionary, pid: int) -> int:
	return int(entry(state, pid).get("exp", 0))


## EXP that fills the current level's bar (0 at the cap).
static func exp_need(state: Dictionary, pid: int) -> int:
	return need_for_level(level(state, pid))


## EXP that fills the bar of `lv` (`TLEVEL_EXP_<lv>`), 0 at the cap.
static func need_for_level(lv: int) -> int:
	if lv >= MAX_LEVEL or lv < 1:
		return 0
	return maxi(1, ConstTable.int_of("TLEVEL_EXP_%d" % lv))


## Bar fill 0..1 (1 when full or at the cap).
static func progress(state: Dictionary, pid: int) -> float:
	var need: int = exp_need(state, pid)
	if need <= 0:
		return 1.0
	return clampf(float(exp_of(state, pid)) / float(need), 0.0, 1.0)


## The level is the cap.
static func is_max(state: Dictionary, pid: int) -> bool:
	return level(state, pid) >= MAX_LEVEL


## The bar is full (waiting for a limit break) or the level is the cap.
static func is_capped(state: Dictionary, pid: int) -> bool:
	if not has_level(state, pid):
		return false
	if is_max(state, pid):
		return true
	return exp_of(state, pid) >= exp_need(state, pid)


## Bar full below the cap — a limit break is due (event / goal / focus training).
static func awaiting_break(state: Dictionary, pid: int) -> bool:
	return has_level(state, pid) and not is_max(state, pid) and is_capped(state, pid)


## Add training EXP; returns the applied amount (0 when capped). The moment the bar fills,
## the limit-break event is stamped for the evening of the current week day
## (`season_state.week_day`) — `LimitBreak.pending_event` opens it that evening or the next
## evening the week screen reaches.
static func add_exp(state: Dictionary, pid: int, amount: int) -> int:
	if amount <= 0 or is_capped(state, pid):
		return 0
	var e: Dictionary = entry(state, pid)
	var need: int = exp_need(state, pid)
	var cur: int = int(e.get("exp", 0))
	var applied: int = mini(amount, need - cur)
	e["exp"] = cur + applied
	if cur + applied >= need:
		e["event_week"] = MentalSystem.week_key(state)
		e["event_day"] = maxi(0, int(state.get("week_day", 0)))
		e["offer"] = []
	return applied


## `TrainingBoard.apply_day_training` hook — `rows` are that day's result rows
## (`exp` = `{stat: EXP earned}`); training EXP = the sum over the six stats.
static func on_training_day(state: Dictionary, rows: Array) -> void:
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var row := raw as Dictionary
		var total: int = 0
		var ex: Variant = row.get("exp", {})
		if ex is Dictionary:
			for v in (ex as Dictionary).values():
				total += maxi(0, int(v))
		if total > 0:
			add_exp(state, int(row.get("pilot_id", -1)), total)


## Level +1 with an empty bar (`LimitBreak.complete`). Returns the new level (unchanged at the cap).
static func level_up(state: Dictionary, pid: int) -> int:
	var e: Dictionary = entry(state, pid)
	if e.is_empty():
		return 1
	var lv: int = mini(level(state, pid) + 1, MAX_LEVEL)
	e["level"] = lv
	e["exp"] = 0
	e["event_week"] = ""
	e["event_day"] = -1
	return lv


## "Lv2" — the compact chip text (hub card, training-screen portraits).
static func chip_text(state: Dictionary, pid: int) -> String:
	return Loc.t(L.TRAINING_LEVEL_CHIP, {"n": level(state, pid)})
