class_name TraitSystem
extends RefCounted

# ── Manager traits (M8) — the single entry point ─────────────────────────────
# Contract: `docs/outgame_dev_plan.md` §12. Table: `traits.csv` (cached on first read).
#
# - **Bonus points** = Σ(bonus_cost of "-" traits) − Σ(bonus_cost of "+" traits).
#   A set with bonus < 0, more than `TRAIT_SLOTS` traits, duplicates or traits the
#   profile does not own is not equippable (`validate_equip`).
# - Inside a run the equipped set is frozen in `season_state.run_setup.traits`
#   (Array[int]) and `.bonus_points`. Season systems read effects with
#   `run_mod(state, key)` — the **sum of p1** of every equipped trait with that key
#   (0 when none, so callers multiply / add unconditionally).
# - In-game traits reach BattleSim as `match_ctx.traits = [{key, p1, p2}]`
#   (`ingame_traits(state)`), consumed by `features/battle_sim/trait/TraitHooks.gd`.
# - Unlock conditions (`unlock` column) are judged at settlement by
#   `evaluate_unlocks` — grammar in `features/meta/traits/README.md`.

const POLARITY_POS: String = "+"
const POLARITY_NEG: String = "-"
const LAYER_OUTGAME: String = "outgame"
const LAYER_INGAME: String = "ingame"

const RARITY_NAMES: Array = ["일반", "고급", "희귀", "영웅", "전설"]

static var _rows: Array = []            # Array[Dictionary], id order
static var _by_id: Dictionary = {}      # int id → row
static var _loaded: bool = false


# ── Table ────────────────────────────────────────────────────────────────────
## `[{id, key, name, rarity, polarity, bonus_cost, layer, p1, p2, unlock,
##   default_owned: bool, craft_cost, desc}]`, id order.
static func rows() -> Array:
	_ensure_loaded()
	return _rows


static func row(trait_id: int) -> Dictionary:
	_ensure_loaded()
	return _by_id.get(trait_id, {})


static func default_owned_ids() -> Array:
	var out: Array = []
	for r in rows():
		if bool((r as Dictionary)["default_owned"]):
			out.append(int((r as Dictionary)["id"]))
	return out


static func is_positive(trait_id: int) -> bool:
	return String(row(trait_id).get("polarity", POLARITY_POS)) == POLARITY_POS


## Description with `{p1}` / `{p2}` filled in (signed numbers keep their sign).
static func desc_of(trait_id: int) -> String:
	var r: Dictionary = row(trait_id)
	return String(r.get("desc", "")) \
			.replace("{p1}", str(int(r.get("p1", 0)))) \
			.replace("{p2}", str(int(r.get("p2", 0))))


static func rarity_name(rarity: int) -> String:
	return String(RARITY_NAMES[clampi(rarity, 0, RARITY_NAMES.size() - 1)])


static func slot_count() -> int:
	return maxi(1, ConstTable.int_of("TRAIT_SLOTS"))


# ── Bonus points / validation ────────────────────────────────────────────────
## Σ provided by "-" traits − Σ consumed by "+" traits. Unknown ids count 0.
static func bonus_points(trait_ids: Array) -> int:
	var total: int = 0
	for raw in trait_ids:
		var r: Dictionary = row(int(raw))
		if r.is_empty():
			continue
		var c: int = int(r["bonus_cost"])
		total += -c if String(r["polarity"]) == POLARITY_POS else c
	return total


## "" when `trait_ids` can be equipped with `owned` (Array[int] of owned trait ids).
static func validate_equip(trait_ids: Array, owned: Array) -> String:
	if trait_ids.size() > slot_count():
		return "특성은 %d개까지 장착할 수 있습니다" % slot_count()
	var seen: Dictionary = {}
	for raw in trait_ids:
		var tid: int = int(raw)
		if row(tid).is_empty():
			return "알 수 없는 특성 id %d" % tid
		if seen.has(tid):
			return "같은 특성을 두 번 장착할 수 없습니다"
		seen[tid] = true
		if not owned.has(tid):
			return "보유하지 않은 특성입니다: %s" % String(row(tid)["name"])
	var bonus: int = bonus_points(trait_ids)
	if bonus < 0:
		return "보너스 점수가 부족합니다 (%d)" % bonus
	return ""


# ── Run-time reads ───────────────────────────────────────────────────────────
## Equipped trait ids of the current run (`run_setup.traits`).
static func run_traits(state: Dictionary) -> Array:
	var out: Array = []
	for raw in ((state.get("run_setup", {}) as Dictionary).get("traits", []) as Array):
		out.append(int(raw))
	return out


## Sum of p1 over equipped traits with `key` (0 when none). Effect keys: §12.
static func run_mod(state: Dictionary, key: String) -> int:
	return sum_p1(run_traits(state), key)


## Sum of p1 over `trait_ids` with `key` — for screens before a run exists
## (run setup cap preview, preset editor).
static func sum_p1(trait_ids: Array, key: String) -> int:
	var total: int = 0
	for tid in trait_ids:
		var r: Dictionary = row(int(tid))
		if String(r.get("key", "")) == key:
			total += int(r.get("p1", 0))
	return total


## `run_mod` as a percentage multiplier: `1 + Σp1 / 100`, floored at 0.
static func run_pct_mult(state: Dictionary, key: String) -> float:
	return maxf(0.0, 1.0 + float(run_mod(state, key)) / 100.0)


## `match_ctx.traits` payload — in-game traits of the run: `[{id, key, p1, p2}]`.
static func ingame_traits(state: Dictionary) -> Array:
	var out: Array = []
	for tid in run_traits(state):
		var r: Dictionary = row(tid)
		if String(r.get("layer", "")) != LAYER_INGAME:
			continue
		out.append({"id": tid, "key": String(r["key"]), "p1": int(r["p1"]), "p2": int(r["p2"])})
	return out


# ── Unlocks (grammar: features/meta/traits/README.md) ─────────────────────
## Trait ids whose `unlock` condition this run met and that the profile does not own
## yet. Called by `RunResult.build_result` (pure — no profile writes). `profile` is the
## ProfileManager dictionary (may be empty for test runs → judge run-only conditions).
static func evaluate_unlocks(state: Dictionary, result: Dictionary, profile: Dictionary) -> Array:
	var owned: Array = []
	var ptr: Variant = profile.get("traits", {})
	if typeof(ptr) == TYPE_DICTIONARY:
		for raw in ((ptr as Dictionary).get("owned", []) as Array):
			owned.append(int(raw))
	var out: Array = []
	for r in rows():
		var tid: int = int((r as Dictionary)["id"])
		var cond: String = String((r as Dictionary)["unlock"]).strip_edges()
		if cond == "" or owned.has(tid):
			continue
		if unlock_met(cond, state, result, profile):
			out.append(tid)
	return out


## One `unlock` condition (grammar: `features/meta/traits/README.md`). Unknown
## condition → warning, not met.
static func unlock_met(cond: String, state: Dictionary, result: Dictionary, profile: Dictionary) -> bool:
	var head: String = cond
	var arg: String = ""
	var colon: int = cond.find(":")
	if colon >= 0:
		head = cond.substr(0, colon).strip_edges()
		arg = cond.substr(colon + 1).strip_edges()
	var n: int = int(arg) if arg.is_valid_int() else 0
	var cleared_phase: bool = int(result.get("phases_cleared", 0)) >= 1
	match head:
		"clear":
			return String(result.get("outcome", "")) == "clear"
		"wins":
			return int(result.get("wins", 0)) >= n
		"titles":
			return int(result.get("titles", 0)) >= n
		"phase":
			return int(result.get("phases_cleared", 0)) >= n
		"win_streak":
			return longest_win_streak(state) >= n
		"outings":
			return max_outings(state) >= n
		"mvp":
			var total: int = 0
			var mvp: Variant = result.get("mvp", {})
			if typeof(mvp) == TYPE_DICTIONARY:
				for k in (mvp as Dictionary).keys():
					total += int((mvp as Dictionary)[k])
			return total >= n
		"finance_manual_profit":
			return FinanceSystem.manual_profit_weeks(state) >= n
		"true_ending":
			return not (result.get("true_endings", []) as Array).is_empty()
		"runs":
			var runs: Variant = profile.get("runs", [])
			var past: int = (runs as Array).size() if typeof(runs) == TYPE_ARRAY else 0
			return past + 1 >= n
		"team":
			return arg.is_valid_int() and int(result.get("team_id", -1)) == n and cleared_phase
		"bonus":
			return int(result.get("bonus_points", 0)) >= n and cleared_phase
	push_warning("TraitSystem: unknown unlock condition '%s'" % cond)
	return false


## Longest run of consecutive `won` entries in `run_stats.matches` (my matches, in order).
static func longest_win_streak(state: Dictionary) -> int:
	var best: int = 0
	var cur: int = 0
	var rs: Variant = state.get("run_stats", {})
	if typeof(rs) != TYPE_DICTIONARY:
		return 0
	for raw in ((rs as Dictionary).get("matches", []) as Array):
		if typeof(raw) == TYPE_DICTIONARY and bool((raw as Dictionary).get("won", false)):
			cur += 1
			best = maxi(best, cur)
		else:
			cur = 0
	return best


## Most outings any of my pilots went on this run (`MentalSystem.outings`).
static func max_outings(state: Dictionary) -> int:
	var best: int = 0
	for pid in MentalSystem.my_pilot_ids(state):
		best = maxi(best, MentalSystem.outings(state, int(pid)))
	return best


# ── Loading ──────────────────────────────────────────────────────────────────
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_warning("TraitSystem: cannot open game.db")
		return
	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='traits'")
	if db.query_result.is_empty():
		db.close_db()
		return
	db.query("SELECT * FROM traits ORDER BY id")
	for r in db.query_result:
		var e: Dictionary = {
			"id": int(r["id"]), "key": String(r["key"]), "name": String(r["name"]),
			"rarity": int(r["rarity"]), "polarity": String(r["polarity"]),
			"bonus_cost": int(r["bonus_cost"]), "layer": String(r["layer"]),
			"p1": int(r["p1"]), "p2": int(r["p2"]), "unlock": String(r["unlock"]),
			"default_owned": int(r["default_owned"]) == 1,
			"craft_cost": int(r["craft_cost"]), "desc": String(r["desc"]),
		}
		_rows.append(e)
		_by_id[int(e["id"])] = e
	db.close_db()
