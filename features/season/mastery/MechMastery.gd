class_name MechMastery
extends RefCounted

# ── Mech mastery (M4) ─────────────────────────────────────────────────────────
# Contract: `docs/outgame_dev_plan.md` §11. Run-scoped state, string keys only
# (JSON round-trips them untouched; numbers come back as floats, so every read
# goes through `int()`):
#   season_state.mech_mastery     = {"<pilot_id>": {"<mech_id>": int 0..MASTERY_MAX}}
#   season_state.mastery_research = {"<pilot_id>": mech_id}   (weekly research mech)
#
# Every pilot of the run (league 40 + INTL 20) gets a full row of all mechs at
# `init_run`: main mechs (`PlayerData.main_mechs`) start at MASTERY_INIT_MAIN,
# other mechs of the pilot's own role at MASTERY_INIT_ROLE, the rest at
# MASTERY_INIT_OTHER.
#
# Effect: value → tier 0..3 (미숙 / 보통 / 능숙 / 마스터, thresholds
# MASTERY_TIER_1..3) → a flat bonus MASTERY_BONUS_<tier> added to **each** of the
# six pilot stats while riding that mech. MatchFlow applies it to roster copies
# (`stat_bonus`); BattleSim never sees mastery.
#
# Gains: match played with the mech (`record_match`, both teams of MY matches),
# weekly research mech (`settle_week`), mastery training tile
# (`add_training_exp` → research mech). Gains for MY pilots are multiplied by the
# knowledge multiplier and `FinanceSystem.mastery_mult` inside `gain`; opponent
# pilots gain the raw amount (my staff does not coach them).
#
# Standalone runs (no active season / empty table) behave as "no mastery":
# `is_enabled` is false, `stat_bonus` is 0 and the UI hides mastery.

const TIER_NAMES: Array = [  # l10n-keys: mastery.tier.*
	L.MASTERY_TIER_NOVICE, L.MASTERY_TIER_AVERAGE, L.MASTERY_TIER_SKILLED, L.MASTERY_TIER_MASTER,
]
const TIER_COUNT: int = 4

static var _mechs: Array = []          # [{id, name, role}] in id order
static var _mech_by_id: Dictionary = {}  # int id → {id, name_key, role}
static var _loaded: bool = false


# ── Lifecycle ────────────────────────────────────────────────────────────────
## Once at run start (`GameManager.start_run`) — initial mastery for every pilot.
static func init_run(state: Dictionary) -> void:
	var mm: Dictionary = {}
	for pool_key in ["all_pilots", "intl_pilots"]:
		for raw in (state.get(pool_key, []) as Array):
			var pd := raw as PlayerData
			if pd != null:
				mm[str(pd.id)] = initial_row(pd)
	state["mech_mastery"] = mm
	state["mastery_research"] = {}


## Initial `{"<mech_id>": int}` row for one pilot.
static func initial_row(pd: PlayerData) -> Dictionary:
	var mains: Array = []
	for m in pd.main_mechs:
		mains.append(int(m))
	var row: Dictionary = {}
	for e in all_mechs():
		var mid: int = int(e["id"])
		var v: int = ConstTable.int_of("MASTERY_INIT_OTHER")
		if mains.has(mid):
			v = ConstTable.int_of("MASTERY_INIT_MAIN")
		elif int(e["role"]) == pd.role:
			v = ConstTable.int_of("MASTERY_INIT_ROLE")
		row[str(mid)] = clampi(v, 0, max_value())
	return row


## True when this state carries a mastery table (an active run). False for a
## standalone MatchFlow / BattleSim — callers then skip mastery entirely.
static func is_enabled(state: Dictionary) -> bool:
	return bool(state.get("active", false)) \
			and not (state.get("mech_mastery", {}) as Dictionary).is_empty()


# ── Reading ──────────────────────────────────────────────────────────────────
static func max_value() -> int:
	return ConstTable.int_of("MASTERY_MAX")


## Mastery 0..MASTERY_MAX. 0 when the pilot / mech has no entry.
static func value(state: Dictionary, pilot_id: int, mech_id: int) -> int:
	var row: Dictionary = (state.get("mech_mastery", {}) as Dictionary).get(str(pilot_id), {})
	return int(row.get(str(mech_id), 0))


## Tier 0..3 (미숙 / 보통 / 능숙 / 마스터).
static func tier_of(v: int) -> int:
	var t: int = 0
	for i in range(1, TIER_COUNT):
		if v >= ConstTable.int_of("MASTERY_TIER_%d" % i):
			t = i
	return t


static func tier_name(t: int) -> String:
	return Loc.t(String(TIER_NAMES[clampi(t, 0, TIER_COUNT - 1)]))  # l10n-dynamic: mastery.tier.*


## Flat per-stat bonus of a tier (negative for 미숙).
static func bonus_for_tier(t: int) -> int:
	return ConstTable.int_of("MASTERY_BONUS_%d" % clampi(t, 0, TIER_COUNT - 1))


## "+2" / "±0" / "-3" — the tier bonus as a short label.
static func bonus_text(t: int) -> String:
	var b: int = bonus_for_tier(t)
	if b == 0:
		return "±0"
	return ("+%d" % b) if b > 0 else str(b)


## Colour of a tier on the white outgame theme.
static func tier_color(t: int) -> Color:
	match clampi(t, 0, TIER_COUNT - 1):
		0: return OutgameTheme.NEGATIVE
		1: return OutgameTheme.TEXT_SUB
		2: return OutgameTheme.POSITIVE
	return OutgameTheme.ACCENT_TEXT


## Flat bonus added to **each** of the six stats while riding that mech
## (0 when mastery is disabled or no mech).
static func stat_bonus(state: Dictionary, pilot_id: int, mech_id: int) -> int:
	if mech_id < 0 or not is_enabled(state):
		return 0
	return bonus_for_tier(tier_of(value(state, pilot_id, mech_id)))


## Applies `stat_bonus` to `pd` (its `assigned_mech`). **Call on a copy only.**
## Floor is `PlayerData.STAT_MIN`, like `PilotMods.apply_to`.
static func apply_to(state: Dictionary, pd: PlayerData) -> void:
	if pd == null or pd.assigned_mech == null:
		return
	var b: int = stat_bonus(state, pd.id, pd.assigned_mech.id)
	if b == 0:
		return
	for k in PlayerData.STAT_KEYS:
		pd.set(k, maxi(PlayerData.STAT_MIN, int(pd.get(k)) + b))


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


## That pilot's weekly research mech (-1 = none).
static func research_mech(state: Dictionary, pilot_id: int) -> int:
	return int((state.get("mastery_research", {}) as Dictionary).get(str(pilot_id), -1))


## Sets (mech_id >= 0) or clears (-1) the research mech.
static func set_research(state: Dictionary, pilot_id: int, mech_id: int) -> void:
	var r: Dictionary = state.get("mastery_research", {})
	if mech_id < 0:
		r.erase(str(pilot_id))
	else:
		r[str(pilot_id)] = mech_id
	state["mastery_research"] = r


## Coach's rule (plain, not optimal): the pilot's own-role mech with the highest
## mastery still below the master threshold; if all are master, the highest one
## below the cap. -1 if nothing can grow.
static func auto_research_mech(state: Dictionary, pd: PlayerData) -> int:
	if pd == null:
		return -1
	var master_at: int = ConstTable.int_of("MASTERY_TIER_%d" % (TIER_COUNT - 1))
	var best: int = -1
	var best_v: int = -1
	var fallback: int = -1
	var fallback_v: int = -1
	for e in mechs_of_role(pd.role):
		var mid: int = int(e["id"])
		var v: int = value(state, pd.id, mid)
		if v < master_at and v > best_v:
			best = mid
			best_v = v
		if v < max_value() and v > fallback_v:
			fallback = mid
			fallback_v = v
	return best if best >= 0 else fallback


## "코치에게 맡기기" — every one of my pilots gets the coach's research mech.
static func auto_assign_all(state: Dictionary) -> void:
	for pd in my_pilots(state):
		set_research(state, pd.id, auto_research_mech(state, pd))


## How many of my pilots have no research mech.
static func missing_research_count(state: Dictionary) -> int:
	var n: int = 0
	for pd in my_pilots(state):
		if research_mech(state, pd.id) < 0:
			n += 1
	return n


## Mastery tile EXP from the training board (`TrainingBoard.apply_day_training`)
## — goes to the research mech; with none set, to the coach's choice so a tile
## placed before choosing is not wasted.
static func add_training_exp(state: Dictionary, pilot_id: int, amount: int) -> void:
	if amount <= 0 or not is_enabled(state):
		return
	var mech: int = research_mech(state, pilot_id)
	if mech < 0:
		mech = auto_research_mech(state, find_pilot(state, pilot_id))
	gain(state, pilot_id, mech, roundi(float(amount) * ConstTable.num("MASTERY_TRAIN_SCALE")))


## Once per finished match of mine (`SeasonHub._consume_pending_match_result`).
## `pending_match.assigned_mechs` = `{"<pilot_id>": mech_id}` for both teams
## (written by MatchFlow). Guarded by `mastery_recorded` against double counting.
static func record_match(state: Dictionary, pending_match: Dictionary) -> void:
	if pending_match.is_empty() or bool(pending_match.get("mastery_recorded", false)):
		return
	if not is_enabled(state):
		return
	var am: Dictionary = pending_match.get("assigned_mechs", {})
	var amount: int = ConstTable.int_of("MASTERY_GAIN_MATCH")
	for k in am.keys():
		gain(state, int(k), int(am[k]), amount)
	pending_match["mastery_recorded"] = true


## Week close (`SeasonHub._end_week`) — research gain for my pilots. When the
## knowledge area is delegated, the coach fills empty research slots first.
static func settle_week(state: Dictionary) -> void:
	if not is_enabled(state):
		return
	var delegated: bool = StaffSystem.is_delegated(state, "knowledge")
	var amount: int = ConstTable.int_of("MASTERY_GAIN_RESEARCH")
	for pd in my_pilots(state):
		var mech: int = research_mech(state, pd.id)
		if mech < 0 and delegated:
			mech = auto_research_mech(state, pd)
			set_research(state, pd.id, mech)
		if mech >= 0:
			gain(state, pd.id, mech, amount)
			_research_quirk_roll(state, pd.id)


## Research also turns up quirks (§14, T1): `QUIRK_RESEARCH_CHANCE`% per pilot
## with a research mech → `QuirkSystem.gain_random` (a full pilot gets nothing).
## Seeded per run · week · pilot, so reloading the week close never rerolls.
static func _research_quirk_roll(state: Dictionary, pilot_id: int) -> void:
	if not QuirkSystem.is_enabled(state):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(state.get("run_seed", 0)), int(state.get("current_phase", 0)),
			int(state.get("phase_week", 1)), pilot_id, "quirk_research"])
	if rng.randi_range(1, 100) <= ConstTable.int_of("QUIRK_RESEARCH_CHANCE"):
		QuirkSystem.gain_random(state, pilot_id)


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
	db.close_db()
