class_name TeamDraft
extends Control

# 런 준비의 **5인 편성** 단계 — 데이터 층. 화면은 자식 `TeamDraftView`.
#
# 예전에는 시즌 씬(`Season.tscn`)의 노드로 살며 `season_state.all_pilots` 에서
# 네임드 25인을 골라 팀 0 과 **맞교환**(`apply_draft`)했다. 지금은 런 준비
# (`RunSetupScreen`)의 마지막 단계라 시즌이 아직 열리지 않았다 — 그래서:
#   - 선수 풀은 `RunSetupScreen` 이 넘겨 주는 **CSV Lv1 사본**(`load_match_data()`)
#     이고, 격자에는 그중 **보유 컬렉션**만 선다(`get_pool_grid()` 한 곳).
#   - 칸마다 **레벨**을 고른다(1 ~ 달성 최대 레벨). 레벨은 `levels`
#     (`{"<pilot_id>": int}`)에만 적고 풀의 원본은 건드리지 않는다 — 화면에
#     보이는 레벨 반영 스탯은 `leveled()` 사본이다.
#   - 규칙 검사는 `RunRules.validate_lineup` 하나다 — 시작(`GameManager.start_run`)
#     이 거절하는 규칙과 고를 때 보이는 규칙이 같은 함수에서 나온다.
#   - 맞교환은 사라졌다 — AI 로스터 분배는 `GameManager.start_run` 의 몫이다.

# ─── 슬롯 순서 (탑 · 정글 · 미드 · 원딜 · 서폿) ──────────────────────────────
# 화면의 다섯 칸은 **역할 고정**이고 그 순서는 `GameEnums.ROLE_DISPLAY_ORDER`
# 하나에서 온다 — 인게임 파일럿 스트립도, 밴픽 화면의 양 팀 블록도, 시즌 허브
# 로스터도 같은 표를 읽는다.
const SLOT_ROLES: Array = GameEnums.ROLE_DISPLAY_ORDER

## 역할 → 화면 슬롯 인덱스. `SLOT_ROLES` 의 역인덱스이며, 썸네일을 눌렀을 때
## 그 파일럿이 어느 칸에 앉는지를 정하는 유일한 답이다.
static func slot_of_role(role: int) -> int:
	return SLOT_ROLES.find(role)


## 편성 화면이 위로 올리는 두 요청. 실제 런 시작 · 단계 이동은 `RunSetupScreen`.
signal back_requested
signal start_requested(pilot_ids: Array)

var scenario_id: int = 0
## 고른 레벨 — `{"<pilot_id>": int}`. 보유 선수 전원이 Lv1 로 시작한다.
var levels: Dictionary = {}
## M8 — trait ids of the chosen manager preset; their `salary_cap` sum moves the cap.
var trait_ids: Array = []

var _pool: Array = []                 # Array[PlayerData] — CSV Lv1 사본 40명
var _by_id: Dictionary = {}           # int id → PlayerData
var _owned_max: Dictionary = {}       # {"<pilot_id>": 달성 최대 레벨}
var _view: TeamDraftView = null


## `RunSetupScreen` 이 단계를 처음 열 때 한 번 부른다.
func setup(pool: Array, owned_max_levels: Dictionary, p_scenario_id: int) -> void:
	_pool = pool
	_owned_max = owned_max_levels.duplicate()
	scenario_id = p_scenario_id
	_by_id.clear()
	for raw in _pool:
		_by_id[(raw as PlayerData).id] = raw
	levels.clear()
	for key in _owned_max.keys():
		levels[str(key)] = 1


## 시나리오 단계로 돌아가 캡을 바꾸고 다시 들어왔을 때 — 고른 다섯은 그대로 두고
## 게이지만 다시 그린다.
func set_scenario(p_scenario_id: int) -> void:
	scenario_id = p_scenario_id
	if _view != null:
		_view.refresh_rules()


## The 감독 step's preset traits (set on every entry to the lineup step). The caller
## follows with `set_scenario`, which redraws the gauge.
func set_traits(ids: Array) -> void:
	trait_ids = ids.duplicate()


## Σ `salary_cap` p1 of the equipped traits (0 when none) — the gauge shows it.
func cap_bonus() -> int:
	return TraitSystem.sum_p1(trait_ids, "salary_cap")


func ensure_view() -> void:
	if _view != null:
		return
	_view = TeamDraftView.create()
	add_child(_view)


func view() -> TeamDraftView:
	return _view


# ── 풀 ───────────────────────────────────────────────────────────────────────
## 편성 격자의 칸 목록 — **보유 컬렉션만**, 역할 안에서 종합 스탯 내림차순.
## `[{pilot: PlayerData, role: int, rank: int}]`.
##
## 모브는 수집 대상이 아니므로 보유 목록에 들 일이 없지만, 옛 프로필을 위해
## 여기서도 한 번 더 거른다 — 모브는 AI 팀의 머릿수를 채우는 배경이다.
func get_pool_grid() -> Array:
	var by_role: Dictionary = {0: [], 1: [], 2: [], 3: [], 4: []}
	for p_raw in _pool:
		var p := p_raw as PlayerData
		if p.is_mob or not _owned_max.has(str(p.id)):
			continue
		by_role[int(p.role)].append(p)
	var entries: Array = []
	for r in 5:
		var arr: Array = by_role[r]
		arr.sort_custom(_compare_by_stats)
		for i in arr.size():
			entries.append({"pilot": arr[i], "role": r, "rank": i})
	return entries


func _compare_by_stats(a: PlayerData, b: PlayerData) -> bool:
	return a.stat_total() > b.stat_total()


func pilot(pilot_id: int) -> PlayerData:
	return _by_id.get(pilot_id, null) as PlayerData


# ── 레벨 ─────────────────────────────────────────────────────────────────────
func level_of(pilot_id: int) -> int:
	return int(levels.get(str(pilot_id), 1))


## 이 선수의 달성 최대 레벨(보유하지 않았으면 0).
func max_level_of(pilot_id: int) -> int:
	return int(_owned_max.get(str(pilot_id), 0))


## 레벨을 [1, 달성 최대] 로 잘라 적는다. 실제로 바뀌었으면 true.
func set_level(pilot_id: int, level: int) -> bool:
	var top: int = max_level_of(pilot_id)
	if top <= 0:
		return false
	var lv: int = clampi(level, 1, top)
	if lv == level_of(pilot_id):
		return false
	levels[str(pilot_id)] = lv
	return true


## 고른 레벨이 반영된 **사본** — 스탯 · 샐러리 표시와 상세 팝업이 읽는다.
## 풀의 원본(Lv1)은 그대로 둔다.
func leveled(pilot_id: int) -> PlayerData:
	var src: PlayerData = pilot(pilot_id)
	if src == null:
		return null
	var copy := src.duplicate() as PlayerData
	RunRules.apply_level(copy, level_of(pilot_id))
	return copy


func salary_of(pilot_id: int) -> int:
	var p: PlayerData = pilot(pilot_id)
	if p == null:
		return 0
	return RunRules.salary_at(p.salary, level_of(pilot_id))


# ── 편성 ─────────────────────────────────────────────────────────────────────
func salary_cap() -> int:
	return RunRules.salary_cap_with(scenario_id, trait_ids)


## 고른 선수들(일부여도 된다)의 샐러리 합.
func lineup_salary(pilot_ids: Array) -> int:
	var picked: Array = []
	for pid in pilot_ids:
		var p: PlayerData = pilot(int(pid))
		if p != null:
			picked.append(p)
	return RunRules.lineup_salary(picked, levels)


## 편성 검증 — "" 면 시작할 수 있다. 시작이 거절하는 규칙과 같은 함수다.
func validate(pilot_ids: Array) -> String:
	return RunRules.validate_lineup(pilot_ids, levels, scenario_id, _pool, _owned_max,
			cap_bonus())


# ─── 파일럿 스킬 ─────────────────────────────────────────────────────────────
## 스킬 타입 표시명. CSV 의 `cooldown` / `charge` / `passive` 를 그대로 띄우면
## 화면에서 읽히지 않는다.
static func skill_type_label(t: String) -> String:
	match t:
		"cooldown": return Loc.t(L.TERM_SKILL_TYPE_COOLDOWN)
		"charge":   return Loc.t(L.TERM_SKILL_TYPE_CHARGE)
		"passive":  return Loc.t(L.TERM_SKILL_TYPE_PASSIVE)
	return t
