class_name MentalEvents
extends RefCounted

# ── mental_events.csv + mental_texts.csv — table, grammar, effects (M7, D6) ──
# One `mental_events` row = one interview / outing stage / incident / press conference.
# Its texts are `mental_texts` rows (l10n keys) by `event_id`:
#   slot `line`   — in `seq` order. Text marker: plain = the other side speaks (left
#                   bubble), `>text` = the manager (right bubble), `*text` = narration,
#                   `@text` = tag (press outlet / incident name), not shown as a bubble.
#   slot `choice` — manager answer `choice` (0-based).
#   slot `say`    — reply line after answer `choice`; `branch` ok / ng = only on a
#                   passed / failed mental check, "" = always; `seq` order.
# Grammar of `effects` / `cond` (full reference in `features/season/mental/README.md`):
#   effects — `|`-joined, ONE entry per choice; clauses inside an entry joined
#             with `;`. Clause prefix `ok>` / `ng>` = only on a passed / failed
#             mental check (an entry with any gated clause **or a gated say** rolls a check).
#   cond    — `;`-joined tokens that must all hold for the row to be drawn.
# `{name}` in any text is filled with the target pilot's name at display time
# (`Loc.t(key, {"name": …})`). Outcomes keep **keys / ids only** (they are saved).
#
# Pure static helpers over a `season_state` dictionary — no autoloads.

const KIND_INTERVIEW: String = "interview"
const KIND_OUTING: String = "outing"
const KIND_INCIDENT: String = "incident"
const KIND_PRESS: String = "press"

## Cond keys (clause types are listed in `parse_clause` and the README).
const COND_KEYS: Array = ["trust", "outings", "role", "last", "mention", "week"]

static var _rows: Array = []            # parsed rows, CSV order
static var _by_id: Dictionary = {}      # id → parsed row
static var _loaded: bool = false


# ── Table ────────────────────────────────────────────────────────────────────
static func all_rows() -> Array:
	_ensure_loaded()
	return _rows


static func rows_of(kind: String) -> Array:
	var out: Array = []
	for r in all_rows():
		if String((r as Dictionary)["kind"]) == kind:
			out.append(r)
	return out


static func row(event_id: String) -> Dictionary:
	_ensure_loaded()
	return _by_id.get(event_id, {})


## Parse one raw `mental_events` row + its raw `mental_texts` rows into
## `{id, kind, manager_type, stage, weight, cond[], lines[key], choices[key],
##   says[[{branch, key}]] (one list per choice), effects[[clause]]}`.
## Line keys still carry their `>` / `*` / `@` marker in the text — `session_view` reads it.
static func parse_row(raw: Dictionary, texts: Array = []) -> Dictionary:
	var line_rows: Array = []
	var choice_rows: Array = []
	var say_rows: Array = []
	for t_raw in texts:
		var t: Dictionary = t_raw
		match String(t.get("slot", "")):
			"line": line_rows.append(t)
			"choice": choice_rows.append(t)
			"say": say_rows.append(t)
	line_rows.sort_custom(func(a, b): return int(a["seq"]) < int(b["seq"]))
	choice_rows.sort_custom(func(a, b): return int(a["choice"]) < int(b["choice"]))
	say_rows.sort_custom(func(a, b): return int(a["seq"]) < int(b["seq"]))
	var lines: Array = []
	for t in line_rows:
		lines.append(String((t as Dictionary)["text_key"]))
	var choices: Array = []
	for t in choice_rows:
		choices.append(String((t as Dictionary)["text_key"]))
	var says: Array = []
	for i in choices.size():
		says.append([])
	for t_raw in say_rows:
		var t: Dictionary = t_raw
		var ci: int = int(t["choice"])
		if ci >= 0 and ci < says.size():
			(says[ci] as Array).append({"branch": String(t.get("branch", "")),
					"key": String(t["text_key"])})
	var effects: Array = []
	for entry in String(raw.get("effects", "")).split("|", true):
		effects.append(parse_effect(String(entry)))
	return {
		"id": String(raw.get("id", "")),
		"kind": String(raw.get("kind", "")),
		"manager_type": int(raw.get("manager_type", -1)),
		"stage": int(raw.get("stage", 0)),
		"weight": maxi(0, int(raw.get("weight", 1))),
		"cond": parse_cond(String(raw.get("cond", ""))),
		"lines": lines,
		"choices": choices,
		"says": says,
		"effects": effects,
	}


## One effects entry → Array of clauses `{gate: ""|"ok"|"ng", type, ...}`.
static func parse_effect(entry: String) -> Array:
	var out: Array = []
	for part in entry.split(";", false):
		var t: String = (part as String).strip_edges()
		if t != "":
			out.append(parse_clause(t))
	return out


## `trust:+4` → `{gate, type:"trust", delta:4}` — see README for every type.
## Unknown / malformed → `{type:"invalid", raw}` (skipped when applied, reported by `lint`).
static func parse_clause(text: String) -> Dictionary:
	var gate: String = ""
	var body: String = text.strip_edges()
	if body.begins_with("ok>"):
		gate = "ok"
		body = body.substr(3)
	elif body.begins_with("ng>"):
		gate = "ng"
		body = body.substr(3)
	var bad: Dictionary = {"gate": gate, "type": "invalid", "raw": text}
	var colon: int = body.find(":")
	if colon < 0:
		return bad
	var kind: String = body.substr(0, colon).strip_edges()
	var rest: String = body.substr(colon + 1)
	var args: PackedStringArray = rest.split(":")
	match kind:
		"trust", "trust_all", "chk":
			if args.size() != 1 or not _is_int(args[0]):
				return bad
			return {"gate": gate, "type": kind, "delta": _to_int(args[0])}
		"pmod", "pmod_all":
			if args.size() != 3 or not _is_int(args[1]) or not _is_int(args[2]):
				return bad
			var stat: String = args[0].strip_edges()
			if stat != "all" and not PlayerData.STAT_KEYS.has(stat):
				return bad
			return {"gate": gate, "type": kind, "stat": stat,
					"delta": _to_int(args[1]), "weeks": _to_int(args[2])}
		"smod":
			if args.size() != 3 or not _is_int(args[1]) or not _is_int(args[2]):
				return bad
			var sstat: String = args[0].strip_edges()
			if not StaffSystem.STATS.has(sstat) or _to_int(args[2]) <= 0:
				return bad
			return {"gate": gate, "type": "smod", "stat": sstat,
					"delta": _to_int(args[1]), "weeks": _to_int(args[2])}
	return bad


## `trust>=30;last=win` → `[{key, op, value}]`. Ops `>=`, `<`, `=`.
static func parse_cond(text: String) -> Array:
	var out: Array = []
	for part in text.split(";", false):
		var t: String = (part as String).strip_edges()
		if t == "":
			continue
		var op: String = ""
		for cand in [">=", "<", "="]:
			if t.find(cand) > 0:
				op = cand
				break
		if op == "":
			out.append({"key": "invalid", "op": "", "value": t})
			continue
		var at: int = t.find(op)
		out.append({"key": t.substr(0, at).strip_edges(), "op": op,
				"value": t.substr(at + op.length()).strip_edges()})
	return out


## Grammar problems in the whole table (empty = clean). Used by tests.
static func lint() -> Array:
	var errs: Array = []
	for r_raw in all_rows():
		var r: Dictionary = r_raw
		var id: String = String(r["id"])
		if not (String(r["kind"]) in [KIND_INTERVIEW, KIND_OUTING, KIND_INCIDENT, KIND_PRESS]):
			errs.append("%s: unknown kind '%s'" % [id, r["kind"]])
		if (r["choices"] as Array).is_empty():
			errs.append("%s: no choices" % id)
		if (r["effects"] as Array).size() != (r["choices"] as Array).size():
			errs.append("%s: %d choices but %d effects entries" % [
				id, (r["choices"] as Array).size(), (r["effects"] as Array).size()])
		if (r["lines"] as Array).is_empty():
			errs.append("%s: no lines" % id)
		for say_list in (r["says"] as Array):
			for s in (say_list as Array):
				if not (String((s as Dictionary)["branch"]) in ["", "ok", "ng"]):
					errs.append("%s: bad say branch '%s'" % [id, (s as Dictionary)["branch"]])
		for entry in (r["effects"] as Array):
			for c in (entry as Array):
				if String((c as Dictionary)["type"]) == "invalid":
					errs.append("%s: bad clause '%s'" % [id, (c as Dictionary)["raw"]])
		for c in (r["cond"] as Array):
			if not (String((c as Dictionary)["key"]) in COND_KEYS):
				errs.append("%s: bad cond '%s'" % [id, (c as Dictionary)["value"]])
	return errs


# ── Selection ────────────────────────────────────────────────────────────────
## Does `r`'s cond hold for target `pilot_id` (-1 = none)? `mention` tokens are
## resolved by the caller (`mention_target`) and pass here.
static func cond_ok(state: Dictionary, r: Dictionary, pilot_id: int) -> bool:
	for c_raw in (r["cond"] as Array):
		var c: Dictionary = c_raw
		var key: String = String(c["key"])
		var value: String = String(c["value"])
		match key:
			"trust":
				if pilot_id < 0 or not _cmp(MentalSystem.trust(state, pilot_id), String(c["op"]), int(value)):
					return false
			"outings":
				if pilot_id < 0 or not _cmp(MentalSystem.outings(state, pilot_id), String(c["op"]), int(value)):
					return false
			"role":
				var pd: PlayerData = pilot_of(state, pilot_id)
				if pd == null or pd.role != int(value):
					return false
			"week":
				if not _cmp(int(state.get("phase_week", 1)), String(c["op"]), int(value)):
					return false
			"last":
				var last: Dictionary = last_match(state)
				if last.is_empty() or bool(last.get("won", false)) != (value == "win"):
					return false
			"mention":
				pass
			_:
				return false
	return true


## The `mention=<mvp|worst>` token of a row, or "".
static func mention_of(r: Dictionary) -> String:
	for c in (r["cond"] as Array):
		if String((c as Dictionary)["key"]) == "mention":
			return String((c as Dictionary)["value"])
	return ""


## Pilot a press question mentions: `mvp` = last own match MVP if mine,
## `worst` = my pilot with the lowest MVP metric in that match. -1 = none.
static func mention_target(state: Dictionary, mention: String) -> int:
	var last: Dictionary = last_match(state)
	if last.is_empty():
		return -1
	var mine: Array = MentalSystem.my_pilot_ids(state)
	if mention == "mvp":
		var mvp: int = int(last.get("mvp", -1))
		return mvp if mine.has(mvp) else -1
	if mention == "worst":
		var scores: Dictionary = last.get("scores", {})
		var best_pid: int = -1
		var best_score: float = INF
		for pid in mine:
			if not scores.has(str(pid)):
				continue
			var s: float = float(scores[str(pid)])
			if s < best_score:
				best_score = s
				best_pid = int(pid)
		return best_pid
	return -1


## Last own match in `run_stats.matches` (or {}).
static func last_match(state: Dictionary) -> Dictionary:
	var rs: Dictionary = state.get("run_stats", {})
	var ms: Array = rs.get("matches", []) if rs.get("matches", []) is Array else []
	if ms.is_empty():
		return {}
	return ms[ms.size() - 1] if ms[ms.size() - 1] is Dictionary else {}


## Weighted pick among `candidates` with `rng`. Rows written for the run's manager
## type weigh `MENTAL_TYPE_WEIGHT_MULT` times more; rows for the other type never
## appear (callers filter with `type_ok`).
static func weighted_pick(state: Dictionary, candidates: Array, rng: RandomNumberGenerator) -> Dictionary:
	var mtype: int = manager_type(state)
	var mult: int = maxi(1, ConstTable.int_of("MENTAL_TYPE_WEIGHT_MULT"))
	var total: int = 0
	var weights: Array = []
	for r_raw in candidates:
		var r: Dictionary = r_raw
		var w: int = int(r["weight"])
		if int(r["manager_type"]) == mtype and mtype >= 0:
			w *= mult
		weights.append(w)
		total += w
	if total <= 0:
		return {}
	var roll: int = rng.randi_range(1, total)
	for i in candidates.size():
		roll -= int(weights[i])
		if roll <= 0:
			return candidates[i]
	return candidates[candidates.size() - 1]


static func type_ok(state: Dictionary, r: Dictionary) -> bool:
	var t: int = int(r["manager_type"])
	return t < 0 or t == manager_type(state)


static func manager_type(state: Dictionary) -> int:
	return int((state.get("run_setup", {}) as Dictionary).get("manager_type", 0))


# ── Application ──────────────────────────────────────────────────────────────
## Mental-check success chance (percent) for judge stat `judge` (1..20) plus the
## entry's `chk:` adjustments.
static func check_chance(judge: int, adjust: int) -> int:
	var c: int = ConstTable.int_of("MENTAL_CHECK_BASE") \
			+ (judge - ConstTable.int_of("MENTAL_CHECK_PIVOT")) * ConstTable.int_of("MENTAL_CHECK_PER_POINT") \
			+ adjust
	return clampi(c, ConstTable.int_of("MENTAL_CHECK_MIN"), ConstTable.int_of("MENTAL_CHECK_MAX"))


## Apply choice `idx` of row `r` to `state` for target `pilot_id`.
## `judge` = the mental value the check uses, `roll_seed` makes the check deterministic.
## → `{checked, ok, chance, pilot_id, say: [text_key], notes: [note dict]}` — saved as is,
## so **keys / ids only**; `outcome_view` turns it into display text.
## Note dicts: `{type: trust, pid, delta}` · `{type: trust_all, delta}` ·
## `{type: pmod, pid, stat, delta, weeks}` · `{type: pmod_all, stat, delta, weeks}` ·
## `{type: smod, stat, delta, weeks}` · `{type: outing, count}` (added by MentalSystem).
static func apply_choice(state: Dictionary, r: Dictionary, idx: int, pilot_id: int,
		judge: int, roll_seed: int) -> Dictionary:
	var effects: Array = r["effects"]
	var clauses: Array = effects[idx] if idx >= 0 and idx < effects.size() else []
	var all_says: Array = r.get("says", [])
	var says: Array = all_says[idx] if idx >= 0 and idx < all_says.size() else []
	var checked: bool = false
	var adjust: int = 0
	for c in clauses:
		if String((c as Dictionary)["gate"]) != "":
			checked = true
		if String((c as Dictionary)["type"]) == "chk":
			adjust += int((c as Dictionary)["delta"])
	for s in says:
		if String((s as Dictionary)["branch"]) != "":
			checked = true
	var ok: bool = true
	var chance: int = -1
	if checked:
		chance = check_chance(judge, adjust)
		var rng := RandomNumberGenerator.new()
		rng.seed = roll_seed
		ok = rng.randi_range(1, 100) <= chance
	var out: Dictionary = {"checked": checked, "ok": ok, "chance": chance, "pilot_id": pilot_id,
			"say": [], "notes": []}
	for s_raw in says:
		var s: Dictionary = s_raw
		if _gate_passes(String(s["branch"]), ok):
			(out["say"] as Array).append(String(s["key"]))
	for c_raw in clauses:
		var c: Dictionary = c_raw
		if _gate_passes(String(c["gate"]), ok):
			_apply_clause(state, r, c, pilot_id, out)
	return out


static func _gate_passes(gate: String, ok: bool) -> bool:
	return gate == "" or (gate == "ok") == ok


static func _apply_clause(state: Dictionary, r: Dictionary, c: Dictionary,
		pilot_id: int, out: Dictionary) -> void:
	var source: String = "mental:%s" % String(r["id"])
	var notes: Array = out["notes"]
	match String(c["type"]):
		"trust":
			if pilot_id >= 0:
				var d: int = MentalSystem.add_trust(state, pilot_id, int(c["delta"]))
				notes.append({"type": "trust", "pid": pilot_id, "delta": d})
		"trust_all":
			for pid in MentalSystem.my_pilot_ids(state):
				MentalSystem.add_trust(state, int(pid), int(c["delta"]))
			notes.append({"type": "trust_all", "delta": int(c["delta"])})
		"pmod":
			if pilot_id >= 0:
				PilotMods.add(state, pilot_id, String(c["stat"]), int(c["delta"]), int(c["weeks"]), source)
				notes.append({"type": "pmod", "pid": pilot_id, "stat": String(c["stat"]),
						"delta": int(c["delta"]), "weeks": int(c["weeks"])})
		"pmod_all":
			for pid in MentalSystem.my_pilot_ids(state):
				PilotMods.add(state, int(pid), String(c["stat"]), int(c["delta"]), int(c["weeks"]), source)
			notes.append({"type": "pmod_all", "stat": String(c["stat"]),
					"delta": int(c["delta"]), "weeks": int(c["weeks"])})
		"smod":
			StaffSystem.add_mod(state, String(c["stat"]), int(c["delta"]), int(c["weeks"]), source)
			notes.append({"type": "smod", "stat": String(c["stat"]),
					"delta": int(c["delta"]), "weeks": int(c["weeks"])})


# ── Display (outcome / notes → text) ─────────────────────────────────────────
## A stored `apply_choice` outcome → `{checked, ok, chance, say: [String], notes: [String]}`
## for `MessengerView.show_result`. `{name}` = the outcome's target pilot.
static func outcome_view(state: Dictionary, outcome: Dictionary) -> Dictionary:
	var pid: int = int(outcome.get("pilot_id", -1))
	var say: Array = []
	for k in (outcome.get("say", []) as Array):
		say.append(text(state, String(k), pid))
	return {"checked": bool(outcome.get("checked", false)), "ok": bool(outcome.get("ok", false)),
			"chance": int(outcome.get("chance", -1)), "say": say,
			"notes": note_texts(state, outcome.get("notes", []))}


## Note dicts (see `apply_choice`) → player-facing chips.
static func note_texts(state: Dictionary, notes: Array) -> Array:
	var out: Array = []
	for n in notes:
		if n is Dictionary:
			out.append(note_text(state, n))
	return out


static func note_text(state: Dictionary, n: Dictionary) -> String:
	var delta: int = int(n.get("delta", 0))
	var weeks: int = int(n.get("weeks", 0))
	var stat: String = String(n.get("stat", ""))
	match String(n.get("type", "")):
		"trust":
			return "%s 신뢰도 %s" % [pilot_name(state, int(n.get("pid", -1))), _signed(delta)]
		"trust_all":
			return "팀 전체 신뢰도 %s" % _signed(delta)
		"pmod":
			return "%s %s %s (%s)" % [pilot_name(state, int(n.get("pid", -1))),
					stat_label(stat), _signed(delta), duration(weeks)]
		"pmod_all":
			return "팀 전체 %s %s (%s)" % [stat_label(stat), _signed(delta), duration(weeks)]
		"smod":
			return "감독 %s %s (%s)" % [String(StaffSystem.STAT_LABELS.get(stat, "")),
					_signed(delta), duration(weeks)]
		"outing":
			return "외출 %d회째 · 다음 훈련일 EXP 감소" % int(n.get("count", 0))
	return ""


# ── Text helpers ─────────────────────────────────────────────────────────────
## One `mental_texts` key → display text with `{name}` = that pilot (marker kept).
static func text(state: Dictionary, key: String, pilot_id: int) -> String:
	return Loc.t(key, {"name": pilot_name(state, pilot_id)})  # l10n-dynamic: mental.*.*


static func pilot_of(state: Dictionary, pilot_id: int) -> PlayerData:
	if pilot_id < 0:
		return null
	for p in (state.get("all_pilots", []) as Array):
		if p is PlayerData and (p as PlayerData).id == pilot_id:
			return p
	return null


static func pilot_name(state: Dictionary, pilot_id: int) -> String:
	var pd: PlayerData = pilot_of(state, pilot_id)
	return pd.name if pd != null else "선수"


static func stat_label(stat: String) -> String:
	if stat == "all":
		return "전 스탯"
	var i: int = PlayerData.STAT_KEYS.find(stat)
	return PlayerData.stat_label(i) if i >= 0 else stat


static func duration(weeks: int) -> String:
	return "다음 경기까지" if weeks < 0 else "%d주" % weeks


static func _signed(v: int) -> String:
	return "+%d" % v if v >= 0 else "%d" % v


static func _cmp(a: int, op: String, b: int) -> bool:
	match op:
		">=": return a >= b
		"<": return a < b
		"=": return a == b
	return false


static func _to_int(s: String) -> int:
	var t: String = s.strip_edges()
	if t.begins_with("+"):
		t = t.substr(1)
	return int(t)


static func _is_int(s: String) -> bool:
	var t: String = s.strip_edges()
	if t.begins_with("+"):
		t = t.substr(1)
	return t.is_valid_int()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_warning("MentalEvents: cannot open game.db")
		return
	var texts: Dictionary = {}   # event_id → [mental_texts row]
	db.query("SELECT * FROM mental_texts")
	for t in db.query_result:
		var eid: String = String((t as Dictionary).get("event_id", ""))
		if not texts.has(eid):
			texts[eid] = []
		(texts[eid] as Array).append(t)
	db.query("SELECT * FROM mental_events")
	for raw in db.query_result:
		var r: Dictionary = parse_row(raw, texts.get(String((raw as Dictionary).get("id", "")), []))
		_rows.append(r)
		_by_id[String(r["id"])] = r
	db.close_db()
