class_name MechMastery
extends RefCounted

# ── Mech mastery (M4, reworked §15 A) ─────────────────────────────────────────
# Contract: `docs/outgame_dev_plan.md` §11 + §15. Run-scoped state, string keys only
# (JSON round-trips them untouched; numbers come back as floats, so every read
# goes through `int()`):
#   season_state.mech_mastery     = {"<pilot_id>": {"<mech_id>": int 0..MASTERY_MAX}}
#
# Points 0..100 per pilot × mech, shown as a **level 0..5** like trust: level = how
# many thresholds `MASTERY_LV_1..5` the points reached (`level_of`, progress inside
# the level `level_progress`).
#
# Run start (`init_run`): every pilot of the run (league 40 + INTL 20) gets a full row.
# The pilot's rank (`run_rank`: my five = collection rank, named = stars, mobs = 1,
# INTL = `MASTERY_INTL_RANK`) decides how many mechs start at Lv3 / Lv2 / Lv1
# (`MASTERY_RANK<r>_L<l>`), dealt from the front of the pilot's `mech_pref`
# (players.csv / intl_players.csv); a dealt mech starts at its level's threshold,
# everything else at 0 (Lv0).
#
# Effect: while riding that mech the pilot's four stats field_hit · field_eva ·
# engage_hit · engage_eva × (1 + `MASTERY_PCT_<level>` %) — Lv0 is a penalty.
# MatchFlow applies it to roster copies (`apply_to`); BattleSim sees only the level
# (`mech_levels_ctx` → `match_ctx.mech_levels`) for mech upgrades (`MechUpgrades`).
#
# Gains: mech-lab research (§16 — `MechResearch.on_complete`, every pilot of mine on the
# researched mech) and the Saturday story (`gain`, §15 D). Gains for MY
# pilots are multiplied by the knowledge multiplier, `FinanceSystem.mastery_mult` and
# the trait `mastery_pct` inside `gain`; opponent pilots gain the raw amount.
# Matches played give nothing (§15 — the old match gain is gone).
#
# Standalone runs (no active season / empty table) behave as "no mastery":
# `is_enabled` is false, `stat_pct` is 0 and the UI hides mastery.

const LEVEL_MAX: int = 5
## The four stats the level percentage scales (not the two growth stats).
const PCT_STAT_KEYS: Array = ["field_hit", "field_eva", "engage_hit", "engage_eva"]
## Run-start levels dealt from `mech_pref`, highest first.
const START_LEVELS: Array = [3, 2, 1]

static var _mechs: Array = []          # [{id, name, role}] in id order
static var _mech_by_id: Dictionary = {}  # int id → {id, name_key, role}
static var _pref_by_pilot: Dictionary = {}  # int pilot id → Array[int] (players / intl_players `mech_pref`)
static var _loaded: bool = false


# ── Lifecycle ────────────────────────────────────────────────────────────────
## Once at run start (`GameManager.start_run`) — initial mastery for every pilot.
static func init_run(state: Dictionary) -> void:
	var mm: Dictionary = {}
	for pool_key in ["all_pilots", "intl_pilots"]:
		for raw in (state.get(pool_key, []) as Array):
			var pd := raw as PlayerData
			if pd != null:
				mm[str(pd.id)] = initial_row(pd, run_rank(pd, pool_key == "intl_pilots"))
	state["mech_mastery"] = mm


## Rank 1..5 that decides a pilot's run-start mastery: my five = collection rank and
## named AI = stars (both already on `PlayerData.rank`, `RunRules.apply_progress`),
## mobs = 1, INTL pilots (no stars) = `MASTERY_INTL_RANK`.
static func run_rank(pd: PlayerData, intl: bool = false) -> int:
	if intl:
		return clampi(ConstTable.int_of("MASTERY_INTL_RANK"), 1, LEVEL_MAX)
	if pd.is_mob:
		return 1
	var r: int = pd.rank if pd.rank > 0 else pd.rarity
	return clampi(r, 1, LEVEL_MAX)


## Initial `{"<mech_id>": int}` row for one pilot of `rank`: `MASTERY_RANK<r>_L3`
## mechs at the Lv3 threshold, then L2, then L1, from the front of `mech_pref`.
static func initial_row(pd: PlayerData, rank: int) -> Dictionary:
	var row: Dictionary = {}
	for e in all_mechs():
		row[str(int(e["id"]))] = 0
	var pref: Array = mech_pref(pd)
	var i: int = 0
	for lv in START_LEVELS:
		var n: int = ConstTable.int_of("MASTERY_RANK%d_L%d" % [clampi(rank, 1, LEVEL_MAX), lv])
		for _k in n:
			if i >= pref.size():
				break
			row[str(int(pref[i]))] = threshold(lv)
			i += 1
	return row


## The pilot's mech preference, best first (`mech_pref`). Falls back to main mechs →
## own-role mechs when the column is empty.
static func mech_pref(pd: PlayerData) -> Array:
	_ensure_loaded()
	var out: Array = (_pref_by_pilot.get(pd.id, []) as Array).duplicate()
	if not out.is_empty():
		return out
	for m in pd.main_mechs:
		out.append(int(m))
	for e in mechs_of_role(pd.role):
		if not out.has(int(e["id"])):
			out.append(int(e["id"]))
	return out


## True when this state carries a mastery table (an active run). False for a
## standalone MatchFlow / BattleSim — callers then skip mastery entirely.
static func is_enabled(state: Dictionary) -> bool:
	return bool(state.get("active", false)) \
			and not (state.get("mech_mastery", {}) as Dictionary).is_empty()


# ── Reading ──────────────────────────────────────────────────────────────────
static func max_value() -> int:
	return ConstTable.int_of("MASTERY_MAX")


## Mastery points 0..MASTERY_MAX. 0 when the pilot / mech has no entry.
static func value(state: Dictionary, pilot_id: int, mech_id: int) -> int:
	var row: Dictionary = (state.get("mech_mastery", {}) as Dictionary).get(str(pilot_id), {})
	return int(row.get(str(mech_id), 0))


## Points needed for level `l` (0 for Lv0).
static func threshold(l: int) -> int:
	if l <= 0:
		return 0
	return ConstTable.int_of("MASTERY_LV_%d" % clampi(l, 1, LEVEL_MAX))


## Level 0..5 of a points value.
static func level_for_value(v: int) -> int:
	var l: int = 0
	for i in range(1, LEVEL_MAX + 1):
		if v >= threshold(i):
			l = i
	return l


static func level_of(state: Dictionary, pilot_id: int, mech_id: int) -> int:
	return level_for_value(value(state, pilot_id, mech_id))


## Progress 0..1 inside the current level (1.0 at Lv5) — like `MentalSystem.trust_progress`.
static func value_progress(v: int) -> float:
	var l: int = level_for_value(v)
	if l >= LEVEL_MAX:
		return 1.0
	var lo: int = threshold(l)
	var hi: int = threshold(l + 1)
	if hi <= lo:
		return 1.0
	return clampf(float(v - lo) / float(hi - lo), 0.0, 1.0)


static func level_progress(state: Dictionary, pilot_id: int, mech_id: int) -> float:
	return value_progress(value(state, pilot_id, mech_id))


## Stat multiplier delta of a level (−0.2 for Lv0 … +0.2 for Lv5).
static func pct_for_level(l: int) -> float:
	return ConstTable.num("MASTERY_PCT_%d" % clampi(l, 0, LEVEL_MAX)) / 100.0


## "+10%" / "±0%" / "-20%" — the level's stat percentage as a short label.
static func pct_text(l: int) -> String:
	var p: int = roundi(pct_for_level(l) * 100.0)
	if p == 0:
		return "±0%"
	return ("+%d%%" % p) if p > 0 else ("%d%%" % p)


## "Lv3".
static func level_name(l: int) -> String:
	return Loc.t(L.MASTERY_LEVEL, {"n": clampi(l, 0, LEVEL_MAX)})


## Colour of a level on the white outgame theme.
static func level_color(l: int) -> Color:
	if l <= 0:
		return OutgameTheme.NEGATIVE
	if l <= 2:
		return OutgameTheme.TEXT_SUB
	if l < LEVEL_MAX:
		return OutgameTheme.POSITIVE
	return OutgameTheme.ACCENT_TEXT


## Stat percentage (as a fraction) while riding that mech — 0 when mastery is off / no mech.
static func stat_pct(state: Dictionary, pilot_id: int, mech_id: int) -> float:
	if mech_id < 0 or not is_enabled(state):
		return 0.0
	return pct_for_level(level_of(state, pilot_id, mech_id))


## Applies `stat_pct` to `pd`'s four combat stats (its `assigned_mech`). **Call on a
## copy only.** Floor is `PlayerData.STAT_MIN`, like `PilotMods.apply_to`.
static func apply_to(state: Dictionary, pd: PlayerData) -> void:
	if pd == null or pd.assigned_mech == null:
		return
	var pct: float = stat_pct(state, pd.id, pd.assigned_mech.id)
	if is_zero_approx(pct):
		return
	for k in PCT_STAT_KEYS:
		pd.set(k, maxi(PlayerData.STAT_MIN, roundi(float(int(pd.get(k))) * (1.0 + pct))))


## `match_ctx.mech_levels` — `{"<pilot_id>": level}` of every pilot in `rosters`
## (an Array of rosters, or one flat roster) on its assigned mech. {} when mastery is off.
static func mech_levels_ctx(state: Dictionary, rosters: Array) -> Dictionary:
	var out: Dictionary = {}
	if not is_enabled(state):
		return out
	var flat: Array = []
	for r in rosters:
		if r is Array:
			flat.append_array(r as Array)
		else:
			flat.append(r)
	for raw in flat:
		var pd := raw as PlayerData
		if pd == null or pd.assigned_mech == null:
			continue
		out[str(pd.id)] = level_of(state, pd.id, pd.assigned_mech.id)
	return out


## Top mastery mechs `[{mech_id, value}]`, highest first (ties: lower id), at most n.
static func top_mechs(state: Dictionary, pilot_id: int, n: int = 3) -> Array:
	var row: Dictionary = (state.get("mech_mastery", {}) as Dictionary).get(str(pilot_id), {})
	var out: Array = []
	for k in row.keys():
		out.append({"mech_id": int(k), "value": int(row[k])})
	out.sort_custom(func(a, b):
		if int(a["value"]) != int(b["value"]):
			return int(a["value"]) > int(b["value"])
		return int(a["mech_id"]) < int(b["mech_id"]))
	return out.slice(0, maxi(0, n))


# ── Gains ────────────────────────────────────────────────────────────────────
## Knowledge multiplier = MASTERY_KNOW_BASE + MASTERY_KNOW_PER × effective knowledge.
static func knowledge_mult(state: Dictionary) -> float:
	return maxf(0.0, ConstTable.num("MASTERY_KNOW_BASE")
			+ ConstTable.num("MASTERY_KNOW_PER") * float(StaffSystem.effective(state, "knowledge")))


## Total gain multiplier for a pilot — knowledge × facility × trait `mastery_pct`
## (M8, `TraitSystem.run_pct_mult`) for MY pilots, 1.0 otherwise.
static func gain_mult(state: Dictionary, pilot_id: int) -> float:
	if not is_my_pilot(state, pilot_id):
		return 1.0
	return knowledge_mult(state) * FinanceSystem.mastery_mult(state) \
			* TraitSystem.run_pct_mult(state, "mastery_pct")


## What `gain(state, pilot_id, _, amount)` would actually add (before the cap).
static func gain_preview(state: Dictionary, pilot_id: int, amount: int) -> int:
	if amount <= 0:
		return 0
	return maxi(1, roundi(float(amount) * gain_mult(state, pilot_id)))


## Raises mastery by `amount` (raw value — multipliers are applied here).
static func gain(state: Dictionary, pilot_id: int, mech_id: int, amount: int) -> void:
	if amount <= 0 or mech_id < 0:
		return
	var mm: Dictionary = state.get("mech_mastery", {})
	var key: String = str(pilot_id)
	if not mm.has(key):
		return
	var row: Dictionary = mm[key]
	var add: int = gain_preview(state, pilot_id, amount)
	row[str(mech_id)] = clampi(int(row.get(str(mech_id), 0)) + add, 0, max_value())


## The pilot's own-role mech with the highest mastery still below the cap (ties: lower
## id); -1 if nothing can grow. Fallback mech for gains without an explicit mech
## (story `mastery:` clause, `FocusTraining.story_mech`) and the lab body's default chip.
static func growth_mech(state: Dictionary, pd: PlayerData) -> int:
	if pd == null:
		return -1
	var best: int = -1
	var best_v: int = -1
	for e in mechs_of_role(pd.role):
		var mid: int = int(e["id"])
		var v: int = value(state, pd.id, mid)
		if v < max_value() and v > best_v:
			best = mid
			best_v = v
	return best


# ── Pilots ───────────────────────────────────────────────────────────────────
## My five pilots in `GameEnums.ROLE_DISPLAY_ORDER`.
static func my_pilots(state: Dictionary) -> Array:
	var tid: int = int(state.get("player_team_id", 0))
	var out: Array = []
	for raw in (state.get("all_pilots", []) as Array):
		var pd := raw as PlayerData
		if pd != null and pd.team_id == tid:
			out.append(pd)
	out.sort_custom(func(a, b):
		return GameEnums.role_seat((a as PlayerData).role) < GameEnums.role_seat((b as PlayerData).role))
	return out


static func is_my_pilot(state: Dictionary, pilot_id: int) -> bool:
	var pd: PlayerData = find_pilot(state, pilot_id)
	return pd != null and pd.team_id == int(state.get("player_team_id", 0)) and pd.team_id < 100


## League or INTL pilot by id (null if unknown).
static func find_pilot(state: Dictionary, pilot_id: int) -> PlayerData:
	for pool_key in ["all_pilots", "intl_pilots"]:
		for raw in (state.get(pool_key, []) as Array):
			var pd := raw as PlayerData
			if pd != null and pd.id == pilot_id:
				return pd
	return null


# ── Mech table ───────────────────────────────────────────────────────────────
## `[{id, name_key, role}]` from game.db `mechs`, id order (`mech_name` for display).
static func all_mechs() -> Array:
	_ensure_loaded()
	return _mechs


static func mechs_of_role(role: int) -> Array:
	var out: Array = []
	for e in all_mechs():
		if int((e as Dictionary)["role"]) == role:
			out.append(e)
	return out


static func mech_name(mech_id: int) -> String:
	_ensure_loaded()
	var key: String = String((_mech_by_id.get(mech_id, {}) as Dictionary).get("name_key", ""))
	return "—" if key.is_empty() else Loc.t(key)  # l10n-dynamic: name.mech.*


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_warning("MechMastery: cannot open game.db")
		return
	db.query("SELECT id, name_key, role FROM mechs ORDER BY id")
	for row in db.query_result:
		var e: Dictionary = {"id": int(row["id"]), "name_key": String(row["name_key"]), "role": int(row["role"])}
		_mechs.append(e)
		_mech_by_id[int(row["id"])] = e
	# `mech_pref` — "12|13|14…", best first (league ids and INTL ids do not overlap).
	for table in ["players", "intl_players"]:
		db.query("SELECT id, mech_pref FROM %s" % table)
		for row in db.query_result:
			var ids: Array = []
			for part in String(row.get("mech_pref", "")).split("|", false):
				if String(part).strip_edges().is_valid_int():
					ids.append(int(String(part).strip_edges()))
			_pref_by_pilot[int(row["id"])] = ids
	db.close_db()
