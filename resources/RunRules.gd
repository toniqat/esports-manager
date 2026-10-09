class_name RunRules
extends RefCounted

# ── 런 준비 규칙 (M1) — 시나리오 · 팀 패키지 · 선수 랭크 · 레벨 · 샐러리캡 ────
# 런 준비 화면(`features/meta/run_setup/`)과 런 시작(`GameManager.start_run`)이
# **같은 규칙**을 읽도록 한 곳에 모았다. 화면이 "고를 때 보이는 규칙"과 시작이
# "거절하는 규칙"이 갈라지면, 편성 중에는 되던 조합이 시작 버튼에서 막힌다.
#
# Tables: `scenarios.csv` · `pilot_levels.csv` · `pilot_ranks.csv` · `teams.csv` (package
# columns). Opened once on first use and cached (like ConstTable).
#
# Key rule: `levels` / `ranks` dictionaries are **String pilot id → int** so they survive
# the run save (JSON) unchanged.

static var _scenarios: Array = []
static var _levels: Dictionary = {}       # int level (0..) → {stat_bonus, salary_bonus, levelup_cost, exp_required}
static var _ranks: Dictionary = {}        # int pilot_id → Array[{rank, stage, kind, value}] by rank
static var _teams: Array = []
static var _loaded: bool = false


# ── 표 ───────────────────────────────────────────────────────────────────────
## `[{id, name_key, salary_cap, desc_key}]`, id 순. 텍스트는 l10n key
## (`scenario.*.name` / `.desc`) — 화면이 `Loc.t` 로 보인다.
static func scenarios() -> Array:
	_ensure_loaded()
	return _scenarios


## id 로 시나리오 한 행. 없으면 빈 Dictionary.
static func scenario(scenario_id: int) -> Dictionary:
	for s in scenarios():
		if int((s as Dictionary)["id"]) == scenario_id:
			return s
	return {}


static func salary_cap(scenario_id: int) -> int:
	return int(scenario(scenario_id).get("salary_cap", 0))


## Cap including the equipped traits' `salary_cap` bonus (M8). The run setup lineup
## step and `GameManager.start_run` both read this — never `salary_cap` + their own sum.
static func salary_cap_with(scenario_id: int, trait_ids: Array) -> int:
	return maxi(0, salary_cap(scenario_id) + TraitSystem.sum_p1(trait_ids, "salary_cap"))


## 팀 선택 화면용 패키지. `[{id, name_key, short_name_key, budget, facility_level,
## manual_areas: Array[String], desc_key}]`, id 순 — 글자는 l10n key 다(`Loc.t` 로
## 표시, `name.team.*.name` · `name.team.*.short` · `team.*.desc`). M1 은 표시 · 스냅샷만 한다.
static func team_packages() -> Array:
	_ensure_loaded()
	return _teams


## 리그 팀(`teams.csv`) 표시 이름 · 약칭 — 런 밖(정적 화면)용. 런 안에서는 국제전 팀까지
## 아는 `GameManager.team_name` / `team_short_name` 을 쓴다. 없는 id 는 id 그대로.
static func team_name(team_id: int) -> String:
	var key: String = String(_team_package(team_id).get("name_key", ""))
	return str(team_id) if key.is_empty() else Loc.t(key)  # l10n-dynamic: name.team.*.name


static func team_short_name(team_id: int) -> String:
	var key: String = String(_team_package(team_id).get("short_name_key", ""))
	return str(team_id) if key.is_empty() else Loc.t(key)  # l10n-dynamic: name.team.*.short


## 팀 부지 맵 id (`teams.csv` `map_id` → `BaseMap.SCENES` 인덱스). 없는 팀 = 0.
static func team_map_id(team_id: int) -> int:
	return int(_team_package(team_id).get("map_id", 0))


static func _team_package(team_id: int) -> Dictionary:
	for raw in team_packages():
		if int((raw as Dictionary).get("id", -1)) == team_id:
			return raw
	return {}


## `manual_areas` 의 영역 키 → 화면 표기.
static func area_label(area: String) -> String:
	match area:
		"training":  return Loc.t(L.TERM_AREA_TRAINING)
		"knowledge": return Loc.t(L.TERM_AREA_KNOWLEDGE)
		"analysis":  return Loc.t(L.TERM_AREA_ANALYSIS)
		"finance":   return Loc.t(L.TERM_AREA_FINANCE)
	return area


# ── Level (rank-local ladder) ────────────────────────────────────────────────
# A pilot's level runs 0 .. `level_cap(rank)` (= RANK_LEVEL_CAP_PER_RANK × rank) and resets to
# 0 on rank-up. `pilot_levels.csv` (Lv0..50) holds the **absolute** bonus of a level — the same
# table for every rank; CSV pilot values are the Lv0 / rank-0 base.

## Highest level in the table (Lv50).
static func max_level() -> int:
	_ensure_loaded()
	var top: int = 0
	for lv in _levels.keys():
		top = maxi(top, int(lv))
	return top


## Level cap of a rank (`RANK_LEVEL_CAP_PER_RANK` × rank, never above the table). 0 for rank 0.
static func level_cap(rank: int) -> int:
	var per: int = maxi(1, ConstTable.int_of("RANK_LEVEL_CAP_PER_RANK"))
	return mini(max_level(), clampi(rank, 0, rank_max()) * per)


## Stat bonus at `level` over the Lv0 base (added to each of the six stats).
static func stat_bonus_at(level: int) -> int:
	_ensure_loaded()
	return int((_levels.get(level, {}) as Dictionary).get("stat_bonus", 0))


## Salary bonus at `level` over the Lv0 base.
static func salary_bonus_at(level: int) -> int:
	_ensure_loaded()
	return int((_levels.get(level, {}) as Dictionary).get("salary_bonus", 0))


## Levelup currency to go from `level - 1` to `level` (0 at Lv0 / unknown).
static func levelup_cost(level: int) -> int:
	_ensure_loaded()
	return int((_levels.get(level, {}) as Dictionary).get("levelup_cost", 0))


## Cumulative pilot EXP **from Lv0 inside one rank** to reach `level` (`exp_required(0)` = 0).
## The profile's `exp` resets to 0 on rank-up, so this curve restarts every rank.
static func exp_required(level: int) -> int:
	_ensure_loaded()
	return int((_levels.get(level, {}) as Dictionary).get("exp_required", 0))


## Highest level whose `exp_required` ≤ `exp_total` (0 at least). Callers clamp to the cap.
static func level_for_exp(exp_total: int) -> int:
	_ensure_loaded()
	var lv: int = 0
	for k in _levels.keys():
		if exp_total >= exp_required(int(k)):
			lv = maxi(lv, int(k))
	return lv


static func salary_at(base_salary: int, level: int) -> int:
	return base_salary + salary_bonus_at(level)


## Salary of this copy at its current level (rank effects are already folded into
## `pd.salary` by `apply_rank`).
static func salary_of(pd: PlayerData) -> int:
	return salary_at(pd.salary, pd.level)


## Sets `pd` to `level` — raises / lowers the six stats by the bonus **difference** to
## its current `pd.level` and writes `pd.level`. Idempotent. Run copies / run setup pool
## only — CSV values are the Lv0 base.
static func apply_level(pd: PlayerData, level: int) -> void:
	var lv: int = clampi(level, 0, max_level())
	var delta: int = stat_bonus_at(lv) - stat_bonus_at(pd.level)
	if delta != 0:
		for key in PlayerData.STAT_KEYS:
			pd.set(key, maxi(PlayerData.STAT_MIN, int(pd.get(key)) + delta))
	pd.level = lv


## Applies `{"<pilot_id>": level}` to the matching pilots of `pool` (others untouched).
static func apply_levels(pool: Array, levels: Dictionary) -> void:
	for raw in pool:
		var pd := raw as PlayerData
		if levels.has(str(pd.id)):
			apply_level(pd, int(levels[str(pd.id)]))


# ── Rank ─────────────────────────────────────────────────────────────────────
# Rank 1..RANK_MAX. A pilot is acquired at rank = stars (`players.rarity` 1..3);
# breakthrough only raises the max rank (`ProfileManager`). Reaching rank R applies the
# pilot's `pilot_ranks.csv` rows 1..R cumulatively, plus `RANK_SALARY_STEP` salary for
# every rank above the stars (ranks bought with rank stones).

static func rank_max() -> int:
	return maxi(1, ConstTable.int_of("RANK_MAX"))


## Rank stones to reach `rank` from `rank - 1` (`RANK_UP_STONE_R<rank>`). -1 outside 2..RANK_MAX.
static func rank_up_cost(rank: int) -> int:
	if rank < 2 or rank > rank_max():
		return -1
	return maxi(0, ConstTable.int_of("RANK_UP_STONE_R%d" % rank))


## `[{rank, kind, value: String}]` of one pilot, rank order (empty for mobs). Several rows can
## share a rank. Display text = `breakthrough.kind.<kind>` filled from `value`. Each row also
## carries `stage` (= rank) for callers written against the old breakthrough rows.
static func rank_rows(pilot_id: int) -> Array:
	_ensure_loaded()
	return _ranks.get(pilot_id, [])


## Raises `pd` from its current `pd.rank` to `rank` (rows applied once each — calling again
## with the same rank does nothing). Effects: `stat_flat` +v to the six stats, `salary_down`
## −v salary (≥ 0), `stat_growth` +v% to `pd.train_bonus_pct`, `card_swap` "slot:card_id"
## replaces that pilot-card slot; each rank above `pd.rarity` (stars) adds `RANK_SALARY_STEP`.
## Run copies / run setup pool only — never CSV values.
static func apply_rank(pd: PlayerData, rank: int) -> void:
	var target: int = clampi(rank, 0, rank_max())
	if target <= pd.rank:
		return
	for raw in rank_rows(pd.id):
		var r: Dictionary = raw
		var rk: int = int(r["rank"])
		if rk <= pd.rank or rk > target:
			continue
		var v: String = String(r["value"])
		match String(r["kind"]):
			"stat_flat":
				for key in PlayerData.STAT_KEYS:
					pd.set(key, maxi(PlayerData.STAT_MIN, int(pd.get(key)) + int(v)))
			"salary_down":
				pd.salary = maxi(0, pd.salary - int(v))
			"stat_growth":
				pd.train_bonus_pct += int(v)
			"card_swap":
				var parts: PackedStringArray = v.split(":")
				if parts.size() == 2:
					var slot: int = int(parts[0])
					if slot >= 0 and slot < pd.pilot_cards.size():
						pd.pilot_cards[slot] = int(parts[1])
	var step: int = ConstTable.int_of("RANK_SALARY_STEP")
	for rk2 in range(pd.rank + 1, target + 1):
		if rk2 > pd.rarity:
			pd.salary += step
	pd.rank = target


## Applies `{"<pilot_id>": rank}` to the matching pilots of `pool` (others untouched).
static func apply_ranks(pool: Array, ranks: Dictionary) -> void:
	for raw in pool:
		var pd := raw as PlayerData
		var rk: int = int(ranks.get(str(pd.id), 0))
		if rk > 0:
			apply_rank(pd, rk)


## Every named pilot of `pool` at its acquisition rank (= stars) — the strength of a pilot
## nobody ranked up (AI teams, unowned pilots in the run setup pool).
static func apply_base_ranks(pool: Array) -> void:
	for raw in pool:
		var pd := raw as PlayerData
		if not pd.is_mob and pd.rarity > 0:
			apply_rank(pd, pd.rarity)


## Run copies of the whole pool: every named pilot at its stars (`apply_base_ranks`), then
## `ranks` / `levels` (`{"<pid>": int}` — the owned collection) on top. Run setup pool and
## `GameManager.start_run` both build their copies through this sequence.
static func apply_progress(pool: Array, ranks: Dictionary, levels: Dictionary) -> void:
	apply_base_ranks(pool)
	apply_ranks(pool, ranks)
	apply_levels(pool, levels)


## @deprecated — use `rank_max`.
static func breakthrough_max() -> int:
	return rank_max()


## @deprecated — use `rank_rows`.
static func breakthrough_rows(pilot_id: int) -> Array:
	return rank_rows(pilot_id)


## @deprecated — use `apply_rank`.
static func apply_breakthrough(pd: PlayerData, stage: int) -> void:
	apply_rank(pd, stage)


# ── Lineup ───────────────────────────────────────────────────────────────────
## Salary sum of the picked copies at their current level (`salary_of`).
static func lineup_salary(pilots: Array) -> int:
	var total: int = 0
	for raw in pilots:
		total += salary_of(raw as PlayerData)
	return total


## Lineup check. "" when valid, else one translated line.
##   pilot_ids : the five picks (any order)
##   pool      : Array[PlayerData] to look ids up in — copies already at their run rank + level
##               (salary is read from them; there is no level choice)
##   owned     : {"<pilot_id>": anything} — the owned collection (keys only)
##   cap_bonus : M8 — the equipped traits' `salary_cap` sum (`TraitSystem.sum_p1`)
static func validate_lineup(pilot_ids: Array, scenario_id: int, pool: Array,
		owned: Dictionary, cap_bonus: int = 0) -> String:
	if pilot_ids.size() != 5:
		return Loc.t(L.UI_LINEUP_NEED_FIVE, {"n": pilot_ids.size()})
	var by_id: Dictionary = {}
	for raw in pool:
		by_id[(raw as PlayerData).id] = raw
	var seen_roles: Dictionary = {}
	var picked: Array = []
	for pid in pilot_ids:
		var id_i: int = int(pid)
		if not by_id.has(id_i):
			return Loc.t(L.UI_LINEUP_UNKNOWN_PILOT, {"id": id_i})
		if not owned.has(str(id_i)):
			return Loc.t(L.UI_LINEUP_NOT_OWNED, {"name": (by_id[id_i] as PlayerData).name})
		var pd := by_id[id_i] as PlayerData
		if seen_roles.has(pd.role):
			return Loc.t(L.UI_LINEUP_DUPLICATE_POSITION)
		seen_roles[pd.role] = true
		picked.append(pd)
	var cap: int = maxi(0, salary_cap(scenario_id) + cap_bonus)
	var total: int = lineup_salary(picked)
	if cap > 0 and total > cap:
		return Loc.t(L.UI_LINEUP_OVER_CAP, {"total": total, "cap": cap})
	return ""


# ── 로딩 ─────────────────────────────────────────────────────────────────────
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_error("RunRules: cannot open game.db")
		return
	if _has_table(db, "scenarios"):
		db.query("SELECT * FROM scenarios ORDER BY id")
		for row in db.query_result:
			_scenarios.append({
				"id": int(row["id"]), "name_key": String(row["name_key"]),
				"salary_cap": int(row["salary_cap"]), "desc_key": String(row["desc_key"]),
			})
	if _has_table(db, "pilot_levels"):
		db.query("SELECT * FROM pilot_levels ORDER BY level")
		for row in db.query_result:
			_levels[int(row["level"])] = {
				"stat_bonus": int(row["stat_bonus"]),
				"salary_bonus": int(row["salary_bonus"]),
				"levelup_cost": int(row.get("levelup_cost", 0)),
				"exp_required": int(row.get("exp_required", 0)),
			}
	if _levels.is_empty():
		_levels[0] = {"stat_bonus": 0, "salary_bonus": 0}
	if _has_table(db, "pilot_ranks"):
		db.query("SELECT * FROM pilot_ranks ORDER BY pilot_id, rank, id")
		for row in db.query_result:
			var pid: int = int(row["pilot_id"])
			var list: Array = _ranks.get(pid, [])
			list.append({
				"rank": int(row["rank"]), "stage": int(row["rank"]),
				"kind": String(row["kind"]), "value": String(row["value"]),
			})
			_ranks[pid] = list
	db.query("SELECT * FROM teams ORDER BY id")
	for row in db.query_result:
		var areas: Array = []
		for part in String(row.get("manual_areas", "")).split("|", false):
			areas.append((part as String).strip_edges())
		_teams.append({
			"id": int(row["id"]), "name_key": String(row["name_key"]),
			"short_name_key": String(row["short_name_key"]),
			"budget": int(row.get("budget", 0)),
			"facility_level": int(row.get("facility_level", 0)),
			"manual_areas": areas,
			"desc_key": String(row.get("desc_key", "")),
			"map_id": int(row.get("map_id", 0)),
		})
	db.close_db()


static func _has_table(db: SQLite, table: String) -> bool:
	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='%s'" % table)
	return not db.query_result.is_empty()
