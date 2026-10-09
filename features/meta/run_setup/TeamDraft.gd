class_name TeamDraft
extends Control

# 런 준비의 **5인 편성** 단계 — 데이터 층. 화면은 자식 `TeamDraftView`.
#
# 예전에는 시즌 씬(`Season.tscn`)의 노드로 살며 `season_state.all_pilots` 에서
# 네임드 25인을 골라 팀 0 과 **맞교환**(`apply_draft`)했다. 지금은 런 준비
# (`RunSetupScreen`)의 마지막 단계라 시즌이 아직 열리지 않았다 — 그래서:
#   - 선수 풀은 `RunSetupScreen` 이 넘겨 주는 **CSV 사본**(`load_match_data()`)에
#     랭크 · 레벨을 얹은 것이다(네임드 전원 = 별, 보유 선수 = 컬렉션 랭크 + 레벨,
#     `RunRules.apply_progress`). 격자에는 그중 **보유 컬렉션**만 선다(`get_pool_grid()`).
#   - 레벨은 **고르지 않는다** — 선수는 컬렉션의 랭크 · 레벨 그대로 런에 들어가고,
#     샐러리도 거기서 나온다. 샐러리캡은 선수 조합만 제약한다.
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
## M8 — trait ids of the chosen manager preset; their `salary_cap` sum moves the cap.
var trait_ids: Array = []

var _pool: Array = []                 # Array[PlayerData] — CSV 사본 40명 (랭크 · 레벨 반영)
var _by_id: Dictionary = {}           # int id → PlayerData
var _owned: Dictionary = {}           # {"<pilot_id>": level} — 보유 컬렉션 (키만 본다)
var _view: TeamDraftView = null


## `RunSetupScreen` 이 단계를 처음 열 때 한 번 부른다.
func setup(pool: Array, owned: Dictionary, p_scenario_id: int) -> void:
	_pool = pool
	_owned = owned.duplicate()
	scenario_id = p_scenario_id
	_by_id.clear()
	for raw in _pool:
		_by_id[(raw as PlayerData).id] = raw


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
		if p.is_mob or not _owned.has(str(p.id)):
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


# ── 랭크 · 레벨 · 샐러리 ──────────────────────────────────────────────────────
## The pilot's level in this run (= collection level; 0 for unknown ids).
func level_of(pilot_id: int) -> int:
	var p: PlayerData = pilot(pilot_id)
	return p.level if p != null else 0


## A **copy** of the pool pilot (rank + level already applied) — the detail popup reads it.
func leveled(pilot_id: int) -> PlayerData:
	var src: PlayerData = pilot(pilot_id)
	return src.duplicate() as PlayerData if src != null else null


func salary_of(pilot_id: int) -> int:
	var p: PlayerData = pilot(pilot_id)
	return RunRules.salary_of(p) if p != null else 0


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
	return RunRules.lineup_salary(picked)


## 편성 검증 — "" 면 시작할 수 있다. 시작이 거절하는 규칙과 같은 함수다.
func validate(pilot_ids: Array) -> String:
	return RunRules.validate_lineup(pilot_ids, scenario_id, _pool, _owned, cap_bonus())


# ─── 파일럿 스킬 ─────────────────────────────────────────────────────────────
## 스킬 타입 표시명. CSV 의 `cooldown` / `charge` / `passive` 를 그대로 띄우면
## 화면에서 읽히지 않는다.
static func skill_type_label(t: String) -> String:
	match t:
		"cooldown": return Loc.t(L.TERM_SKILL_TYPE_COOLDOWN)
		"charge":   return Loc.t(L.TERM_SKILL_TYPE_CHARGE)
		"passive":  return Loc.t(L.TERM_SKILL_TYPE_PASSIVE)
	return t
