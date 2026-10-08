class_name QuirkSystem
extends RefCounted

# ── Quirks (기벽) — run-only pilot passives (§14, T1) ─────────────────────────
# Contract: `docs/outgame_dev_plan.md` §14. Run-scoped state, string keys only:
#   season_state.quirks = {"<pilot_id>": {"slots": int, "ids": [quirk_id]}}  (MY 5 pilots only)
# JSON round-trips turn the numbers into floats, so every read goes through `int()`.
# Positive stat bonuses only. MatchFlow adds them to roster copies (`apply_to`),
# like mech mastery — BattleSim never reads quirks.
#
# Table `quirks` (game.db, `data/csv/quirks.csv`): `stats` / `cond_stats` are
# `stat:n|stat:n` with `PlayerData.STAT_KEYS`; `cond` grammar is in the README
# (`main` · `own_role` · `mech_role:<n>` · `tier:<n>`, `&` = and).
#
# Rolls (gain / reroll) pick a **grade** first — weights `QUIRK_GRADE_W_<g>` plus
# `QUIRK_KNOW_W_<g>` × effective knowledge (`StaffSystem.effective`) — then a quirk
# of that grade by its `weight`, never one the pilot already has. The RNG is
# seeded from `run_seed` · week · weekday · pilot · purpose · current quirks, so a
# reload replays the same roll.

const GRADE_COUNT: int = 3
## Grade → shared rarity tier (`GameEnums.rarity_label`): 일반 · 희귀 · 영웅 = tiers 0 · 2 · 3.
const GRADE_TIERS: Array = [0, 2, 3]
## Grade colours on the white outgame theme (grey / blue / purple).
const GRADE_COLORS: Array = [
	Color(0.47, 0.49, 0.53),
	Color(0.18, 0.45, 0.88),
	Color(0.58, 0.30, 0.86),
]

static var _rows: Dictionary = {}     # int id → row
static var _ids_by_grade: Array = []  # grade → [id] in id order
static var _loaded: bool = false


## Once at run start (`GameManager.start_run`) — every pilot of mine: 0 quirks,
## `QUIRK_SLOTS_START` slots.
static func init_run(state: Dictionary) -> void:
	var q: Dictionary = {}
	var start: int = clampi(ConstTable.int_of("QUIRK_SLOTS_START"), 0, max_slots())
	for pd in MechMastery.my_pilots(state):
		q[str((pd as PlayerData).id)] = {"slots": start, "ids": []}
	state["quirks"] = q


## False outside a run / before `init_run` → no bonus, UI hidden.
static func is_enabled(state: Dictionary) -> bool:
	return bool(state.get("active", false)) \
			and not (state.get("quirks", {}) as Dictionary).is_empty()


## Equipped quirk ids of a pilot (empty for opponents).
static func quirks_of(state: Dictionary, pilot_id: int) -> Array:
	var e: Dictionary = _entry(state, pilot_id)
	var out: Array = []
	for v in (e.get("ids", []) as Array):
		out.append(int(v))
	return out


## Current slot count (QUIRK_SLOTS_START..QUIRK_SLOTS_MAX).
static func slots_of(state: Dictionary, pilot_id: int) -> int:
	return int(_entry(state, pilot_id).get("slots", 0))


static func max_slots() -> int:
	return ConstTable.int_of("QUIRK_SLOTS_MAX")


## Rolls a random quirk (grade weighted by effective knowledge) into an empty slot.
## Returns `{result: "gain"|"full"|"none", id}`; "full" = no empty slot (nothing changes).
static func gain_random(state: Dictionary, pilot_id: int) -> Dictionary:
	if not is_enabled(state) or not _has_entry(state, pilot_id):
		return {"result": "none", "id": -1}
	var ids: Array = quirks_of(state, pilot_id)
	if ids.size() >= slots_of(state, pilot_id):
		return {"result": "full", "id": -1}
	var rng := _rng(state, pilot_id, "gain")
	var id: int = _roll(state, rng, ids)
	if id < 0:
		return {"result": "none", "id": -1}
	ids.append(id)
	_store(state, pilot_id, slots_of(state, pilot_id), ids)
	return {"result": "gain", "id": id}


## Rerolls every equipped quirk of the pilot. Returns `{result: "reroll"|"none", from: [id], to: [id]}`.
## Each slot draws a quirk the pilot does not hold and that is not the one it
## replaces (when the table allows), so every slot actually changes.
static func reroll(state: Dictionary, pilot_id: int) -> Dictionary:
	var from: Array = quirks_of(state, pilot_id)
	if not is_enabled(state) or from.is_empty():
		return {"result": "none", "from": from, "to": from.duplicate()}
	var rng := _rng(state, pilot_id, "reroll")
	var to: Array = []
	for old in from:
		var excl: Array = to.duplicate()
		excl.append(int(old))
		var id: int = _roll(state, rng, excl)
		if id < 0:
			id = _roll(state, rng, to)   # table too small to avoid the old one
		if id < 0:
			id = int(old)
		to.append(id)
	_store(state, pilot_id, slots_of(state, pilot_id), to)
	return {"result": "reroll", "from": from, "to": to}


## Slots added per slot-op training (QUIRK_SLOT_GAIN, at least one).
static func slot_gain() -> int:
	return maxi(1, ConstTable.int_of("QUIRK_SLOT_GAIN"))


## +`slot_gain()` slots, capped at QUIRK_SLOTS_MAX. Returns `{result: "slot"|"max", slots}`.
static func add_slot(state: Dictionary, pilot_id: int) -> Dictionary:
	var n: int = slots_of(state, pilot_id)
	if not is_enabled(state) or not _has_entry(state, pilot_id) or n >= max_slots():
		return {"result": "max", "slots": n}
	var to: int = mini(n + slot_gain(), max_slots())
	_store(state, pilot_id, to, quirks_of(state, pilot_id))
	return {"result": "slot", "slots": to}


## Total per-stat bonus `{stat_key: int}` for the pilot riding `pd.assigned_mech`
## (unconditional `stats` + `cond_stats` whose `cond` holds).
static func stat_bonus(state: Dictionary, pd: PlayerData) -> Dictionary:
	var mech_id: int = pd.assigned_mech.id if pd != null and pd.assigned_mech != null else -1
	return stat_bonus_with(state, pd, mech_id)


## `stat_bonus` for an explicit mech (-1 = no mech: conditions never hold).
## The ban/pick screen previews seats with this before anything is assigned.
static func stat_bonus_with(state: Dictionary, pd: PlayerData, mech_id: int) -> Dictionary:
	var out: Dictionary = {}
	if pd == null or not is_enabled(state):
		return out
	for id in quirks_of(state, pd.id):
		var r: Dictionary = row(id)
		if r.is_empty():
			continue
		_add_into(out, r["stats"])
		if cond_holds(state, pd, mech_id, String(r["cond"])):
			_add_into(out, r["cond_stats"])
	return out


## Sum of `stat_bonus_with` over all six stats — the one number the slot tags show.
static func bonus_total(state: Dictionary, pd: PlayerData, mech_id: int) -> int:
	var total: int = 0
	for v in stat_bonus_with(state, pd, mech_id).values():
		total += int(v)
	return total


## Adds `stat_bonus` to `pd`. **Call on a copy only** (`MatchFlow._finalize_rosters`).
static func apply_to(state: Dictionary, pd: PlayerData) -> void:
	if pd == null:
		return
	var b: Dictionary = stat_bonus(state, pd)
	for k in b.keys():
		pd.set(String(k), maxi(PlayerData.STAT_MIN, int(pd.get(String(k))) + int(b[k])))


## Table row `{id, name_key, grade, stats, cond, cond_stats, weight, desc_key}` ({} if unknown).
## `stats` / `cond_stats` come back parsed as `{stat_key: int}`. Text = l10n keys —
## display through `name_of` / `desc_of`.
static func row(id: int) -> Dictionary:
	_ensure_loaded()
	return _rows.get(id, {})


## Display name (current locale). "" for an unknown id.
static func name_of(id: int) -> String:
	return Loc.t(String(row(id).get("name_key", "")))  # l10n-dynamic: quirk.*.name


## Flavour description (current locale). "" for an unknown id.
static func desc_of(id: int) -> String:
	return Loc.t(String(row(id).get("desc_key", "")))  # l10n-dynamic: quirk.*.desc


# ── Conditions ───────────────────────────────────────────────────────────────
## Does `cond` hold for `pd` riding `mech_id`? Empty = always (no `cond_stats` then).
## Clauses joined by `&` must all hold; an unknown clause never holds.
static func cond_holds(state: Dictionary, pd: PlayerData, mech_id: int, cond: String) -> bool:
	if cond.strip_edges() == "":
		return true
	if pd == null or mech_id < 0:
		return false
	for part in cond.split("&", false):
		if not _clause_holds(state, pd, mech_id, String(part).strip_edges()):
			return false
	return true


static func _clause_holds(state: Dictionary, pd: PlayerData, mech_id: int, clause: String) -> bool:
	var bits: PackedStringArray = clause.split(":", false)
	var kind: String = String(bits[0]) if bits.size() > 0 else ""
	var arg: int = int(String(bits[1])) if bits.size() > 1 else 0
	match kind:
		"main":
			for m in pd.main_mechs:
				if int(m) == mech_id:
					return true
			return false
		"own_role":
			return _mech_role(mech_id) == pd.role
		"mech_role":
			return _mech_role(mech_id) == arg
		"tier":
			return MechMastery.is_enabled(state) \
					and MechMastery.tier_of(MechMastery.value(state, pd.id, mech_id)) >= arg
	return false


static func _mech_role(mech_id: int) -> int:
	for e in MechMastery.all_mechs():
		if int((e as Dictionary)["id"]) == mech_id:
			return int((e as Dictionary)["role"])
	return -1


# ── Text (shared by every screen that lists quirks) ──────────────────────────
static func grade_name(grade: int) -> String:
	return GameEnums.rarity_label(int(GRADE_TIERS[clampi(grade, 0, GRADE_COUNT - 1)]))


static func grade_color(grade: int) -> Color:
	return GRADE_COLORS[clampi(grade, 0, GRADE_COUNT - 1)]


## "전장 명중 +3 · 교전 회피 +2" — `short` uses `PlayerData.STAT_SHORT`.
static func stats_text(stats: Dictionary, short: bool = false) -> String:
	var parts: Array = []
	for i in PlayerData.STAT_KEYS.size():
		var k: String = String(PlayerData.STAT_KEYS[i])
		if stats.has(k) and int(stats[k]) != 0:
			var label: String = PlayerData.stat_short(i) if short else PlayerData.stat_label(i)
			parts.append("%s %+d" % [label, int(stats[k])])
	return " · ".join(parts)


## The condition in words ("주력 메크 탑승" …). Empty for no condition.
static func cond_text(cond: String) -> String:
	if cond.strip_edges() == "":
		return ""
	var parts: Array = []
	for part in cond.split("&", false):
		var bits: PackedStringArray = String(part).strip_edges().split(":", false)
		var kind: String = String(bits[0]) if bits.size() > 0 else ""
		var arg: int = int(String(bits[1])) if bits.size() > 1 else 0
		match kind:
			"main":
				parts.append(Loc.t(L.QUIRK_COND_MAIN))
			"own_role":
				parts.append(Loc.t(L.QUIRK_COND_OWN_ROLE))
			"mech_role":
				parts.append(Loc.t(L.QUIRK_COND_MECH_ROLE, {"role": OutgameTheme.role_name(arg)}))
			"tier":
				parts.append(Loc.t(L.QUIRK_COND_TIER, {"tier": MechMastery.tier_name(arg)}))
			_:
				parts.append(kind)
	return " · ".join(parts)


## One-line effect: "전장 명중 +3" or "공격 성장 +3 / 주력 메크 탑승 시 전장 명중 +4 · …".
static func effect_text(id: int, short: bool = false) -> String:
	var r: Dictionary = row(id)
	if r.is_empty():
		return ""
	var base: String = stats_text(r["stats"], short)
	var c: String = String(r["cond"])
	if c.strip_edges() == "":
		return base
	var extra: String = Loc.t(L.QUIRK_EFFECT_COND,
			{"cond": cond_text(c), "stats": stats_text(r["cond_stats"], short)})
	return extra if base == "" else "%s / %s" % [base, extra]


# ── Rolls ────────────────────────────────────────────────────────────────────
## Grade weights right now — `[w0, w1, w2]`, base + per-knowledge part.
static func grade_weights(state: Dictionary) -> Array:
	var know: float = float(StaffSystem.effective(state, "knowledge"))
	var out: Array = []
	for g in GRADE_COUNT:
		var w: float = ConstTable.num("QUIRK_GRADE_W_%d" % g)
		if ConstTable.has("QUIRK_KNOW_W_%d" % g):
			w += ConstTable.num("QUIRK_KNOW_W_%d" % g) * know
		out.append(maxf(0.0, w))
	return out


## Grade odds in percent `[p0, p1, p2]` (for the sheet legend).
static func grade_odds(state: Dictionary) -> Array:
	var w: Array = grade_weights(state)
	var total: float = 0.0
	for v in w:
		total += float(v)
	var out: Array = []
	for v2 in w:
		out.append(0.0 if total <= 0.0 else float(v2) * 100.0 / total)
	return out


## One quirk id not in `exclude` — grade first, then row weight inside the
## grade. A grade with nothing left is skipped (its weight drops out). -1 if
## the whole table is excluded.
static func _roll(state: Dictionary, rng: RandomNumberGenerator, exclude: Array) -> int:
	_ensure_loaded()
	var gw: Array = grade_weights(state)
	var pools: Array = []
	var weights := PackedFloat32Array()
	for g in GRADE_COUNT:
		var pool: Array = []
		for id in (_ids_by_grade[g] as Array):
			if not exclude.has(int(id)) and int((_rows[id] as Dictionary)["weight"]) > 0:
				pool.append(int(id))
		pools.append(pool)
		weights.append(float(gw[g]) if not pool.is_empty() else 0.0)
	var total: float = 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return -1
	var g_pick: int = rng.rand_weighted(weights)
	var pool_pick: Array = pools[g_pick]
	var iw := PackedFloat32Array()
	for id2 in pool_pick:
		iw.append(float(int((_rows[id2] as Dictionary)["weight"])))
	return int(pool_pick[rng.rand_weighted(iw)])


## Deterministic per run · week · weekday · pilot · purpose · current quirks
## (so two rolls in a row on the same pilot still differ).
static func _rng(state: Dictionary, pilot_id: int, purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(state.get("run_seed", 0)), int(state.get("current_phase", 0)),
			int(state.get("phase_week", 1)), int(state.get("week_day", -1)),
			pilot_id, purpose, quirks_of(state, pilot_id), slots_of(state, pilot_id)])
	return rng


# ── State ────────────────────────────────────────────────────────────────────
static func _has_entry(state: Dictionary, pilot_id: int) -> bool:
	return (state.get("quirks", {}) as Dictionary).has(str(pilot_id))


static func _entry(state: Dictionary, pilot_id: int) -> Dictionary:
	var q: Variant = state.get("quirks", {})
	if typeof(q) != TYPE_DICTIONARY:
		return {}
	var e: Variant = (q as Dictionary).get(str(pilot_id), {})
	return e if typeof(e) == TYPE_DICTIONARY else {}


static func _store(state: Dictionary, pilot_id: int, slots: int, ids: Array) -> void:
	var q: Dictionary = state.get("quirks", {})
	var clean: Array = []
	for v in ids:
		clean.append(int(v))
	q[str(pilot_id)] = {"slots": slots, "ids": clean}
	state["quirks"] = q


static func _add_into(acc: Dictionary, add: Dictionary) -> void:
	for k in add.keys():
		acc[k] = int(acc.get(k, 0)) + int(add[k])


# ── Table ────────────────────────────────────────────────────────────────────
## Every quirk id in id order (for docs / tests).
static func all_ids() -> Array:
	_ensure_loaded()
	var out: Array = _rows.keys()
	out.sort()
	return out


## `stat:n|stat:n` → `{stat_key: int}`; unknown stats are dropped.
static func parse_stats(raw: String) -> Dictionary:
	var out: Dictionary = {}
	for part in raw.split("|", false):
		var kv: PackedStringArray = String(part).strip_edges().split(":", false)
		if kv.size() != 2:
			continue
		var k: String = String(kv[0]).strip_edges()
		if k in PlayerData.STAT_KEYS:
			out[k] = int(out.get(k, 0)) + int(String(kv[1]))
	return out


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_ids_by_grade = []
	for g in GRADE_COUNT:
		_ids_by_grade.append([])
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_warning("QuirkSystem: cannot open game.db")
		return
	db.query("SELECT id, name_key, grade, stats, cond, cond_stats, weight, desc_key FROM quirks ORDER BY id")
	for r in db.query_result:
		var id: int = int(r["id"])
		var g: int = clampi(int(r["grade"]), 0, GRADE_COUNT - 1)
		_rows[id] = {
			"id": id, "name_key": String(r["name_key"]), "grade": g,
			"stats": parse_stats(String(r["stats"])), "cond": String(r["cond"]),
			"cond_stats": parse_stats(String(r["cond_stats"])),
			"weight": int(r["weight"]), "desc_key": String(r["desc_key"]),
		}
		(_ids_by_grade[g] as Array).append(id)
	db.close_db()
