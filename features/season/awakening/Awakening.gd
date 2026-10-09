class_name Awakening
extends RefCounted

# ── Awakening (깨달음, §15 C) ────────────────────────────────────────────────
# Per-pilot gauge in percent points. Training, stories, incidents, focus training …
# add to it (`add_gauge`); every time it reaches AWAKEN_THRESHOLD (100) one awakening is
# queued and the gauge drops by the threshold (130 → 30, a pending awakening keeps its
# place in the queue). The week screen polls `next_pending` and opens `AwakeningView`;
# the pilot picks 1 of 3: card upgrade / card swap / add preset (`PilotLoadout`).
# Resolving (`resolve_*`) writes the loadout, pops the queue and counts the awakening —
# a queued awakening that was never resolved (app closed) simply reopens.
#
# State (JSON-round-tripped, string keys, `int()` reads):
#   season_state.awakening         = {"<pid>": int gauge}
#   season_state.awakening_pending = [pid, …]           (queue, a pid may repeat)
#   season_state.awakening_count   = {"<pid>": int}     (resolved awakenings — seeds the draws)
# Candidate draws are deterministic per run · pid · awakening count (`_rng`), so reopening
# the same awakening shows the same candidates.

const KEY_GAUGE: String = "awakening"
const KEY_PENDING: String = "awakening_pending"
const KEY_COUNT: String = "awakening_count"

const KIND_UPGRADE: String = "upgrade"
const KIND_SWAP: String = "swap"
const KIND_PRESET: String = "preset"
const KIND_SKIP: String = "skip"


static func init_run(state: Dictionary) -> void:
	var g: Dictionary = {}
	var n: Dictionary = {}
	for pid in MentalSystem.my_pilot_ids(state):
		g[str(pid)] = 0
		n[str(pid)] = 0
	state[KEY_GAUGE] = g
	state[KEY_COUNT] = n
	state[KEY_PENDING] = []


static func gauge(state: Dictionary, pid: int) -> int:
	return int((state.get(KEY_GAUGE, {}) as Dictionary).get(str(pid), 0))


static func threshold() -> int:
	return maxi(ConstTable.int_of("AWAKEN_THRESHOLD"), 1)


## Add to the gauge (`source` = short id for logs / notes). Crossing the threshold queues an
## event and takes the threshold off the gauge (as many times as it was crossed). Only my
## pilots have a gauge; a negative amount lowers it, never below 0.
static func add_gauge(state: Dictionary, pid: int, amount: int, source: String = "") -> void:
	if amount == 0 or not MentalSystem.my_pilot_ids(state).has(pid):
		return
	if not (state.get(KEY_GAUGE, null) is Dictionary):
		state[KEY_GAUGE] = {}
	var d: Dictionary = state[KEY_GAUGE]
	var v: int = maxi(gauge(state, pid) + amount, 0)
	var queued: int = 0
	while v >= threshold():
		v -= threshold()
		_pending(state).append(pid)
		queued += 1
	d[str(pid)] = v
	if queued > 0 and OS.is_debug_build():
		print("Awakening: pilot %d queued %d (source %s, gauge now %d)" % [pid, queued, source, v])


## Pilot with a queued awakening, -1 = none. The week screen polls this after each state change.
static func next_pending(state: Dictionary) -> int:
	var q: Array = _pending(state)
	return int(q[0]) if not q.is_empty() else -1


## Queued awakenings of `pid` (for a "pending" mark on the detail sheet).
static func pending_count(state: Dictionary, pid: int) -> int:
	var n: int = 0
	for raw in _pending(state):
		if int(raw) == pid:
			n += 1
	return n


## Resolved awakenings of `pid` so far this run.
static func count(state: Dictionary, pid: int) -> int:
	return int((state.get(KEY_COUNT, {}) as Dictionary).get(str(pid), 0))


## `TrainingBoard.apply_day_training` hook. Each row's day EXP (`exp` = stat → EXP earned) ×
## AWAKEN_TRAIN_PER_EXP, clamped to AWAKEN_TRAIN_MIN..MAX (0 on a day without EXP). The gain
## is written back on the row as `awaken` so the week screen can show it.
static func on_training_day(state: Dictionary, rows: Array) -> void:
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var row := raw as Dictionary
		var total: int = 0
		for v in (row.get("exp", {}) as Dictionary).values():
			total += maxi(int(v), 0)
		var gain: int = 0
		if total > 0:
			gain = clampi(roundi(float(total) * ConstTable.num("AWAKEN_TRAIN_PER_EXP")),
					ConstTable.int_of("AWAKEN_TRAIN_MIN"), ConstTable.int_of("AWAKEN_TRAIN_MAX"))
		row["awaken"] = gain
		add_gauge(state, int(row.get("pilot_id", -1)), gain, "train")


## `SeasonHub._consume_pending_match_result` hook. Every pilot of mine gets AWAKEN_MATCH_BASE,
## plus AWAKEN_MATCH_RANK_BONUS scaled by the MVP-metric rank among my five (best = full,
## worst = 0), plus AWAKEN_MATCH_MVP for the match MVP. Runs once per match
## (`pending_match.awakening_recorded`); the gains land in `pending_match.awakening_gains`.
static func on_match(state: Dictionary, pending_match: Dictionary) -> void:
	if bool(pending_match.get("awakening_recorded", false)):
		return
	if int(pending_match.get("winner_side", -1)) < 0:
		return
	pending_match["awakening_recorded"] = true
	var mine: Array = MentalSystem.my_pilot_ids(state)
	var scores: Dictionary = {}
	var rows_v: Variant = pending_match.get("pilot_stats", [])
	var rows: Array = []
	if rows_v is Array:
		rows = rows_v
	for raw in rows:
		if raw is Dictionary and mine.has(int((raw as Dictionary).get("pilot_id", -1))):
			scores[int((raw as Dictionary)["pilot_id"])] = RunStats.mvp_score(raw as Dictionary)
	var ranked: Array = scores.keys()
	ranked.sort_custom(func(a, b) -> bool: return float(scores[a]) > float(scores[b]))
	var mvp: int = int(pending_match.get("mvp_pilot_id", -1))
	var gains: Dictionary = {}
	for raw in mine:
		var pid: int = int(raw)
		var gain: int = ConstTable.int_of("AWAKEN_MATCH_BASE")
		var i: int = ranked.find(pid)
		if i >= 0 and ranked.size() > 1:
			gain += roundi(float(ConstTable.int_of("AWAKEN_MATCH_RANK_BONUS")) \
					* float(ranked.size() - 1 - i) / float(ranked.size() - 1))
		if pid == mvp:
			gain += ConstTable.int_of("AWAKEN_MATCH_MVP")
		gains[str(pid)] = gain
		add_gauge(state, pid, gain, "match")
	pending_match["awakening_gains"] = gains


# ── Choices ──────────────────────────────────────────────────────────────────

## What the awakening of `pid` may do now: `{upgrade, swap, preset: bool}` + `preset_reason`
## ("" / "level" = training level too low / "max" = extras full).
static func options(state: Dictionary, pid: int) -> Dictionary:
	var up: bool = false
	var sw: bool = false
	var n: int = PilotLoadout.presets(state, pid).size()
	for i in n:
		if not upgradable(state, pid, i).is_empty():
			up = true
		if not swap_candidates(state, pid, i).is_empty():
			sw = true
	var reason: String = ""
	if not PilotLoadout.can_add_preset(state, pid):
		reason = "max" if PilotLoadout.extra_count(state, pid) >= ConstTable.int_of("LOADOUT_EXTRA_MAX") \
				else "level"
	return {KIND_UPGRADE: up, KIND_SWAP: sw,
			KIND_PRESET: reason == "" and not preset_candidates(state, pid).is_empty(),
			"preset_reason": reason}


## Cards of preset `idx` that still have an upgrade ("+" rows are not upgradable again).
static func upgradable(state: Dictionary, pid: int, idx: int) -> Array:
	var out: Array = []
	for c in PilotLoadout.preset(state, pid, idx):
		if PilotLoadout.upgrade_of(int(c)) >= 0:
			out.append(int(c))
	return out


## AWAKEN_SWAP_CANDIDATES cards that could come into preset `idx` (pool rules of
## `PilotLoadout.candidate_pool`), deterministic per run · pid · awakening count · preset.
static func swap_candidates(state: Dictionary, pid: int, idx: int) -> Array:
	var held: Array = PilotLoadout.preset(state, pid, idx)
	if held.is_empty():
		return []
	var pool: Array = PilotLoadout.candidate_pool(state, pid, held)
	_shuffle(pool, _rng(state, pid, KIND_SWAP, idx))
	return pool.slice(0, ConstTable.int_of("AWAKEN_SWAP_CANDIDATES"))


## AWAKEN_PRESET_CANDIDATES new presets of 3 pool cards each (pool rules, no family twice
## inside a preset). The candidates take consecutive cards of one shuffled pool, so they do
## not share cards while the pool is big enough.
static func preset_candidates(state: Dictionary, pid: int) -> Array:
	var pool: Array = PilotLoadout.candidate_pool(state, pid, [])
	if pool.size() < PilotLoadout.CARDS_PER_PRESET:
		return []
	_shuffle(pool, _rng(state, pid, KIND_PRESET, 0))
	var out: Array = []
	var cursor: int = 0
	for _i in ConstTable.int_of("AWAKEN_PRESET_CANDIDATES"):
		var ids: Array = []
		var guard: int = 0
		while ids.size() < PilotLoadout.CARDS_PER_PRESET and guard < pool.size() * 2:
			var c: int = int(pool[cursor % pool.size()])
			cursor += 1
			guard += 1
			if not PilotLoadout.candidate_pool(state, pid, ids).has(c):
				continue
			ids.append(c)
		if ids.size() == PilotLoadout.CARDS_PER_PRESET:
			out.append(ids)
	return out


## Upgrade `card_id` in preset `idx`. → `{ok, kind, preset, from, to}`.
static func resolve_upgrade(state: Dictionary, pid: int, idx: int, card_id: int) -> Dictionary:
	if not _is_next(state, pid) or not upgradable(state, pid, idx).has(card_id):
		return {"ok": false}
	var to: int = PilotLoadout.upgrade_of(card_id)
	if not PilotLoadout.upgrade_card(state, pid, idx, card_id):
		return {"ok": false}
	_consume(state, pid)
	return {"ok": true, "kind": KIND_UPGRADE, "preset": idx, "from": card_id, "to": to}


## Swap `out_id` of preset `idx` for the candidate `in_id`. → `{ok, kind, preset, from, to}`.
static func resolve_swap(state: Dictionary, pid: int, idx: int, out_id: int, in_id: int) -> Dictionary:
	if not _is_next(state, pid) or not swap_candidates(state, pid, idx).has(in_id):
		return {"ok": false}
	if not PilotLoadout.swap_card(state, pid, idx, out_id, in_id):
		return {"ok": false}
	_consume(state, pid)
	return {"ok": true, "kind": KIND_SWAP, "preset": idx, "from": out_id, "to": in_id}


## Add candidate preset `cand` (index into `preset_candidates`). → `{ok, kind, preset, cards}`.
static func resolve_preset(state: Dictionary, pid: int, cand: int) -> Dictionary:
	if not _is_next(state, pid) or not PilotLoadout.can_add_preset(state, pid):
		return {"ok": false}
	var cands: Array = preset_candidates(state, pid)
	if cand < 0 or cand >= cands.size():
		return {"ok": false}
	var idx: int = PilotLoadout.add_preset(state, pid, cands[cand])
	if idx < 0:
		return {"ok": false}
	_consume(state, pid)
	return {"ok": true, "kind": KIND_PRESET, "preset": idx, "cards": (cands[cand] as Array).duplicate()}


## No option is available (every card upgraded, empty pool, preset locked): the awakening is
## spent without an effect so the queue never sticks.
static func resolve_skip(state: Dictionary, pid: int) -> Dictionary:
	if not _is_next(state, pid):
		return {"ok": false}
	_consume(state, pid)
	return {"ok": true, "kind": KIND_SKIP}


static func _is_next(state: Dictionary, pid: int) -> bool:
	# Not `has` — after a JSON load the queue holds floats.
	return pending_count(state, pid) > 0


## Pop one queued awakening of `pid` and count it (the next draw of this pilot changes).
static func _consume(state: Dictionary, pid: int) -> void:
	var q: Array = _pending(state)
	for i in q.size():
		if int(q[i]) == pid:
			q.remove_at(i)
			break
	if not (state.get(KEY_COUNT, null) is Dictionary):
		state[KEY_COUNT] = {}
	var n: Dictionary = state[KEY_COUNT]
	n[str(pid)] = count(state, pid) + 1


static func _pending(state: Dictionary) -> Array:
	if not (state.get(KEY_PENDING, null) is Array):
		state[KEY_PENDING] = []
	return state[KEY_PENDING]


## Seeded per run · pid · awakening count · draw kind · preset.
static func _rng(state: Dictionary, pid: int, kind: String, idx: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:%d:%d:%s:%d" % [int(state.get("run_seed", 0)), pid, count(state, pid),
			kind, idx]).hash()
	return rng


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t
