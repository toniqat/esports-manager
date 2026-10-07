class_name RunSetupScreen
extends Control

# 런 준비 화면(`scenes/RunSetup.tscn`) — 오케스트레이터.
# 시나리오 → 팀 → 감독(프리셋 · 특성) → 5인 편성(레벨 · 샐러리캡) → `GameManager.start_run(run_setup)`
# → `Season.tscn`(HUB 부터). 계약: `docs/outgame_dev_plan.md` §10.2.
#
# **단계는 표 하나(`STEPS`)다.** 맨 위 단계 머리글도, `뒤로` / `다음` 의 이동도
# 이 표의 순서를 따른다 — 감독 프리셋 단계(M3/M9)는 이 표에 한 줄과 그 단계의
# 뷰를 만드는 분기 하나를 더하면 끼어든다(`_make_step_view`).
#
# 각 단계 뷰는 처음 들어갈 때 한 번 만들고 그 뒤로는 숨겼다 보인다 — 팀 단계로
# 돌아갔다 와도 편성에서 고른 다섯과 레벨이 남는다.
#
# **모양의 정본은 `scenes/RunSetup.tscn`** (바탕 · 머리글 줄 · 단계 본문 자리 `%Steps` ·
# 오류 줄) 과 각 단계 뷰의 `.tscn`. 이 스크립트는 안전 영역 들여쓰기(Pattern B), 머리글
# 알약(`StepChip`)을 `STEPS` 수만큼 세우고 상태 색을 칠하는 일, 단계 이동 · 런 시작만 한다.

const LOBBY_SCENE: String = "res://scenes/Lobby.tscn"
const SEASON_SCENE: String = "res://scenes/Season.tscn"

## 단계 표. `id` 는 `_make_step_view` 의 분기 키, `label` 은 머리글 글자.
const STEPS: Array = [
	{"id": "scenario", "label": "시나리오"},
	{"id": "team",     "label": "팀"},
	{"id": "manager",  "label": "감독"},    # M8/M9 — preset + traits (ManagerStepView)
	{"id": "lineup",   "label": "편성"},
]

# ─── 머리글 (단계 표시) ──────────────────────────────────────────────────────
# 머리글 줄의 자리 · 크기는 씬(`%Header`, y 28 · 높이 64)이 정한다. 단계 본문은
# 그 아랫변 + 24 에서 시작한다 — 단계 뷰 씬들의 첫 블록이 그 y(116)에 놓여 있다.
const CONTENT_TOP: float = 116.0


## 단계 본문이 시작하는 y(화면째 안전 영역으로 내린 좌표계). 단계 뷰 씬의 첫 블록 자리와 같다.
static func content_top() -> float:
	return CONTENT_TOP


@onready var _gm: Node = get_node("/root/GameManager")
@onready var _pm: Node = get_node("/root/ProfileManager")

var scenario_id: int = -1
var team_id: int = -1
## Manager preset chosen on the 감독 step (-1 = active preset — `start_run` resolves it).
var manager_preset: int = -1
var _manager_view: ManagerStepView = null

var _step: int = -1
var _views: Dictionary = {}          # step id → Control
var _header_chips: Array = []        # Array[StepChip]
var _draft: TeamDraft = null
var _pool: Array = []                # CSV Lv1 사본 (load_match_data)
var _load_error: String = ""
var _built: bool = false


func _ready() -> void:
	if _built:
		return
	_built = true
	# 화면째 안전 영역 위끝으로 내린다(Pattern B) — 단계 뷰들은 그 안의 좌표로 산다.
	# 바탕만 노치 띠까지 위로 늘린다.
	ScreenMetrics.indent_to_safe_top(self)
	ScreenMetrics.extend_background(%Background)
	_build_header()
	(%ErrorLabel as Control).visible = false

	# 선수 풀은 시즌이 열리기 전이라 `season_state` 가 아니라 CSV 사본에서 온다.
	var data: Dictionary = _gm.load_match_data()
	if data.has("error"):
		_load_error = String(data["error"])
	else:
		_pool = data["players"]
		# M10 — owned pilots show (and are capped) at their breakthrough stage.
		RunRules.apply_breakthroughs(_pool, _pm.owned_breakthroughs())
	go_to_step(0)


# ── 단계 이동 ────────────────────────────────────────────────────────────────
func step_count() -> int:
	return STEPS.size()


func current_step_id() -> String:
	return String((STEPS[_step] as Dictionary)["id"]) if _step >= 0 else ""


func go_to_step(i: int) -> void:
	if i < 0:
		get_tree().change_scene_to_file(LOBBY_SCENE)
		return
	if i >= STEPS.size():
		return
	var id: String = String((STEPS[i] as Dictionary)["id"])
	if not _views.has(id):
		var v: Control = _make_step_view(id)
		if v == null:
			return
		_views[id] = v
	for key in _views.keys():
		(_views[key] as Control).visible = key == id
	_step = i
	_on_step_entered(id)
	_refresh_header()


func _next_step() -> void:
	go_to_step(_step + 1)


func _prev_step() -> void:
	go_to_step(_step - 1)


## 단계 id → 그 단계의 뷰. **새 단계는 여기에 분기 하나를 더한다.**
func _make_step_view(id: String) -> Control:
	match id:
		"scenario":
			var sv := ScenarioStepView.create()
			%Steps.add_child(sv)
			sv.back_requested.connect(_prev_step)
			sv.next_requested.connect(_on_scenario_next.bind(sv))
			return sv
		"team":
			var tv := TeamStepView.create()
			%Steps.add_child(tv)
			tv.back_requested.connect(_prev_step)
			tv.next_requested.connect(_on_team_next.bind(tv))
			return tv
		"manager":
			_manager_view = ManagerStepView.create()
			%Steps.add_child(_manager_view)
			_manager_view.back_requested.connect(_prev_step)
			_manager_view.next_requested.connect(_on_manager_next)
			return _manager_view
		"lineup":
			_draft = TeamDraft.new()
			_draft.set_anchors_preset(Control.PRESET_FULL_RECT)
			_draft.setup(_pool, _pm.owned_max_levels(), maxi(0, scenario_id))
			%Steps.add_child(_draft)
			_draft.ensure_view()
			_draft.back_requested.connect(_prev_step)
			_draft.start_requested.connect(_on_start_requested)
			return _draft
	push_error("RunSetupScreen: unknown step '%s'" % id)
	return null


func _on_step_entered(id: String) -> void:
	(%ErrorLabel as Control).visible = false
	if id == "lineup":
		if _draft != null:
			# Trait `salary_cap` moves the cap — set before the scenario redraws the gauge.
			_draft.set_traits(manager_traits())
			_draft.set_scenario(scenario_id)
		if _load_error != "":
			_show_error("선수 데이터를 읽지 못했습니다: " + _load_error)


func _on_scenario_next(view: ScenarioStepView) -> void:
	scenario_id = view.selected_id
	_next_step()


func _on_team_next(view: TeamStepView) -> void:
	team_id = view.selected_id
	_next_step()


func _on_manager_next() -> void:
	manager_preset = _manager_view.preset_idx
	_next_step()


## Trait ids of the chosen preset (empty before the 감독 step was built).
func manager_traits() -> Array:
	return _manager_view.selected_traits() if _manager_view != null else []


# ── 런 시작 ──────────────────────────────────────────────────────────────────
## 계약 §10.2 의 `run_setup`. `pilot_ids` 는 `GameEnums.Role` 순, 레벨 키는 문자열.
func build_run_setup(pilot_ids: Array) -> Dictionary:
	var levels: Dictionary = {}
	for pid in pilot_ids:
		levels[str(int(pid))] = _draft.level_of(int(pid))
	var ids: Array = []
	for pid in pilot_ids:
		ids.append(int(pid))
	return {
		"scenario": scenario_id,
		"team_id": team_id,
		"pilot_ids": ids,
		"pilot_levels": levels,
		"salary_cap": RunRules.salary_cap_with(scenario_id, manager_traits()),
		"salary_total": _draft.lineup_salary(ids),
		# M9 — profile preset index; `GameManager.start_run` validates and snapshots it.
		"preset": manager_preset,
	}


## 편성 화면의 `게임 시작`. 규칙은 이미 통과했다(뷰가 암전 전에 검사) — 여기서는
## 암전 → 가짜 로딩 → 밝아짐(`SceneFade`) 뒤에서 런을 연다. 덮개는 root 의
## CanvasLayer 라 씬이 바뀌어도 남아 Season 의 첫 HUB 위에서 걷힌다.
func _on_start_requested(pilot_ids: Array) -> void:
	var run_setup: Dictionary = build_run_setup(pilot_ids)
	SceneFade.play(get_tree(), _commit_start.bind(run_setup))


## 화면이 다 가려진 순간 — 런 시작 + 씬 전환. 실패면 덮개가 걷히며 오류가 보인다.
func _commit_start(run_setup: Dictionary) -> void:
	if _draft != null and _draft.view() != null:
		_draft.view().close_detail()
	var err: String = start_run(run_setup)
	if err != "":
		if _draft != null and _draft.view() != null:
			_draft.view().show_start_error(err)
		Haptics.play(Haptics.Kind.ERROR)
		return
	get_tree().change_scene_to_file(SEASON_SCENE)


## `GameManager.start_run` — 그쪽이 같은 `RunRules.validate_lineup` 으로 다시 막는다.
func start_run(run_setup: Dictionary) -> String:
	return String(_gm.start_run(run_setup))


func _show_error(msg: String) -> void:
	var lbl: Label = %ErrorLabel
	lbl.text = msg
	lbl.visible = true


# ── 머리글 ───────────────────────────────────────────────────────────────────
## 알약 한 칸씩 `STEPS` 수만큼 — 자리 · 간격 · 높이는 씬의 `%Header` 줄이 정한다.
func _build_header() -> void:
	var row: Control = %Header
	for i in STEPS.size():
		var chip := StepChip.create()
		row.add_child(chip)
		chip.set_text("%d  %s" % [i + 1, String((STEPS[i] as Dictionary)["label"])])
		_header_chips.append(chip)


## 지난 단계 = 옅은 앰버, 지금 = 앰버 색면, 남은 단계 = 흰 판.
func _refresh_header() -> void:
	for i in _header_chips.size():
		var chip: StepChip = _header_chips[i]
		var bg: Color = OutgameTheme.SURFACE
		var fg: Color = OutgameTheme.TEXT_FAINT
		if i == _step:
			bg = OutgameTheme.ACCENT
			fg = OutgameTheme.TEXT_ON_FILL
		elif i < _step:
			bg = OutgameTheme.ACCENT_DIM
			fg = OutgameTheme.ACCENT_TEXT
		chip.paint(bg, fg, OutgameTheme.BORDER if i > _step else null)
