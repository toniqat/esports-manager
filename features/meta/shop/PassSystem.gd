class_name PassSystem
extends RefCounted

# ── Weekly pass (free, local) — M10 ──────────────────────────────────────────
# Contract: `docs/outgame_dev_plan.md` §12. Pure rules over the profile dictionary
# (`profile.pass = {week_id, exp, claimed: Array[int]}`); mutators do not save.
#
# - Pass exp comes from run settlement (`RunResult`: score × `PASS_EXP_PER_SCORE`).
# - Level = 1 + exp / `PASS_EXP_PER_LEVEL`, capped at `PASS_MAX_LEVEL`; rewards per level
#   in `pass_rewards.csv`, claimed by hand (`claim` — feature E). Exp past the cap converts
#   to outgame currency: `PASS_OVERFLOW_OUTGAME` per extra level's worth.
# - Resets every ISO week of the **device clock** (`week_id_now`) — clock tampering is a
#   server-stage problem (§3 M11).

static var _rewards: Dictionary = {}    # int level → {currency, amount}
static var _loaded: bool = false


## "YYYY-Www" (ISO-8601 week) of the device clock, in **local** time — the week turns
## at Monday 00:00 on the device, matching the countdown (`seconds_until_reset`).
static func week_id_now() -> String:
	return week_id_of(local_unix_now())


## Device clock as a "local unix" (UTC seconds shifted by the time-zone bias), so the
## UTC date helpers below read local calendar fields.
static func local_unix_now() -> int:
	var bias_min: int = int(Time.get_time_zone_from_system().get("bias", 0))
	return int(Time.get_unix_time_from_system()) + bias_min * 60


## Seconds from `local_unix` until the next Monday 00:00 (the weekly reset).
static func seconds_until_reset(local_unix: int = -1) -> int:
	var t: int = local_unix_now() if local_unix < 0 else local_unix
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(t)
	var iso_wd: int = 7 if int(d["weekday"]) == 0 else int(d["weekday"])
	var day_start: int = t - posmod(t, 86400)
	return day_start + (8 - iso_wd) * 86400 - t


static func week_id_of(unix: int) -> String:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(unix)
	# ISO weekday 1..7 (Mon..Sun); Godot weekday 0 = Sunday.
	var iso_wd: int = 7 if int(d["weekday"]) == 0 else int(d["weekday"])
	# The Thursday of this week decides the ISO year.
	var thu: int = unix + (4 - iso_wd) * 86400
	var td: Dictionary = Time.get_datetime_dict_from_unix_time(thu)
	var jan1: int = int(Time.get_unix_time_from_datetime_dict(
			{"year": td["year"], "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0}))
	var week: int = int((thu - jan1) / 86400) / 7 + 1
	return "%04d-W%02d" % [int(td["year"]), week]


static func max_level() -> int:
	return maxi(1, ConstTable.int_of("PASS_MAX_LEVEL"))


static func exp_per_level() -> int:
	return maxi(1, ConstTable.int_of("PASS_EXP_PER_LEVEL"))


## Resets the pass when the stored week is not this week. true when it reset.
static func ensure_week(profile: Dictionary) -> bool:
	var ps: Dictionary = _pass(profile)
	var now: String = week_id_now()
	if String(ps.get("week_id", "")) == now:
		return false
	ps["week_id"] = now
	ps["exp"] = 0
	ps["claimed"] = []
	return true


static func exp_of(profile: Dictionary) -> int:
	return int(_pass(profile).get("exp", 0))


static func level_of(profile: Dictionary) -> int:
	return mini(max_level(), 1 + exp_of(profile) / exp_per_level())


## Adds pass exp (after a week check). Exp beyond the max level is converted to
## outgame currency right away. → `{from, to, overflow_outgame}`.
static func add_exp(profile: Dictionary, amount: int) -> Dictionary:
	ensure_week(profile)
	var ps: Dictionary = _pass(profile)
	var from_lv: int = level_of(profile)
	var cap_exp: int = (max_level() - 1) * exp_per_level()
	var total: int = int(ps.get("exp", 0)) + maxi(0, amount)
	var overflow_outgame: int = 0
	var carry: int = int(ps.get("overflow", 0))
	if total > cap_exp:
		carry += total - cap_exp
		total = cap_exp
		var lv_worth: int = carry / exp_per_level()
		carry -= lv_worth * exp_per_level()
		overflow_outgame = lv_worth * maxi(0, ConstTable.int_of("PASS_OVERFLOW_OUTGAME"))
		if overflow_outgame > 0:
			var cur: Dictionary = profile.get("currency", {})
			cur["outgame"] = int(cur.get("outgame", 0)) + overflow_outgame
	ps["exp"] = total
	ps["overflow"] = carry
	return {"from": from_lv, "to": level_of(profile), "overflow_outgame": overflow_outgame}


## `{currency, amount}` of a pass level (empty when none).
static func reward_at(level: int) -> Dictionary:
	_ensure_loaded()
	return _rewards.get(level, {})


static func is_claimed(profile: Dictionary, level: int) -> bool:
	for raw in (_pass(profile).get("claimed", []) as Array):
		if int(raw) == level:
			return true
	return false


## Claims one reached, unclaimed level: its reward goes into `profile.currency` and the
## level into `claimed`. "" on success, else why not (nothing changes). Week check first.
static func claim(profile: Dictionary, level: int) -> String:
	ensure_week(profile)
	if level < 1 or level > max_level():
		return "없는 단계입니다"
	if level > level_of(profile):
		return "아직 도달하지 않은 단계입니다"
	if is_claimed(profile, level):
		return "이미 수령했습니다"
	var rw: Dictionary = reward_at(level)
	if rw.is_empty():
		return "보상이 없는 단계입니다"
	var cur: Dictionary = profile.get("currency", {})
	var key: String = String(rw["currency"])
	cur[key] = maxi(0, int(cur.get(key, 0)) + int(rw["amount"]))
	profile["currency"] = cur
	var claimed: Array = _pass(profile).get("claimed", [])
	claimed.append(level)
	_pass(profile)["claimed"] = claimed
	return ""


## Reached, unclaimed levels that have a reward (ascending).
static func claimable_levels(profile: Dictionary) -> Array:
	ensure_week(profile)
	var out: Array = []
	for lv in range(1, level_of(profile) + 1):
		if not is_claimed(profile, lv) and not reward_at(lv).is_empty():
			out.append(lv)
	return out


## Claims every claimable level. → `{count, gained: {currency: amount}}`.
static func claim_all(profile: Dictionary) -> Dictionary:
	var gained: Dictionary = {}
	var n: int = 0
	for lv in claimable_levels(profile):
		if claim(profile, int(lv)) == "":
			n += 1
			var rw: Dictionary = reward_at(int(lv))
			var key: String = String(rw["currency"])
			gained[key] = int(gained.get(key, 0)) + int(rw["amount"])
	return {"count": n, "gained": gained}


## Exp inside the current level → `{into, need}` (`need` 0 at the max level).
static func level_progress(profile: Dictionary) -> Dictionary:
	if level_of(profile) >= max_level():
		return {"into": 0, "need": 0}
	return {"into": exp_of(profile) % exp_per_level(), "need": exp_per_level()}


static func _pass(profile: Dictionary) -> Dictionary:
	if not profile.has("pass") or typeof(profile["pass"]) != TYPE_DICTIONARY:
		profile["pass"] = {"week_id": "", "exp": 0, "claimed": []}
	return profile["pass"]


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_warning("PassSystem: cannot open game.db")
		return
	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='pass_rewards'")
	if not db.query_result.is_empty():
		db.query("SELECT * FROM pass_rewards ORDER BY level")
		for r in db.query_result:
			_rewards[int(r["level"])] = {"currency": String(r["currency"]), "amount": int(r["amount"])}
	db.close_db()
