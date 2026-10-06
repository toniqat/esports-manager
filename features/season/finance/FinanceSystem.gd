class_name FinanceSystem
extends RefCounted

# ── Finance · facilities (M6) ────────────────────────────────────────────────
# Owns the shape of `season_state.finance` (see `finance/README.md`). Other
# features only call the functions below; the four multipliers are the only
# way finance reaches training / mastery / incidents.
#
# Week end (`settle_week`, Sunday close, before the calendar rolls):
#   income  = sponsor_base × facility income_pct + match bonus of the week
#   expense = staff weekly salaries + facility upkeep
#   net >= 0 → FINANCE_RESERVE_PCT of it stays in the balance, the rest is
#              split across training / facility fund / welfare (allocation).
#   net <  0 → bankruptcy rule (balance never goes negative):
#              allocation stops → balance → facility fund → one forced cut
#              (facility downgrade, or a training penalty at level 1).
#
# All numbers are tuning values in `const.csv` (`FINANCE_*`) and
# `facilities.csv`. Saved state goes through JSON, so every read is `int()` /
# `float()`-wrapped.

const AXES: Array = ["training", "facility", "welfare"]
const AXIS_LABELS: Dictionary = {
	"training": "훈련", "facility": "시설 적립", "welfare": "복지",
}
## Manual allocation the run starts with (percent, sums to 100, step-aligned).
const DEFAULT_ALLOC: Dictionary = {"training": 40, "facility": 30, "welfare": 30}

static var _facilities: Dictionary = {}   # int level → row Dictionary
static var _max_level: int = 1
static var _loaded: bool = false


# ── Run lifecycle ────────────────────────────────────────────────────────────
## Once at run start (`GameManager.start_run`) — starting balance, facility
## level from the team package, default allocation.
static func init_run(state: Dictionary, team_id: int) -> void:
	var pkg: Dictionary = _team_package(team_id)
	state["finance"] = {
		"balance": maxi(0, ConstTable.int_of("FINANCE_START_BALANCE")),
		"facility_level": clampi(int(pkg.get("facility_level", 1)), 1, max_level()),
		"facility_fund": 0,
		"sponsor_base": int(pkg.get("budget", 0)),
		"alloc": DEFAULT_ALLOC.duplicate(),
		"effects": {"training_pct": 0.0, "welfare_pct": 0.0},
		"penalty_weeks": 0,
		"week_bonus": 0,
		"week_wins": 0,
		"week_losses": 0,
		"week_no": 0,
		"manual_profit_weeks": 0,
		"history": [],
	}


## Week end (`SeasonHub._end_week`, before the calendar advances). Returns the
## week summary `{income, expense, net, balance, cuts: Array[String], toast, …}`
## (the full history entry plus `toast`).
static func settle_week(state: Dictionary) -> Dictionary:
	var f: Dictionary = _fin(state)
	var lvl: int = facility_level(state)
	var row: Dictionary = facility_row(lvl)
	var income_pct: int = int(row.get("income_pct", 100))
	var sponsor: int = sponsor_income(state, lvl)
	var bonus: int = int(f.get("week_bonus", 0))
	var income: int = sponsor + bonus
	var salaries: int = StaffSystem.weekly_salary_total(state)
	var upkeep: int = upkeep_cost(state, lvl)
	var expense: int = salaries + upkeep
	var net: int = income - expense

	# The week that just ended consumed one penalty week.
	var penalty: int = maxi(0, int(f.get("penalty_weeks", 0)) - 1)
	var balance_now: int = maxi(0, int(f.get("balance", 0)))
	var fund: int = maxi(0, int(f.get("facility_fund", 0)))
	var cuts: Array = []
	var spent: Dictionary = {"training": 0, "facility": 0, "welfare": 0}
	var reserve: int = 0
	var unpaid: int = 0
	var delegated: bool = StaffSystem.is_delegated(state, "finance")
	# M8 — trait unlock `finance_manual_profit:N` counts surplus weeks run by the manager.
	if net >= 0 and StaffSystem.owner(state, "finance") == StaffSystem.OWNER_MANAGER:
		f["manual_profit_weeks"] = int(f.get("manual_profit_weeks", 0)) + 1

	if net >= 0:
		reserve = _pct_of(net, clampi(ConstTable.int_of("FINANCE_RESERVE_PCT"), 0, 100))
		var pool: int = net - reserve
		var shares: Dictionary = allocation_shares(state)
		# Floor each share; the rounding remainder goes to the largest share
		# (so a 0% axis never collects stray units).
		var rest: int = pool
		var biggest: String = "training"
		for axis in AXES:
			spent[axis] = _pct_of(pool, int(shares[axis]))
			rest -= int(spent[axis])
			if int(shares[axis]) > int(shares[biggest]):
				biggest = axis
		spent[biggest] = int(spent[biggest]) + rest
		balance_now += reserve
		fund += int(spent["facility"])
	else:
		# Bankruptcy rule — see README. 1) allocation stops (no surplus to split),
		# 2) balance pays, 3) facility fund pays, 4) one forced cut writes the rest off.
		var need: int = -net
		cuts.append("훈련 · 복지 지원 중단")
		var from_balance: int = mini(balance_now, need)
		balance_now -= from_balance
		need -= from_balance
		if need > 0 and fund > 0:
			var from_fund: int = mini(fund, need)
			fund -= from_fund
			need -= from_fund
			cuts.append("시설 적립금 %s 전용" % fmt(from_fund))
		if need > 0:
			unpaid = need
			if lvl > 1:
				cuts.append("시설 Lv%d → Lv%d 강등 (미납 %s)" % [lvl, lvl - 1, fmt(need)])
				lvl -= 1
			else:
				penalty = maxi(penalty, ConstTable.int_of("FINANCE_UNPAID_PENALTY_WEEKS"))
				cuts.append("훈련 지원 삭감 %d주 (훈련 EXP −%d%%)" % [
						penalty, ConstTable.int_of("FINANCE_UNPAID_TRAIN_PENALTY_PCT")])

	var week_no: int = int(f.get("week_no", 0)) + 1
	var entry: Dictionary = {
		"week_no": week_no,
		"phase": int(state.get("current_phase", 0)),
		"phase_week": int(state.get("phase_week", 1)),
		"sponsor": sponsor,
		"income_pct": income_pct,
		"trait_income_pct": TraitSystem.run_mod(state, "income_pct"),
		"trait_upkeep_pct": TraitSystem.run_mod(state, "upkeep_pct"),
		"bonus": bonus,
		"wins": int(f.get("week_wins", 0)),
		"losses": int(f.get("week_losses", 0)),
		"income": income,
		"salaries": salaries,
		"upkeep": upkeep,
		"expense": expense,
		"net": net,
		"reserve": reserve,
		"alloc": spent,
		"unpaid": unpaid,
		"balance": balance_now,
		"fund": fund,
		"level": lvl,
		"delegated": delegated,
		"cuts": cuts,
	}

	f["balance"] = balance_now
	f["facility_fund"] = fund
	f["facility_level"] = lvl
	f["penalty_weeks"] = penalty
	f["effects"] = {
		"training_pct": _spend_effect(int(spent["training"]),
				"FINANCE_TRAINING_FULL_SPEND", "FINANCE_TRAINING_MAX_PCT"),
		"welfare_pct": _spend_effect(int(spent["welfare"]),
				"FINANCE_WELFARE_FULL_SPEND", "FINANCE_WELFARE_MAX_PCT"),
	}
	f["week_bonus"] = 0
	f["week_wins"] = 0
	f["week_losses"] = 0
	f["week_no"] = week_no
	var hist: Array = f.get("history", [])
	hist.append(entry)
	var keep: int = maxi(1, ConstTable.int_of("FINANCE_HISTORY_WEEKS"))
	while hist.size() > keep:
		hist.pop_front()
	f["history"] = hist

	var out: Dictionary = entry.duplicate(true)
	if cuts.size() > 1 or unpaid > 0:
		out["toast"] = "재무 적자 %s · 긴급 삭감 %d건 — 재무 카드 확인" % [fmt_signed(net), cuts.size()]
	else:
		out["toast"] = "재무 정산 %s · 잔고 %s" % [fmt_signed(net), fmt(balance_now)]
	return out


## Once per consumed player match — accrues the week's performance bonus.
## Playoff / INTL matches pay `FINANCE_TOURNAMENT_MULT` times the league amount.
static func record_match(state: Dictionary, pending_match: Dictionary, won: bool) -> void:
	if bool(pending_match.get("finance_recorded", false)):
		return
	pending_match["finance_recorded"] = true
	var f: Dictionary = _fin(state)
	var amount: int = ConstTable.int_of("FINANCE_MATCH_WIN") if won \
			else ConstTable.int_of("FINANCE_MATCH_LOSS")
	if String(pending_match.get("source", "league")) != "league":
		amount *= maxi(1, ConstTable.int_of("FINANCE_TOURNAMENT_MULT"))
	f["week_bonus"] = int(f.get("week_bonus", 0)) + amount
	var key: String = "week_wins" if won else "week_losses"
	f[key] = int(f.get(key, 0)) + 1


# ── Reads ────────────────────────────────────────────────────────────────────
static func balance(state: Dictionary) -> int:
	return int((state.get("finance", {}) as Dictionary).get("balance", 0))


## Current facility level 1..5. 1 when there is no run state.
static func facility_level(state: Dictionary) -> int:
	return clampi(int((state.get("finance", {}) as Dictionary).get("facility_level", 1)), 1, max_level())


static func facility_fund(state: Dictionary) -> int:
	return int((state.get("finance", {}) as Dictionary).get("facility_fund", 0))


## Latest history entry (last settled week), or {} before the first week end.
static func last_week(state: Dictionary) -> Dictionary:
	var hist: Array = (state.get("finance", {}) as Dictionary).get("history", [])
	return hist.back() if not hist.is_empty() else {}


static func history(state: Dictionary) -> Array:
	return (state.get("finance", {}) as Dictionary).get("history", [])


## Weekly sponsor income at facility `level` — sponsor base × facility `income_pct`
## × trait `income_pct` (M8, `TraitSystem.run_pct_mult`). `settle_week` and
## `projection` both read it so the panel and the settlement cannot disagree.
static func sponsor_income(state: Dictionary, level: int) -> int:
	var f: Dictionary = state.get("finance", {})
	var row: Dictionary = facility_row(level)
	return int(round(float(f.get("sponsor_base", 0)) * float(row.get("income_pct", 100)) / 100.0
			* TraitSystem.run_pct_mult(state, "income_pct")))


## Weekly facility upkeep at `level` × trait `upkeep_pct` (M8).
static func upkeep_cost(state: Dictionary, level: int) -> int:
	return int(round(float(facility_row(level).get("upkeep", 0))
			* TraitSystem.run_pct_mult(state, "upkeep_pct")))


## Surplus weeks settled while the manager ran finance (trait unlock counter, M8).
static func manual_profit_weeks(state: Dictionary) -> int:
	return int((state.get("finance", {}) as Dictionary).get("manual_profit_weeks", 0))


## Weekly fixed cost at the current level — salaries + upkeep.
static func weekly_fixed_cost(state: Dictionary) -> int:
	return StaffSystem.weekly_salary_total(state) + upkeep_cost(state, facility_level(state))


## What the coming week-end settlement looks like so far (bonus accrued to date).
## → `{sponsor, bonus, income, expense, net}`.
static func projection(state: Dictionary) -> Dictionary:
	var f: Dictionary = state.get("finance", {})
	var sponsor: int = sponsor_income(state, facility_level(state))
	var bonus: int = int(f.get("week_bonus", 0))
	var expense: int = weekly_fixed_cost(state)
	return {"sponsor": sponsor, "bonus": bonus, "income": sponsor + bonus,
			"expense": expense, "net": sponsor + bonus - expense}


## Low balance = less than one week of fixed costs left.
static func is_low_balance(state: Dictionary) -> bool:
	return balance(state) < weekly_fixed_cost(state)


static func penalty_weeks(state: Dictionary) -> int:
	return int((state.get("finance", {}) as Dictionary).get("penalty_weeks", 0))


## Effect bonuses active this week (from last week's allocation), in percent.
static func effects(state: Dictionary) -> Dictionary:
	var e: Dictionary = (state.get("finance", {}) as Dictionary).get("effects", {})
	return {"training_pct": float(e.get("training_pct", 0.0)),
			"welfare_pct": float(e.get("welfare_pct", 0.0))}


# ── Multipliers ──────────────────────────────────────────────────────────────
## Training EXP multiplier (facility × training allocation × unpaid penalty).
## `TrainingBoard` multiplies by it.
static func training_exp_mult(state: Dictionary) -> float:
	var m: float = float(facility_row(facility_level(state)).get("train_exp_pct", 100)) / 100.0
	m *= 1.0 + float(effects(state)["training_pct"]) / 100.0
	if penalty_weeks(state) > 0:
		m *= 1.0 - float(ConstTable.int_of("FINANCE_UNPAID_TRAIN_PENALTY_PCT")) / 100.0
	return maxf(0.0, m)


## Mech mastery gain multiplier (facility). `MechMastery` multiplies by it.
static func mastery_mult(state: Dictionary) -> float:
	return float(facility_row(facility_level(state)).get("mastery_pct", 100)) / 100.0


## Incident chance multiplier (facility × welfare allocation). `MentalSystem` multiplies by it.
static func incident_mult(state: Dictionary) -> float:
	var m: float = float(facility_row(facility_level(state)).get("incident_pct", 100)) / 100.0
	m *= 1.0 - float(effects(state)["welfare_pct"]) / 100.0
	return maxf(ConstTable.num("FINANCE_INCIDENT_MULT_MIN"), m)


# ── Allocation ───────────────────────────────────────────────────────────────
## Shares (percent, sum 100) the next settlement uses. Delegated finance =
## the staff's automatic split: even thirds, or half / half between training
## and welfare once the facility is at max level (nothing left to save for).
## Manual = the manager's stored `alloc`.
static func allocation_shares(state: Dictionary) -> Dictionary:
	if StaffSystem.is_delegated(state, "finance"):
		if facility_level(state) >= max_level():
			return {"training": 50, "facility": 0, "welfare": 50}
		return {"training": 34, "facility": 33, "welfare": 33}
	return manual_alloc(state)


static func manual_alloc(state: Dictionary) -> Dictionary:
	var a: Dictionary = (state.get("finance", {}) as Dictionary).get("alloc", DEFAULT_ALLOC)
	var out: Dictionary = {}
	var total: int = 0
	for axis in AXES:
		out[axis] = clampi(int(a.get(axis, 0)), 0, 100)
		total += int(out[axis])
	if total != 100:
		return DEFAULT_ALLOC.duplicate()
	return out


## Manual stepper: `dir` +1 / -1 moves `FINANCE_ALLOC_STEP_PCT` on `axis`.
## Raising takes from the largest other axis (then the next); lowering hands
## the freed share to the facility fund (or to training when lowering the
## fund itself). Sum stays 100. Returns true if anything changed.
static func nudge_allocation(state: Dictionary, axis: String, dir: int) -> bool:
	if not AXES.has(axis) or dir == 0:
		return false
	var a: Dictionary = manual_alloc(state)
	var step: int = maxi(1, ConstTable.int_of("FINANCE_ALLOC_STEP_PCT"))
	if dir > 0:
		var others: Array = []
		for o in AXES:
			if o != axis:
				others.append(o)
		others.sort_custom(func(x, y): return int(a[x]) > int(a[y]))
		var need: int = mini(step, 100 - int(a[axis]))
		var moved: int = 0
		for o in others:
			var take: int = mini(need - moved, int(a[o]))
			a[o] = int(a[o]) - take
			moved += take
			if moved >= need:
				break
		if moved <= 0:
			return false
		a[axis] = int(a[axis]) + moved
	else:
		var give: int = mini(step, int(a[axis]))
		if give <= 0:
			return false
		var to: String = "training" if axis == "facility" else "facility"
		a[axis] = int(a[axis]) - give
		a[to] = int(a[to]) + give
	_fin(state)["alloc"] = a
	return true


# ── Facilities ───────────────────────────────────────────────────────────────
## `{level, upkeep, upgrade_cost, train_exp_pct, mastery_pct, incident_pct,
## income_pct}`; an unknown level falls back to a neutral row.
static func facility_row(level: int) -> Dictionary:
	_ensure_loaded()
	if _facilities.has(level):
		return _facilities[level]
	return {"level": level, "upkeep": 0, "upgrade_cost": 0, "train_exp_pct": 100,
			"mastery_pct": 100, "incident_pct": 100, "income_pct": 100}


static func max_level() -> int:
	_ensure_loaded()
	return _max_level


## Cost of going from the current level to the next; 0 at max level.
static func upgrade_cost(state: Dictionary) -> int:
	var lvl: int = facility_level(state)
	if lvl >= max_level():
		return 0
	return int(facility_row(lvl).get("upgrade_cost", 0))


## Money an upgrade may use — facility fund first, then the balance.
static func upgrade_funds(state: Dictionary) -> int:
	return facility_fund(state) + balance(state)


## "" when the upgrade is possible, otherwise the Korean reason.
static func upgrade_block_reason(state: Dictionary) -> String:
	if facility_level(state) >= max_level():
		return "최고 레벨"
	if upgrade_funds(state) < upgrade_cost(state):
		return "자금 부족"
	return ""


## Upgrades one level, paying from the facility fund first, then the balance.
## Returns "" on success or the reason it was refused.
static func upgrade_facility(state: Dictionary) -> String:
	var why: String = upgrade_block_reason(state)
	if why != "":
		return why
	var f: Dictionary = _fin(state)
	var cost: int = upgrade_cost(state)
	var fund: int = facility_fund(state)
	var from_fund: int = mini(fund, cost)
	f["facility_fund"] = fund - from_fund
	f["balance"] = balance(state) - (cost - from_fund)
	f["facility_level"] = facility_level(state) + 1
	return ""


# ── Formatting ───────────────────────────────────────────────────────────────
## 1234567 → "1,234,567".
static func fmt(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	out = s + out
	return ("−" + out) if n < 0 else out


## Signed: "+360" / "−55" / "±0".
static func fmt_signed(n: int) -> String:
	if n > 0:
		return "+" + fmt(n)
	if n == 0:
		return "±0"
	return fmt(n)


# ── Internal ─────────────────────────────────────────────────────────────────
# The finance dict, initialised lazily for states that never went through
# `init_run` (e.g. a pre-M6 save) — keys missing from a save get defaults.
static func _fin(state: Dictionary) -> Dictionary:
	var f: Dictionary = state.get("finance", {})
	if not f.has("balance") or not f.has("sponsor_base"):
		var keep: Dictionary = f.duplicate(true)
		init_run(state, int(state.get("player_team_id", 0)))
		f = state["finance"]
		for k in keep:
			f[k] = keep[k]
	state["finance"] = f
	return f


# floor(n × pct / 100) without an integer-division warning.
static func _pct_of(n: int, pct: int) -> int:
	return floori(float(n) * float(pct) / 100.0)


# Linear up to the "full" spend, capped: pct = MAX × min(1, spend / FULL).
static func _spend_effect(spend: int, full_key: String, max_key: String) -> float:
	var full: float = maxf(1.0, ConstTable.num(full_key))
	return ConstTable.num(max_key) * clampf(float(spend) / full, 0.0, 1.0)


static func _team_package(team_id: int) -> Dictionary:
	for raw in RunRules.team_packages():
		var t: Dictionary = raw
		if int(t.get("id", -1)) == team_id:
			return t
	return {"budget": 0, "facility_level": 1}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_warning("FinanceSystem: cannot open game.db")
		return
	db.query("SELECT * FROM facilities ORDER BY level")
	for row in db.query_result:
		var lvl: int = int(row["level"])
		_facilities[lvl] = {
			"level": lvl,
			"upkeep": int(row["upkeep"]),
			"upgrade_cost": int(row["upgrade_cost"]),
			"train_exp_pct": int(row["train_exp_pct"]),
			"mastery_pct": int(row["mastery_pct"]),
			"incident_pct": int(row["incident_pct"]),
			"income_pct": int(row["income_pct"]),
		}
		_max_level = maxi(_max_level, lvl)
	db.close_db()
