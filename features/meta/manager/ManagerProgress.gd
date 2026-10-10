class_name ManagerProgress
extends RefCounted

# ── Manager growth (M9) — pure rules over the profile dictionary ─────────────
# Contract: `docs/outgame_dev_plan.md` §12. Every function takes the
# `ProfileManager.profile` dictionary (no autoload dependency → headless-checkable).
# Mutators change `profile` in place and **do not save** — the caller calls
# `ProfileManager.save_profile()` once per user action.
#
# Stat model (manager stats 1..`MANAGER_STAT_CAP`):
#   base(stat)   = manager_types[type][stat] − removed[stat] × MANAGER_REMOVE_STAT_DROP  (≥ STAT_MIN)
#   preset(stat) = base(stat) + preset.alloc[stat]                     (≤ MANAGER_STAT_CAP)
# - Each level-up grants `MANAGER_REMOVE_PER_LEVEL` **removal points**.
#   Spending one lowers a stat's base by `MANAGER_REMOVE_STAT_DROP` (not below STAT_MIN),
#   **permanent until prestige**, and yields `MANAGER_SPEC_PER_REMOVAL`
#   **specialisation points**.
# - Specialisation points = Σ removed × MANAGER_SPEC_PER_REMOVAL. Each preset distributes them freely
#   (`alloc`, any stat, add / take back at will between runs). Total stays constant —
#   specialising moves points, it never creates them.
# - Prestige (Lv `PRESTIGE_LEVEL`, no season limit): level 1, exp 0, removals cleared,
#   type re-chosen, existing presets turn into `kind = "prestige"` (unusable until
#   reset), `PRESTIGE_NEW_PRESETS` new normal presets are appended (up to `PRESET_MAX_COUNT`),
#   the last one becomes active, `PRESTIGE_REWARD_*` currency is granted.

const KIND_NORMAL: String = "normal"
const KIND_PRESTIGE: String = "prestige"

static var _levels: Array = []      # index = level - 1 → cumulative exp required
static var _loaded: bool = false


# ── Levels ───────────────────────────────────────────────────────────────────
static func max_level() -> int:
	_ensure_loaded()
	return maxi(1, _levels.size())


## Cumulative exp needed to be at `level` (level 1 = 0).
static func exp_for_level(level: int) -> int:
	_ensure_loaded()
	if _levels.is_empty():
		return 0
	return int(_levels[clampi(level, 1, _levels.size()) - 1])


static func level_for_exp(exp_total: int) -> int:
	_ensure_loaded()
	var lv: int = 1
	for i in _levels.size():
		if exp_total >= int(_levels[i]):
			lv = i + 1
	return lv


static func level_of(profile: Dictionary) -> int:
	return int(_mgr(profile).get("level", 1))


static func exp_of(profile: Dictionary) -> int:
	return int(_mgr(profile).get("exp", 0))


## Adds manager exp and levels up (capped at `max_level()`; exp keeps accumulating).
## → `{from, to}` levels.
static func add_exp(profile: Dictionary, amount: int) -> Dictionary:
	var mgr: Dictionary = _mgr(profile)
	var from_lv: int = int(mgr.get("level", 1))
	mgr["exp"] = int(mgr.get("exp", 0)) + maxi(0, amount)
	var to_lv: int = maxi(from_lv, mini(max_level(), level_for_exp(int(mgr["exp"]))))
	mgr["level"] = to_lv
	return {"from": from_lv, "to": to_lv}


# ── Stats ────────────────────────────────────────────────────────────────────
static func stat_cap() -> int:
	return clampi(ConstTable.int_of("MANAGER_STAT_CAP"), StaffSystem.STAT_MIN, StaffSystem.STAT_MAX)


## The type's initial stats `{stat: int}`.
static func type_stats(type_id: int) -> Dictionary:
	var r: Dictionary = StaffSystem.manager_type_row(type_id)
	if r.is_empty() and not StaffSystem.manager_types().is_empty():
		r = StaffSystem.manager_types()[0]
	var out: Dictionary = {}
	for s in StaffSystem.STATS:
		out[s] = int((r.get("stats", {}) as Dictionary).get(s, StaffSystem.STAT_MIN))
	return out


static func removed(profile: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var raw: Dictionary = _mgr(profile).get("removed", {})
	for s in StaffSystem.STATS:
		out[s] = maxi(0, int(raw.get(s, 0)))
	return out


static func removal_points_total(profile: Dictionary) -> int:
	return maxi(0, level_of(profile) - 1) * maxi(0, ConstTable.int_of("MANAGER_REMOVE_PER_LEVEL"))


static func removal_points_left(profile: Dictionary) -> int:
	var used: int = 0
	var rm: Dictionary = removed(profile)
	for s in rm.keys():
		used += int(rm[s])
	return maxi(0, removal_points_total(profile) - used)


## Base-stat drop per removal point spent (MANAGER_REMOVE_STAT_DROP, at least one).
static func remove_stat_drop() -> int:
	return maxi(1, ConstTable.int_of("MANAGER_REMOVE_STAT_DROP"))


## Specialisation points gained per removal point spent (MANAGER_SPEC_PER_REMOVAL).
static func spec_per_removal() -> int:
	return maxi(0, ConstTable.int_of("MANAGER_SPEC_PER_REMOVAL"))


## Specialisation points = Σ removed × `spec_per_removal()` (the pool every preset distributes).
static func spec_points(profile: Dictionary) -> int:
	var total: int = 0
	var rm: Dictionary = removed(profile)
	for s in rm.keys():
		total += int(rm[s])
	return total * spec_per_removal()


## type − removed × `remove_stat_drop()`, each ≥ STAT_MIN.
static func base_stats(profile: Dictionary) -> Dictionary:
	var t: Dictionary = type_stats(int(_mgr(profile).get("type", 0)))
	var rm: Dictionary = removed(profile)
	var drop: int = remove_stat_drop()
	var out: Dictionary = {}
	for s in StaffSystem.STATS:
		out[s] = maxi(StaffSystem.STAT_MIN, int(t[s]) - int(rm[s]) * drop)
	return out


## "" when one removal point can be spent on `stat`.
static func can_remove(profile: Dictionary, stat: String) -> String:
	if not StaffSystem.STATS.has(stat):
		return Loc.t(L.MANAGER_PROGRESS_UNKNOWN_STAT)
	if removal_points_left(profile) <= 0:
		return Loc.t(L.MANAGER_PROGRESS_NO_REMOVAL)
	if int(base_stats(profile)[stat]) <= StaffSystem.STAT_MIN:
		return Loc.t(L.MANAGER_PROGRESS_STAT_AT_MIN, {"min": StaffSystem.STAT_MIN})
	return ""


## Spends one removal point on `stat` (permanent until prestige). "" on success.
## Presets whose alloc pushed this stat to the cap stay valid (base drops, so the
## preset value drops by `remove_stat_drop()`).
static func remove_stat(profile: Dictionary, stat: String) -> String:
	var err: String = can_remove(profile, stat)
	if err != "":
		return err
	var mgr: Dictionary = _mgr(profile)
	var rm: Dictionary = mgr.get("removed", {})
	rm[stat] = int(rm.get(stat, 0)) + 1
	mgr["removed"] = rm
	return ""


# ── Presets ──────────────────────────────────────────────────────────────────
static func new_preset(kind: String = KIND_NORMAL) -> Dictionary:
	var alloc: Dictionary = {}
	for s in StaffSystem.STATS:
		alloc[s] = 0
	return {"kind": kind, "alloc": alloc, "traits": []}


static func presets(profile: Dictionary) -> Array:
	return profile.get("presets", [])


static func preset_at(profile: Dictionary, idx: int) -> Dictionary:
	var ps: Array = presets(profile)
	if idx < 0 or idx >= ps.size():
		return {}
	return ps[idx]


static func active_index(profile: Dictionary) -> int:
	return clampi(int(profile.get("active_preset", 0)), 0, maxi(0, presets(profile).size() - 1))


static func alloc_used(preset: Dictionary) -> int:
	var total: int = 0
	var a: Dictionary = preset.get("alloc", {})
	for s in a.keys():
		total += maxi(0, int(a[s]))
	return total


## Manager stats this preset gives `{stat: int}` (base + alloc, clamped to [1, cap]).
static func preset_stats(profile: Dictionary, preset: Dictionary) -> Dictionary:
	var base: Dictionary = base_stats(profile)
	var a: Dictionary = preset.get("alloc", {})
	var out: Dictionary = {}
	for s in StaffSystem.STATS:
		out[s] = clampi(int(base[s]) + maxi(0, int(a.get(s, 0))), StaffSystem.STAT_MIN, stat_cap())
	return out


## "" when `delta` (+1 / −1) can be applied to `preset.alloc[stat]`.
static func can_alloc(profile: Dictionary, preset: Dictionary, stat: String, delta: int) -> String:
	if not StaffSystem.STATS.has(stat):
		return Loc.t(L.MANAGER_PROGRESS_UNKNOWN_STAT)
	var cur: int = int((preset.get("alloc", {}) as Dictionary).get(stat, 0))
	if delta < 0:
		return "" if cur + delta >= 0 else Loc.t(L.MANAGER_PROGRESS_NO_SPEC_TO_REMOVE)
	if alloc_used(preset) + delta > spec_points(profile):
		return Loc.t(L.MANAGER_PROGRESS_NO_SPEC_LEFT)
	if int(base_stats(profile)[stat]) + cur + delta > stat_cap():
		return Loc.t(L.MANAGER_PROGRESS_STAT_CAP, {"cap": stat_cap()})
	return ""


## Applies `delta` to `preset.alloc[stat]` when allowed. "" on success.
static func alloc_step(profile: Dictionary, preset: Dictionary, stat: String, delta: int) -> String:
	var err: String = can_alloc(profile, preset, stat, delta)
	if err != "":
		return err
	var a: Dictionary = preset.get("alloc", {})
	a[stat] = int(a.get(stat, 0)) + delta
	preset["alloc"] = a
	return ""


## Turns a prestige preset back into a usable normal one with an empty alloc
## (its traits are kept).
static func reset_preset(preset: Dictionary) -> void:
	var fresh: Dictionary = new_preset()
	preset["kind"] = KIND_NORMAL
	preset["alloc"] = fresh["alloc"]


## "" when the preset may start a run. `owned_traits` = Array[int].
static func validate_preset(profile: Dictionary, preset: Dictionary, owned_traits: Array) -> String:
	if preset.is_empty():
		return Loc.t(L.MANAGER_PROGRESS_NO_PRESET)
	if String(preset.get("kind", KIND_NORMAL)) == KIND_PRESTIGE:
		return Loc.t(L.MANAGER_PROGRESS_PRESTIGE_PRESET)
	if alloc_used(preset) > spec_points(profile):
		return Loc.t(L.MANAGER_PROGRESS_SPEC_OVER,
				{"used": alloc_used(preset), "total": spec_points(profile)})
	var base: Dictionary = base_stats(profile)
	var a: Dictionary = preset.get("alloc", {})
	for s in StaffSystem.STATS:
		if int(a.get(s, 0)) < 0:
			return Loc.t(L.MANAGER_PROGRESS_SPEC_NEGATIVE)
		if int(base[s]) + int(a.get(s, 0)) > stat_cap():
			return Loc.t(L.MANAGER_PROGRESS_STAT_OVER_CAP,
					{"stat": StaffSystem.stat_label(String(s)), "cap": stat_cap()})
	return TraitSystem.validate_equip(preset.get("traits", []), owned_traits)


# ── Prestige ─────────────────────────────────────────────────────────────────
static func prestige_level() -> int:
	return clampi(ConstTable.int_of("PRESTIGE_LEVEL"), 1, max_level())


static func can_prestige(profile: Dictionary) -> String:
	if level_of(profile) < prestige_level():
		return Loc.t(L.MANAGER_PROGRESS_PRESTIGE_LEVEL, {"level": prestige_level()})
	return ""


## Prestige with the re-chosen `new_type`. Mutates `profile`; → `{rewards: {currency: n}}`
## or `{error}`.
static func prestige(profile: Dictionary, new_type: int) -> Dictionary:
	var err: String = can_prestige(profile)
	if err != "":
		return {"error": err}
	var mgr: Dictionary = _mgr(profile)
	mgr["level"] = 1
	mgr["exp"] = 0
	mgr["removed"] = {}
	mgr["type"] = new_type
	mgr["type_chosen"] = true
	mgr["prestige"] = int(mgr.get("prestige", 0)) + 1
	var ps: Array = presets(profile)
	for p in ps:
		(p as Dictionary)["kind"] = KIND_PRESTIGE
	var room: int = maxi(1, ConstTable.int_of("PRESET_MAX_COUNT")) - ps.size()
	var add: int = mini(maxi(1, ConstTable.int_of("PRESTIGE_NEW_PRESETS")), room)
	if add > 0:
		for _i in add:
			ps.append(new_preset())
		profile["active_preset"] = ps.size() - 1
	else:
		# Full — the active preset is reset in place so the next run can start.
		var act: int = active_index(profile)
		reset_preset(ps[act])
	profile["presets"] = ps
	var rewards: Dictionary = {
		"outgame": ConstTable.int_of("PRESTIGE_REWARD_OUTGAME"),
		"gacha_ticket_pilot": ConstTable.int_of("PRESTIGE_REWARD_PILOT_TICKETS"),
		"gacha_ticket_trait": ConstTable.int_of("PRESTIGE_REWARD_TRAIT_TICKETS"),
	}
	var cur: Dictionary = profile.get("currency", {})
	for k in rewards.keys():
		cur[k] = int(cur.get(k, 0)) + int(rewards[k])
	profile["currency"] = cur
	return {"rewards": rewards}


# ── UI helpers (manager tab / run setup step) ────────────────────────────────
## Progress inside the current level: `{level, into, span, is_max}` — `into` = exp
## past this level's threshold, `span` = exp from this level to the next (0 at max).
static func level_progress(profile: Dictionary) -> Dictionary:
	var lv: int = level_of(profile)
	var at: int = exp_for_level(lv)
	if lv >= max_level():
		return {"level": lv, "into": maxi(0, exp_of(profile) - at), "span": 0, "is_max": true}
	var span: int = maxi(1, exp_for_level(lv + 1) - at)
	return {"level": lv, "into": clampi(exp_of(profile) - at, 0, span), "span": span,
			"is_max": false}


## Equips / unequips `trait_id` on `preset.traits` (rewritten as Array[int]). "" on success.
## Over-budget sets (bonus < 0) are allowed here on purpose — screens show the red
## state and `validate_preset` blocks saving / starting.
static func toggle_trait(preset: Dictionary, trait_id: int, owned_traits: Array) -> String:
	var cur: Array = []
	for raw in (preset.get("traits", []) as Array):
		cur.append(int(raw))
	if cur.has(trait_id):
		cur.erase(trait_id)
	else:
		if not owned_traits.has(trait_id):
			return Loc.t(L.MANAGER_PROGRESS_TRAIT_LOCKED)
		cur.append(trait_id)
	preset["traits"] = cur
	return ""


## Deep copy of preset `idx` for editing (`{}` when out of range).
static func preset_copy(profile: Dictionary, idx: int) -> Dictionary:
	return preset_at(profile, idx).duplicate(true)


## Writes an edited copy back over preset `idx` (no validation, no save).
static func store_preset(profile: Dictionary, idx: int, preset: Dictionary) -> void:
	var ps: Array = presets(profile)
	if idx < 0 or idx >= ps.size():
		return
	ps[idx] = preset.duplicate(true)


# ── Internals ────────────────────────────────────────────────────────────────
static func _mgr(profile: Dictionary) -> Dictionary:
	if not profile.has("manager") or typeof(profile["manager"]) != TYPE_DICTIONARY:
		profile["manager"] = {}
	return profile["manager"]


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_warning("ManagerProgress: cannot open game.db")
		return
	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='manager_levels'")
	if not db.query_result.is_empty():
		db.query("SELECT * FROM manager_levels ORDER BY level")
		for r in db.query_result:
			_levels.append(int(r["exp_required"]))
	db.close_db()
	if _levels.is_empty():
		_levels.append(0)
