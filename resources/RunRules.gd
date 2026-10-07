class_name RunRules
extends RefCounted

# ── 런 준비 규칙 (M1) — 시나리오 · 팀 패키지 · 선수 레벨 · 샐러리캡 ──────────
# 런 준비 화면(`features/meta/run_setup/`)과 런 시작(`GameManager.start_run`)이
# **같은 규칙**을 읽도록 한 곳에 모았다. 화면이 "고를 때 보이는 규칙"과 시작이
# "거절하는 규칙"이 갈라지면, 편성 중에는 되던 조합이 시작 버튼에서 막힌다.
#
# 표: `scenarios.csv` · `pilot_levels.csv` · `teams.csv`(패키지 컬럼). 처음 읽힐
# 때 DB 를 한 번 열어 캐시한다(ConstTable 과 같은 방식).
#
# 레벨 키 규칙: `levels` 딕셔너리는 **문자열 pilot id → int 레벨**이다 — 런
# 세이브(JSON)를 지나도 모양이 같도록.

static var _scenarios: Array = []
static var _levels: Dictionary = {}       # int level → {stat_bonus, salary_bonus, levelup_cost, exp_required}
static var _breakthrough: Dictionary = {} # int pilot_id → Array[{stage, kind, value, desc_key}] by stage
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


# ── 레벨 ─────────────────────────────────────────────────────────────────────
static func max_level() -> int:
	_ensure_loaded()
	var top: int = 1
	for lv in _levels.keys():
		top = maxi(top, int(lv))
	return top


## Lv1 대비 누적 스탯 가산(여섯 스탯 각각에 더한다).
static func stat_bonus_at(level: int) -> int:
	_ensure_loaded()
	return int((_levels.get(level, {}) as Dictionary).get("stat_bonus", 0))


## Lv1 대비 누적 샐러리 가산.
static func salary_bonus_at(level: int) -> int:
	_ensure_loaded()
	return int((_levels.get(level, {}) as Dictionary).get("salary_bonus", 0))


## M10 — levelup currency to raise the max level **to** `level` (0 at Lv1 / unknown).
static func levelup_cost(level: int) -> int:
	_ensure_loaded()
	return int((_levels.get(level, {}) as Dictionary).get("levelup_cost", 0))


## M10 — cumulative pilot exp at which the max level reaches `level` automatically.
static func exp_required(level: int) -> int:
	_ensure_loaded()
	return int((_levels.get(level, {}) as Dictionary).get("exp_required", 0))


## M10 — highest level whose `exp_required` ≤ `exp_total`.
static func level_for_exp(exp_total: int) -> int:
	_ensure_loaded()
	var lv: int = 1
	for k in _levels.keys():
		if exp_total >= exp_required(int(k)):
			lv = maxi(lv, int(k))
	return lv


static func salary_at(base_salary: int, level: int) -> int:
	return base_salary + salary_bonus_at(level)


## 이 선수의 지금 레벨 기준 샐러리.
static func salary_of(pd: PlayerData) -> int:
	return salary_at(pd.salary, pd.level)


## `pd` 를 `level` 로 맞춘다 — 지금 레벨과의 **차이만큼** 여섯 스탯을 올리거나
## 내리고 `pd.level` 을 적는다. 같은 레벨로 다시 불러도 아무 일도 없다.
## 런 사본(`season_state.all_pilots`)에만 쓴다 — CSV 원본 값은 Lv1 기준이다.
static func apply_level(pd: PlayerData, level: int) -> void:
	var lv: int = clampi(level, 1, max_level())
	var delta: int = stat_bonus_at(lv) - stat_bonus_at(pd.level)
	if delta != 0:
		for key in PlayerData.STAT_KEYS:
			pd.set(key, maxi(PlayerData.STAT_MIN, int(pd.get(key)) + delta))
	pd.level = lv


# ── 돌파 (M10) ───────────────────────────────────────────────────────────────
static func breakthrough_max() -> int:
	return maxi(0, ConstTable.int_of("BREAKTHROUGH_MAX"))


## `[{stage, kind, value: String, desc_key}]` (`desc_key` = l10n key `breakthrough.*.desc`) of one pilot, stage order (empty for mobs).
static func breakthrough_rows(pilot_id: int) -> Array:
	_ensure_loaded()
	return _breakthrough.get(pilot_id, [])


## Raises `pd` from its current `pd.breakthrough` to `stage` (cumulative stages,
## applied once each — calling again with the same stage does nothing). Effects:
## `stat_flat` +v to the six stats, `salary_down` −v to the Lv1 salary (≥ 0),
## `stat_growth` +v% to `pd.train_bonus_pct`, `card_swap` "slot:card_id" replaces
## that pilot-card slot. Run copies / run setup pool only — never CSV values.
static func apply_breakthrough(pd: PlayerData, stage: int) -> void:
	var target: int = clampi(stage, 0, breakthrough_max())
	for raw in breakthrough_rows(pd.id):
		var r: Dictionary = raw
		var st: int = int(r["stage"])
		if st <= pd.breakthrough or st > target:
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
	pd.breakthrough = maxi(pd.breakthrough, target)


## Applies `{"<pilot_id>": stage}` to the matching pilots of `pool` (others untouched).
static func apply_breakthroughs(pool: Array, stages: Dictionary) -> void:
	for raw in pool:
		var pd := raw as PlayerData
		var st: int = int(stages.get(str(pd.id), 0))
		if st > 0:
			apply_breakthrough(pd, st)


# ── 편성 ─────────────────────────────────────────────────────────────────────
## 고른 선수들의 샐러리 합. `levels` 에 없는 선수는 Lv1.
static func lineup_salary(pilots: Array, levels: Dictionary) -> int:
	var total: int = 0
	for raw in pilots:
		var pd := raw as PlayerData
		total += salary_at(pd.salary, int(levels.get(str(pd.id), 1)))
	return total


## 편성 검증. 성공이면 "" — 실패면 사람이 읽는 한 줄.
##   pilot_ids        : 고른 5명(순서 무관)
##   levels           : {"<pilot_id>": level}
##   pool             : Array[PlayerData] — id 를 찾을 선수 목록(CSV Lv1 사본)
##   owned_max_levels : {"<pilot_id>": 달성 최대 레벨} — 보유 컬렉션
##   cap_bonus        : M8 — the equipped traits' `salary_cap` sum (`TraitSystem.sum_p1`)
static func validate_lineup(pilot_ids: Array, levels: Dictionary, scenario_id: int,
		pool: Array, owned_max_levels: Dictionary, cap_bonus: int = 0) -> String:
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
		if not owned_max_levels.has(str(id_i)):
			return Loc.t(L.UI_LINEUP_NOT_OWNED, {"name": (by_id[id_i] as PlayerData).name})
		var pd := by_id[id_i] as PlayerData
		if seen_roles.has(pd.role):
			return Loc.t(L.UI_LINEUP_DUPLICATE_POSITION)
		seen_roles[pd.role] = true
		var lv: int = int(levels.get(str(id_i), 1))
		if lv < 1 or lv > int(owned_max_levels[str(id_i)]):
			return Loc.t(L.UI_LINEUP_LEVEL_NOT_ALLOWED, {"name": pd.name, "level": lv})
		picked.append(pd)
	var cap: int = maxi(0, salary_cap(scenario_id) + cap_bonus)
	var total: int = lineup_salary(picked, levels)
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
		_levels[1] = {"stat_bonus": 0, "salary_bonus": 0}
	if _has_table(db, "pilot_breakthrough"):
		db.query("SELECT * FROM pilot_breakthrough ORDER BY pilot_id, stage")
		for row in db.query_result:
			var pid: int = int(row["pilot_id"])
			var list: Array = _breakthrough.get(pid, [])
			list.append({
				"stage": int(row["stage"]), "kind": String(row["kind"]),
				"value": String(row["value"]), "desc_key": String(row["desc_key"]),
			})
			_breakthrough[pid] = list
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
		})
	db.close_db()


static func _has_table(db: SQLite, table: String) -> bool:
	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='%s'" % table)
	return not db.query_result.is_empty()
