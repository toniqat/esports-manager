class_name LimitBreak
extends RefCounted

# ── Limit break (한계돌파, §15 B) ─────────────────────────────────────────────
# A pilot who reaches an even 깨달음 레벨 (2, 4, 6, 8 — `TrainingLevel.awaiting_break`, the
# EXP bar locks) gets a forced visual-novel event at that day's evening: the manager offers
# 1 of 3 short-term goals; the goal stays until it is met on my matches (or focus training
# completes it). Met → all six stats + LIMIT_BREAK_STAT_GAIN and the bar unlocks; the level
# stays (`TrainingLevel.break_done`). Goal pool and rules: `docs/outgame_dev_plan.md` §15.0 B
# (+ the 2026-10-09 decision), `features/season/training/README.md` "Limit break".
#
# State lives in the pilot's `season_state.training_level` entry (`TrainingLevel`):
#   offer  [goal id ×3]  — drawn once when the dialogue is first built (seeded)
#   goal   {} | {"id", "since_match", "set_week", "set_day", "recs": [match record…]}
#   note   {} | {"pilot_id", "level", "goal", "source", "gain", "week", "day", "seen"}
# Match record (one per my match the pilot played since the goal was set, last
# `WINDOW` kept): {"k", "d", "a", "obj", "mvp", "top_kills", "top_score", "top_turret", "top_care"}.
#
#   event  "" | mental event id of the dialogue lines (drawn once, kept until a pick)
#
# Dialogue lines are authored in Draft (`narrative/`, kind `limit_break`, cond `tlevel`) and
# imported into `mental_events` / `mental_texts` like every mental event: the opening lines
# are the event's `line` texts, the closing reply is the `say` list of its **single
# placeholder option** (the Draft convention needs a Select; its option text is never shown).
# The 3 choices are UI text — the drawn goals with live numbers (`training.limit_break.goal.*`).

## Overlay / session kind the week screen uses (`VnDialogueView`).
const KIND: String = "limit_break"

const GOAL_KDA: String = "kda"
const GOAL_KILLS: String = "kills"
const GOAL_OBJ: String = "obj"
const GOAL_MVP: String = "mvp"
const GOAL_SCORE: String = "score"
const GOAL_TURRET: String = "turret"
const GOAL_CARE: String = "care"

const SOURCE_GOAL: String = "goal"
const SOURCE_FOCUS: String = "focus"

## The 7-goal pool, pool order = §15.0 B order. `only` / `not` = `GameEnums.Role` filter.
## `rank` = pilot_stats key whose game-wide rank 1 is required in each match of the window.
const GOALS: Array = [
	{"id": GOAL_KDA, "key": L.TRAINING_LIMIT_BREAK_GOAL_KDA},
	{"id": GOAL_KILLS, "key": L.TRAINING_LIMIT_BREAK_GOAL_KILLS, "rank": "k",
			"not": [GameEnums.Role.SUPPORT]},
	{"id": GOAL_OBJ, "key": L.TRAINING_LIMIT_BREAK_GOAL_OBJ,
			"only": [GameEnums.Role.ASSASSIN, GameEnums.Role.FIGHTER]},
	{"id": GOAL_MVP, "key": L.TRAINING_LIMIT_BREAK_GOAL_MVP},
	{"id": GOAL_SCORE, "key": L.TRAINING_LIMIT_BREAK_GOAL_SCORE, "rank": "score",
			"not": [GameEnums.Role.SUPPORT]},
	{"id": GOAL_TURRET, "key": L.TRAINING_LIMIT_BREAK_GOAL_TURRET, "rank": "turret",
			"not": [GameEnums.Role.SUPPORT, GameEnums.Role.ASSASSIN]},
	{"id": GOAL_CARE, "key": L.TRAINING_LIMIT_BREAK_GOAL_CARE, "rank": "care",
			"only": [GameEnums.Role.SUPPORT]},
]

static var STAT_GAIN: int = ConstTable.int_of("LIMIT_BREAK_STAT_GAIN")
static var OFFER: int = ConstTable.int_of("LIMIT_BREAK_OFFER")
static var WINDOW: int = ConstTable.int_of("LIMIT_BREAK_WINDOW")
static var WINDOW_MVP: int = ConstTable.int_of("LIMIT_BREAK_WINDOW_MVP")
static var KDA_NEED: float = ConstTable.num("LIMIT_BREAK_KDA")
static var OBJ_TURN: int = ConstTable.int_of("LIMIT_BREAK_OBJ_TURN")
static var OBJ_NEED: int = ConstTable.int_of("LIMIT_BREAK_OBJ_NEED")


# ── Event ────────────────────────────────────────────────────────────────────
## Pilot whose limit-break dialogue must open on the evening of `day`, -1 = none.
## A pilot is due when the bar is locked at an even level, no goal is set yet and the
## level was reached on this day or earlier (an earlier week counts — "the next evening reached").
## Several due pilots → the first in seat order; after `choose_goal` the next one is returned.
static func pending_event(state: Dictionary, day: int) -> int:
	var wk: String = MentalSystem.week_key(state)
	for pid in _my_pilots_by_seat(state):
		var e: Dictionary = TrainingLevel.entry(state, pid)
		if not TrainingLevel.awaiting_break(state, pid) or not (e.get("goal", {}) as Dictionary).is_empty():
			continue
		var ev_day: int = int(e.get("event_day", -1))
		if String(e.get("event_week", "")) != wk or ev_day < 0 or day >= ev_day:
			return pid
	return -1


## View dict for `VnDialogueView` (same shape as `MentalSystem.session_view`, plus
## `sub` / `title` for `open`'s header). {} when `pid` is not due a limit break.
##   view.open(view.sub, view.title, pid, view.lines, view.choices, "", view.previews)
static func session(state: Dictionary, pid: int) -> Dictionary:
	if not TrainingLevel.awaiting_break(state, pid):
		return {}
	var offer: Array = offer_of(state, pid)
	if offer.is_empty():
		return {}
	var r: Dictionary = event_row(state, pid)
	var lines: Array = []
	for k in (r.get("lines", []) as Array):
		var t: String = MentalEvents.text(state, String(k), pid).strip_edges()
		if t != "" and not t.begins_with("@"):
			lines.append(t)
	var choices: Array = []
	var previews: Array = []
	var preview: String = Loc.t(L.TRAINING_LIMIT_BREAK_PREVIEW, {"gain": STAT_GAIN})
	for raw in offer:
		choices.append(goal_name(String(raw)))
		previews.append(preview)
	var title: String = Loc.t(L.TRAINING_LIMIT_BREAK_TITLE)
	return {"kind": KIND, "event": String(r.get("id", KIND)), "pilot_id": pid, "partner_id": -1, "tag": title,
			"sub": title, "title": MentalEvents.pilot_name(state, pid),
			"lines": lines, "choices": choices, "previews": previews}


## The manager picked goal `idx` of the offer → outcome view for `VnDialogueView.show_result`
## (`{checked, ok, say, notes}`). Stores the goal; a second call returns the same view.
static func choose_goal(state: Dictionary, pid: int, idx: int) -> Dictionary:
	var e: Dictionary = TrainingLevel.entry(state, pid)
	if e.is_empty():
		return {}
	var goal: Dictionary = e.get("goal", {})
	if goal.is_empty():
		var offer: Array = offer_of(state, pid)
		if offer.is_empty():
			return {}
		var id: String = String(offer[clampi(idx, 0, offer.size() - 1)])
		goal = {"id": id, "since_match": _matches_played(state),
				"set_week": MentalSystem.week_key(state), "set_day": int(state.get("week_day", -1)),
				"recs": []}
		e["goal"] = goal
		e["offer"] = []
	# Closing reply = the says of the Draft row's single placeholder option.
	var say: Array = []
	var says: Array = event_row(state, pid).get("says", [])
	for sv in (says[0] if not says.is_empty() else []):
		if String((sv as Dictionary).get("branch", "")) == "":
			say.append(MentalEvents.text(state, String((sv as Dictionary)["key"]), pid))
	return {"checked": false, "ok": true, "say": say,
			"notes": [Loc.t(L.TRAINING_LIMIT_BREAK_NOTE_GOAL, {"goal": goal_name(String(goal["id"]))})]}


## The Draft dialogue row (`MentalEvents`, kind `limit_break`) for this limit break: drawn once
## among the rows whose cond holds for the pilot (`tlevel=N` …), weighted and seeded like
## `MentalSystem._draw`, then kept in the entry (`event`) until the goal is picked. {} = none
## imported (the dialogue then shows only the choices).
static func event_row(state: Dictionary, pid: int) -> Dictionary:
	var e: Dictionary = TrainingLevel.entry(state, pid)
	var have: String = String(e.get("event", ""))
	if have != "":
		var kept: Dictionary = MentalEvents.row(have)
		if not kept.is_empty():
			return kept
	var cands: Array = []
	for r_raw in MentalEvents.rows_of(MentalEvents.KIND_LIMIT_BREAK):
		var r: Dictionary = r_raw
		if MentalEvents.type_ok(state, r) and MentalEvents.cond_ok(state, r, pid):
			cands.append(r)
	var picked: Dictionary = MentalEvents.weighted_pick(state, cands, _rng(state, pid, "lines"))
	if not picked.is_empty() and not e.is_empty():
		e["event"] = String(picked["id"])
	return picked


## The 3 offered goal ids — drawn once per limit break (seeded by run · pilot · level) from
## the pool filtered by the pilot's position, then kept in the entry until a goal is picked.
static func offer_of(state: Dictionary, pid: int) -> Array:
	var e: Dictionary = TrainingLevel.entry(state, pid)
	if e.is_empty():
		return []
	var have: Variant = e.get("offer", [])
	if have is Array and not (have as Array).is_empty():
		return have
	var pd: PlayerData = MentalEvents.pilot_of(state, pid)
	var cands: Array = pool_for_role(pd.role if pd != null else -1)
	var rng := _rng(state, pid, "offer")
	for i in range(cands.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t: Variant = cands[i]
		cands[i] = cands[j]
		cands[j] = t
	var offer: Array = cands.slice(0, mini(OFFER, cands.size()))
	e["offer"] = offer
	return offer


## Goal ids allowed for `role` (pool order).
static func pool_for_role(role: int) -> Array:
	var out: Array = []
	for g in GOALS:
		var only: Array = g.get("only", [])
		var excl: Array = g.get("not", [])
		if not only.is_empty() and not only.has(role):
			continue
		if excl.has(role):
			continue
		out.append(String(g["id"]))
	return out


# ── Goal ─────────────────────────────────────────────────────────────────────
static func goal_active(state: Dictionary, pid: int) -> bool:
	return not goal_of(state, pid).is_empty()


## The active goal dict ({} = none).
static func goal_of(state: Dictionary, pid: int) -> Dictionary:
	var g: Variant = TrainingLevel.entry(state, pid).get("goal", {})
	return g if g is Dictionary else {}


## Translated one-line goal text with progress ("" when none) — "목표 — … (1/2)".
static func goal_text(state: Dictionary, pid: int) -> String:
	var g: Dictionary = goal_of(state, pid)
	if g.is_empty():
		return ""
	return Loc.t(L.TRAINING_LIMIT_BREAK_GOAL_LINE,
			{"goal": goal_name(String(g["id"])), "progress": progress_text(g)})


## The goal's name with its numbers ("다음 2경기 합산 KDA 4 이상").
static func goal_name(id: String) -> String:
	var g: Dictionary = _goal_def(id)
	if g.is_empty():
		return id
	return Loc.t(String(g["key"]), {"n": window_of(id), "kda": _fmt_kda(KDA_NEED),  # l10n-dynamic: training.limit_break.goal.*
			"turn": OBJ_TURN, "need": OBJ_NEED})


## Matches the goal is judged on (sliding window of my last matches since it was set).
static func window_of(id: String) -> int:
	return WINDOW_MVP if id == GOAL_MVP else WINDOW


## `{have, need}` toward the goal over the current window (KDA: the window's KDA vs. the need).
static func progress(goal: Dictionary) -> Dictionary:
	var id: String = String(goal.get("id", ""))
	var w: int = window_of(id)
	var recs: Array = _window(goal, w)
	match id:
		GOAL_KDA:
			var ka: int = 0
			var d: int = 0
			for r in recs:
				ka += int(r.get("k", 0)) + int(r.get("a", 0))
				d += int(r.get("d", 0))
			return {"have": float(ka) / float(maxi(d, 1)) if not recs.is_empty() else 0.0,
					"need": KDA_NEED}
		GOAL_OBJ:
			var n: int = 0
			for r in recs:
				n += int(r.get("obj", 0))
			return {"have": float(n), "need": float(OBJ_NEED)}
		GOAL_MVP:
			var hit: int = 1 if not recs.is_empty() and bool(recs[-1].get("mvp", false)) else 0
			return {"have": float(hit), "need": float(w)}
	# Rank goals: the streak of rank-1 matches at the end of the window.
	var flag: String = "top_" + id   # match_record flag of that goal
	var streak: int = 0
	for i in range(recs.size() - 1, -1, -1):
		if not bool(recs[i].get(flag, false)):
			break
		streak += 1
	return {"have": float(streak), "need": float(w)}


## The goal is met: the window holds `window_of` matches and the progress reaches the need.
static func is_met(goal: Dictionary) -> bool:
	var id: String = String(goal.get("id", ""))
	if _window(goal, window_of(id)).size() < window_of(id):
		return false
	var p: Dictionary = progress(goal)
	return float(p["have"]) >= float(p["need"])


static func progress_text(goal: Dictionary) -> String:
	var p: Dictionary = progress(goal)
	if String(goal.get("id", "")) == GOAL_KDA:
		return Loc.t(L.TRAINING_LIMIT_BREAK_PROGRESS_KDA,
				{"v": _fmt_kda(float(p["have"])), "need": _fmt_kda(float(p["need"]))})
	return Loc.t(L.TRAINING_LIMIT_BREAK_PROGRESS_COUNT,
			{"have": int(p["have"]), "need": int(p["need"])})


# ── Completion ───────────────────────────────────────────────────────────────
## Finish the limit break now (goal met / focus training): stats up, the bar unlocks, the level
## stays (`TrainingLevel.break_done`). Returns the result note (also kept in the entry for the
## week screen / hub, `unseen_notes`); {} when no limit break was due.
## `source` = SOURCE_GOAL | SOURCE_FOCUS.
static func complete(state: Dictionary, pid: int, source: String = SOURCE_FOCUS) -> Dictionary:
	var e: Dictionary = TrainingLevel.entry(state, pid)
	if e.is_empty() or not TrainingLevel.break_done(state, pid):
		return {}
	var goal_id: String = String((e.get("goal", {}) as Dictionary).get("id", ""))
	var lv: int = TrainingLevel.level(state, pid)
	var pd: PlayerData = MentalEvents.pilot_of(state, pid)
	if pd != null:
		for sk in PlayerData.STAT_KEYS:
			var key: String = String(sk)
			pd.set(key, maxi(PlayerData.STAT_MIN, int(pd.get(key)) + STAT_GAIN))
	e["goal"] = {}
	e["offer"] = []
	e["event"] = ""
	var note: Dictionary = {"pilot_id": pid, "level": lv, "goal": goal_id, "source": source,
			"gain": STAT_GAIN, "week": MentalSystem.week_key(state),
			"day": int(state.get("week_day", -1)), "seen": false}
	e["note"] = note
	return note


## Result notes not shown yet (`seen` false), seat order.
static func unseen_notes(state: Dictionary) -> Array:
	var out: Array = []
	for pid in _my_pilots_by_seat(state):
		var n: Variant = TrainingLevel.entry(state, pid).get("note", {})
		if n is Dictionary and not (n as Dictionary).is_empty() and not bool(n.get("seen", false)):
			out.append(n)
	return out


static func mark_note_seen(state: Dictionary, pid: int) -> void:
	var n: Variant = TrainingLevel.entry(state, pid).get("note", {})
	if n is Dictionary and not (n as Dictionary).is_empty():
		n["seen"] = true


## "한계돌파 성공 · 깨달음 레벨 Lv2 · 모든 스탯 +3" for a note from `complete` (`n` = the level,
## unchanged by the limit break).
static func note_text(state: Dictionary, note: Dictionary) -> String:
	return Loc.t(L.TRAINING_LIMIT_BREAK_NOTE_DONE, {
		"name": MentalEvents.pilot_name(state, int(note.get("pilot_id", -1))),
		"n": int(note.get("level", 1)), "gain": int(note.get("gain", STAT_GAIN))})


# ── Match judging ────────────────────────────────────────────────────────────
## `SeasonHub._consume_pending_match_result` hook (after `RunStats.record_match`).
## For each of my pilots with an active goal who played (a `side == 0` row), appends that
## match's record to the goal's window and completes the limit break when the goal is met.
## Idempotent (`pending_match.limit_break_recorded`).
static func record_match(state: Dictionary, pending_match: Dictionary) -> void:
	if bool(pending_match.get("limit_break_recorded", false)):
		return
	if int(pending_match.get("winner_side", -1)) < 0:
		return
	pending_match["limit_break_recorded"] = true
	var rows_v: Variant = pending_match.get("pilot_stats", [])
	var rows: Array = rows_v if rows_v is Array else []
	if rows.is_empty():
		return
	var mvp: int = int(pending_match.get("mvp_pilot_id", -1))
	for pid in _my_pilots_by_seat(state):
		var goal: Dictionary = goal_of(state, pid)
		if goal.is_empty():
			continue
		var row: Dictionary = {}
		for raw in rows:
			if raw is Dictionary and int(raw.get("pilot_id", -1)) == pid and int(raw.get("side", -1)) == 0:
				row = raw
				break
		if row.is_empty():
			continue
		var recs: Array = goal.get("recs", [])
		recs.append(match_record(rows, row, mvp))
		while recs.size() > WINDOW:
			recs.pop_front()
		goal["recs"] = recs
		if is_met(goal):
			complete(state, pid, SOURCE_GOAL)


## One match record for the goal window (see the header).
static func match_record(rows: Array, row: Dictionary, mvp_pilot_id: int) -> Dictionary:
	var obj: int = 0
	for t in (row.get("obj_turns", []) as Array):
		if int(t) <= OBJ_TURN:
			obj += 1
	return {"k": int(row.get("k", 0)), "d": int(row.get("d", 0)), "a": int(row.get("a", 0)),
			"obj": obj, "mvp": mvp_pilot_id >= 0 and int(row.get("pilot_id", -1)) == mvp_pilot_id,
			"top_kills": is_rank_one(rows, row, "k"), "top_score": is_rank_one(rows, row, "score"),
			"top_turret": is_rank_one(rows, row, "turret"), "top_care": is_rank_one(rows, row, "care")}


## `row` holds the highest `key` value among all rows (both teams; ties count as rank 1).
## A zero value is never rank 1 — a game where nobody scored does not hand out the goal.
static func is_rank_one(rows: Array, row: Dictionary, key: String) -> bool:
	var mine: float = float(row.get(key, 0))
	if mine <= 0.0:
		return false
	for raw in rows:
		if raw is Dictionary and float(raw.get(key, 0)) > mine:
			return false
	return true


# ── Internals ────────────────────────────────────────────────────────────────
static func _goal_def(id: String) -> Dictionary:
	for g in GOALS:
		if String(g["id"]) == id:
			return g
	return {}


## The last `w` match records of the goal.
static func _window(goal: Dictionary, w: int) -> Array:
	var recs: Array = goal.get("recs", [])
	return recs.slice(maxi(0, recs.size() - w))


static func _fmt_kda(v: float) -> String:
	return ("%.1f" % v).trim_suffix(".0")


## My matches recorded so far (`run_stats.matches`) — stored as the goal's `since_match`.
static func _matches_played(state: Dictionary) -> int:
	var rs: Variant = state.get("run_stats", {})
	if rs is Dictionary and (rs as Dictionary).get("matches", null) is Array:
		return ((rs as Dictionary)["matches"] as Array).size()
	return 0


## My pilots that have a training level, in seat order (`GameEnums.role_seat`).
static func _my_pilots_by_seat(state: Dictionary) -> Array:
	var ids: Array = []
	for raw in MentalSystem.my_pilot_ids(state):
		if TrainingLevel.has_level(state, int(raw)):
			ids.append(int(raw))
	ids.sort_custom(func(a: int, b: int) -> bool:
		var pa: PlayerData = MentalEvents.pilot_of(state, a)
		var pb: PlayerData = MentalEvents.pilot_of(state, b)
		var sa: int = GameEnums.role_seat(pa.role) if pa != null else 99
		var sb: int = GameEnums.role_seat(pb.role) if pb != null else 99
		return sa < sb if sa != sb else a < b)
	return ids


## Deterministic RNG per run · pilot · level · purpose (like `MentalSystem._seed`).
static func _rng(state: Dictionary, pid: int, purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(state.get("run_seed", 0)), pid, TrainingLevel.level(state, pid),
			"limit_break", purpose])
	return rng
