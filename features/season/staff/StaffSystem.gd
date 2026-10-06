class_name StaffSystem
extends RefCounted

# ── 감독 · 스태프 유효 스탯 (M3) — 런 안의 단일 진입점 ────────────────────────
# 감독 스탯을 읽는 모든 자리는 `effective(state, stat)` 하나를 거친다
# (`docs/outgame_dev_plan.md` §2.3 · §11).
#
#   effective(stat) = max(감독[stat] + 일시 보정, 어시스턴트[stat], 담당 일반 스태프[stat])
#
# - 일반 스태프는 **분야당 1명**(`JOB_STAT`), 어시스턴트 매니저는 팀에 1명이고
#   여러 스탯을 동시에 메운다. 여러 빈자리를 메우는 것은 감독과 어시스턴트뿐.
# - 멘탈은 예외: 면담 · 외출은 `manager_value(state, "mental")`(감독 값만),
#   사건 처리만 `effective_for_incident`(누구든 가장 높은 멘탈).
# - `owner(state, stat)` 이 "manager" 가 아니면 그 영역은 **위임**된 것이다 —
#   화면이 자동 버튼(훈련 자동 편성 · 연구 자동 지정 · 분석 해석 · 예산 자동
#   배분)을 보여 주는 근거(`is_delegated`).
#
# 입력은 언제나 `season_state` 딕셔너리다(오토로드에 기대지 않는다 — 헤드리스
# 단위 확인을 위해). 스냅샷은 런 시작 때 `snapshot_for_run` 이 `run_setup` 에
# 고정한다: `run_setup.manager_type` / `.manager_stats` / `.staff`.

const STATS: Array = ["training", "tactics", "knowledge", "mental", "analysis", "finance"]
const STAT_LABELS: Dictionary = {
	"training": "훈련", "tactics": "전술", "knowledge": "지식",
	"mental": "멘탈", "analysis": "분석", "finance": "관리",
}
const STAT_MIN: int = 1
const STAT_MAX: int = 20

## 일반 스태프 직업 → 맡는 스탯. 어시스턴트(`assistant`)는 여기 없다 — 전 스탯.
const JOB_STAT: Dictionary = {
	"coach_training": "training",
	"coach_tactics": "tactics",
	"coach_knowledge": "knowledge",
	"analyst": "analysis",
	"finance": "finance",
}
const JOB_ASSISTANT: String = "assistant"
const JOB_LABELS: Dictionary = {
	"assistant": "어시스턴트 매니저",
	"coach_training": "훈련 코치",
	"coach_tactics": "전술 코치",
	"coach_knowledge": "메크 코치",
	"analyst": "분석가",
	"finance": "예산 관리자",
}

const OWNER_MANAGER: String = "manager"
const OWNER_ASSISTANT: String = "assistant"
const OWNER_STAFF: String = "staff"

static var _types: Array = []          # manager_types 행
static var _staff: Dictionary = {}     # int id → staff 행 {id, name, job, stats{}, salary}
static var _team_staff: Dictionary = {}  # int team_id → Array[int] staff ids
static var _loaded: bool = false


# ── 표 ───────────────────────────────────────────────────────────────────────
## `[{id, name, gender, stats{stat: int}, desc}]`, id 순.
static func manager_types() -> Array:
	_ensure_loaded()
	return _types


static func manager_type_row(type_id: int) -> Dictionary:
	for t in manager_types():
		if int((t as Dictionary)["id"]) == type_id:
			return t
	return {}


## `{id, name, job, stats{stat: int}, salary}`. 없으면 빈 Dictionary.
static func staff_row(staff_id: int) -> Dictionary:
	_ensure_loaded()
	return _staff.get(staff_id, {})


static func team_staff_ids(team_id: int) -> Array:
	_ensure_loaded()
	return (_team_staff.get(team_id, []) as Array).duplicate()


# ── 런 스냅샷 ────────────────────────────────────────────────────────────────
## 런 시작 때 `run_setup` 에 합칠 조각. 감독 스탯은 타입 초기값(M9 전까지
## 전문화 분배 없음), 스태프는 팀의 초기 스태프 그대로(런 중 이탈 없음).
## → `{manager_type, manager_stats{stat: int}, staff: [{id, name, job, stats{}, salary}]}`
static func snapshot_for_run(team_id: int, manager_type: int) -> Dictionary:
	var row: Dictionary = manager_type_row(manager_type)
	if row.is_empty() and not manager_types().is_empty():
		row = manager_types()[0]
	var mstats: Dictionary = {}
	for s in STATS:
		mstats[s] = clampi(int((row.get("stats", {}) as Dictionary).get(s, STAT_MIN)), STAT_MIN, STAT_MAX)
	var staff: Array = []
	for sid in team_staff_ids(team_id):
		var e: Dictionary = staff_row(int(sid))
		if not e.is_empty():
			staff.append(e.duplicate(true))
	return {
		"manager_type": int(row.get("id", manager_type)),
		"manager_stats": mstats,
		"staff": staff,
	}


# ── 판정 ─────────────────────────────────────────────────────────────────────
## 감독의 스냅샷 값(보정 전).
static func manager_base(state: Dictionary, stat: String) -> int:
	var setup: Dictionary = state.get("run_setup", {})
	var m: Dictionary = setup.get("manager_stats", {})
	return int(m.get(stat, STAT_MIN))


## 이 스탯에 걸린 일시 보정의 합(`staff_mods`).
static func mod_total(state: Dictionary, stat: String) -> int:
	var total: int = 0
	for raw in (state.get("staff_mods", []) as Array):
		var m: Dictionary = raw
		if String(m.get("stat", "")) == stat:
			total += int(m.get("delta", 0))
	return total


## 감독 값 = 스냅샷 + 일시 보정, [STAT_MIN, STAT_MAX].
static func manager_value(state: Dictionary, stat: String) -> int:
	return clampi(manager_base(state, stat) + mod_total(state, stat), STAT_MIN, STAT_MAX)


## 어시스턴트 매니저 한 명(없으면 빈 Dictionary).
static func assistant(state: Dictionary) -> Dictionary:
	for raw in _run_staff(state):
		var e: Dictionary = raw
		if String(e.get("job", "")) == JOB_ASSISTANT:
			return e
	return {}


## 이 스탯 전담 일반 스태프(분야당 1명, 없으면 빈 Dictionary).
static func staff_for(state: Dictionary, stat: String) -> Dictionary:
	for raw in _run_staff(state):
		var e: Dictionary = raw
		if String(JOB_STAT.get(String(e.get("job", "")), "")) == stat:
			return e
	return {}


static func effective(state: Dictionary, stat: String) -> int:
	return int(_best(state, stat)["value"])


## 누가 이 스탯을 맡는가 — "manager" / "assistant" / "staff". 같은 값이면
## 스태프 → 어시스턴트 → 감독 순으로 넘긴다(위임이 되는 쪽이 이긴다 — 같은
## 결과라면 손이 덜 가는 편).
static func owner(state: Dictionary, stat: String) -> String:
	return String(_best(state, stat)["owner"])


## 담당자의 표시 이름(감독이면 "감독").
static func owner_name(state: Dictionary, stat: String) -> String:
	var b: Dictionary = _best(state, stat)
	if String(b["owner"]) == OWNER_MANAGER:
		return "감독"
	return String((b["who"] as Dictionary).get("name", "—"))


## 위임되었는가 — 자동 버튼을 보일지의 근거.
static func is_delegated(state: Dictionary, stat: String) -> bool:
	return owner(state, stat) != OWNER_MANAGER


## 사건 처리 멘탈 — 감독(보정 포함) · 어시스턴트 · **아무 스태프**의 멘탈 중 최댓값.
static func effective_for_incident(state: Dictionary) -> int:
	var v: int = manager_value(state, "mental")
	for raw in _run_staff(state):
		v = maxi(v, int(((raw as Dictionary).get("stats", {}) as Dictionary).get("mental", 0)))
	return v


## 스태프 주급 합(재무 지출).
static func weekly_salary_total(state: Dictionary) -> int:
	var total: int = 0
	for raw in _run_staff(state):
		total += int((raw as Dictionary).get("salary", 0))
	return total


## 분석 공개 단계 0..3 — `ANALYSIS_TIER_1..3`(const.csv) 문턱을 넘은 수.
## 0 = 이름 · 역할, 1 = + 스탯(대략), 2 = + 숙련도 상위 메크, 3 = + 파일럿 카드.
static func analysis_tier(state: Dictionary) -> int:
	var v: int = effective(state, "analysis")
	var tier: int = 0
	for i in range(1, 4):
		if v >= ConstTable.int_of("ANALYSIS_TIER_%d" % i):
			tier = i
	return tier


# ── 일시 보정 ────────────────────────────────────────────────────────────────
## 감독 스탯 일시 보정. `weeks` 주 동안(주 마감마다 1 줄어 0 이면 사라진다).
static func add_mod(state: Dictionary, stat: String, delta: int, weeks: int, source: String = "") -> void:
	if not STATS.has(stat) or delta == 0 or weeks <= 0:
		return
	var mods: Array = state.get("staff_mods", [])
	mods.append({"stat": stat, "delta": delta, "weeks_left": weeks, "source": source})
	state["staff_mods"] = mods


## 주 마감(`SeasonHub._end_week`)에 한 번.
static func decay_mods(state: Dictionary) -> void:
	var kept: Array = []
	for raw in (state.get("staff_mods", []) as Array):
		var m: Dictionary = (raw as Dictionary).duplicate()
		m["weeks_left"] = int(m.get("weeks_left", 0)) - 1
		if int(m["weeks_left"]) > 0:
			kept.append(m)
	state["staff_mods"] = kept


# ── 내부 ─────────────────────────────────────────────────────────────────────
static func _run_staff(state: Dictionary) -> Array:
	return (state.get("run_setup", {}) as Dictionary).get("staff", [])


# {value, owner, who} — 스태프 → 어시스턴트 → 감독 순으로 동점을 가져간다.
static func _best(state: Dictionary, stat: String) -> Dictionary:
	var best: Dictionary = {"value": manager_value(state, stat), "owner": OWNER_MANAGER, "who": {}}
	var asst: Dictionary = assistant(state)
	if not asst.is_empty():
		var av: int = int((asst.get("stats", {}) as Dictionary).get(stat, 0))
		if av >= int(best["value"]):
			best = {"value": av, "owner": OWNER_ASSISTANT, "who": asst}
	var st: Dictionary = staff_for(state, stat)
	if not st.is_empty():
		var sv: int = int((st.get("stats", {}) as Dictionary).get(stat, 0))
		if sv >= int(best["value"]):
			best = {"value": sv, "owner": OWNER_STAFF, "who": st}
	return best


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_warning("StaffSystem: cannot open game.db")
		return
	db.query("SELECT * FROM manager_types ORDER BY id")
	for row in db.query_result:
		_types.append({
			"id": int(row["id"]), "name": String(row["name"]),
			"gender": String(row["gender"]), "stats": _stats_of(row),
			"desc": String(row["desc"]),
		})
	db.query("SELECT * FROM staff ORDER BY id")
	for row in db.query_result:
		_staff[int(row["id"])] = {
			"id": int(row["id"]), "name": String(row["name"]),
			"job": String(row["job"]), "stats": _stats_of(row),
			"salary": int(row["salary"]),
		}
	db.query("SELECT id, staff_ids FROM teams ORDER BY id")
	for row in db.query_result:
		var ids: Array = []
		for part in String(row.get("staff_ids", "")).split("|", false):
			if (part as String).strip_edges().is_valid_int():
				ids.append(int(part))
		_team_staff[int(row["id"])] = ids
	db.close_db()


static func _stats_of(row: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for s in STATS:
		out[s] = int(row.get(s, STAT_MIN))
	return out
