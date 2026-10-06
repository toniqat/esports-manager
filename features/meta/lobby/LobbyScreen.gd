extends Control

# 프로젝트 진입점 — 로비. 세이브는 프로필 1 + 런 1 이라 슬롯 고르기가 없다.
# 진행 중인 런이 있으면 그 요약 카드와 `새 런`(1) / `이어하기`(2) 하단 바,
# 없으면 빈 상태 한 줄과 전폭 `새 런` 하나.
#
# `새 런` 을 누를 때 런이 이미 있으면 **포기 확인 모달**(`ConfirmPopup`)을
# 띄운다 — 확인하면 그 런을 **포기로 정산**(`RunResult.settle_current_run("abandon")`,
# 실패 정산이지만 보상은 준다)하고 정산 화면으로 간다. 그 화면의 `새 런` 이
# 런 준비로 잇는다.
#
# 이후 마일스톤에서 런 카드 아래에 메뉴 진입점(컬렉션 / 감독 / 특성 / 상점)이
# 붙는다 — 그때 `_build_menu()` 같은 구획을 하나 더 세운다. 지금은 비워 둔다.

const PHASE_NAMES: Dictionary = HubView.PHASE_NAMES
const WEEKDAY_NAMES: Array = OutgameTheme.DAY_LETTERS

const RUN_SETUP_SCENE: String = "res://scenes/RunSetup.tscn"

const CARD_X: float = 80.0
const CARD_W: float = 920.0
const CARD_TOP: float = 420.0
const CARD_H: float = 400.0
const EMPTY_CARD_H: float = 220.0
const CARD_PAD: float = 44.0

@onready var _gm: Node = get_node("/root/GameManager")
@onready var _pm: Node = get_node("/root/ProfileManager")

var _has_run: bool = false
var _meta: Dictionary = {}
var _toast_lbl: Label
var _confirm: ConfirmPopup
var _manager_popup: ManagerTypePopup = null
var _built: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 로비를 거쳐 들어간 시즌은 진짜 런 파일에 저장한다. 에디터에서 Season /
	# MatchFlow 를 바로 실행하면 기본값(true)이 남아 숨은 테스트 런에 쓴다.
	_gm.use_test_run = false
	_has_run = SaveSystem.has_run()
	_meta = SaveSystem.read_run_meta() if _has_run else {}
	if not _built:
		_build()
		_built = true


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 제목이 깔리지 않게. 제목만 따로 내리면 본문과 겹친다.
	ScreenMetrics.indent_to_safe_top(self)
	# 배경만은 안전 영역 밖(노치 자리)까지 덮는다(`add_background` 안에서).
	OutgameTheme.add_background(self)

	var vp_w: float = ScreenMetrics.vp_w()
	UiHelpers.mk_label(self, "ESPORTS MANAGER", 64, OutgameTheme.TEXT,
			Vector2(0, 170), Vector2(vp_w, 88), HORIZONTAL_ALIGNMENT_CENTER)
	# 제목 밑 앰버 짧은 띠 — 강조는 색면 하나로만.
	var rule := ColorRect.new()
	rule.color = OutgameTheme.ACCENT
	rule.position = Vector2(ScreenMetrics.center_x() - 40.0, 272)
	rule.size = Vector2(80, 6)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)

	UiHelpers.mk_label(self, "진행 중인 런", 24, OutgameTheme.TEXT_SUB,
			Vector2(_card_x(), CARD_TOP - 50.0), Vector2(CARD_W, 34))
	if _has_run and not _meta.is_empty():
		_build_run_card()
	else:
		_build_empty_card()

	# 하단 바 바로 위 — 실패 메시지 한 줄. 바보다 위라 제스처 띠와 겹치지 않는다.
	_toast_lbl = UiHelpers.mk_label(self, "", 24, OutgameTheme.NEGATIVE,
			Vector2(0, OutgameTheme.bottom_bar_top() - 64.0),
			Vector2(vp_w, 34), HORIZONTAL_ALIGNMENT_CENTER)

	_build_bottom_bar()

	_confirm = ConfirmPopup.new()
	add_child(_confirm)
	_confirm.confirmed.connect(_on_abandon_confirmed)

	# First lobby of a profile: the manager type must be chosen before anything
	# else (plan §11.0). The popup can't be dismissed without choosing.
	if not _pm.manager_type_chosen():
		_manager_popup = ManagerTypePopup.new()
		add_child(_manager_popup)
		_manager_popup.chosen.connect(_on_manager_type_chosen)
		_manager_popup.open()


## 태블릿처럼 뷰포트가 1080 보다 넓으면 카드도 가운데로.
func _card_x() -> float:
	return maxf(CARD_X, ScreenMetrics.center_x() - CARD_W * 0.5)


func _build_run_card() -> void:
	var card: Panel = OutgameTheme.add_card(self, Vector2(_card_x(), CARD_TOP),
			Vector2(CARD_W, CARD_H), 24)
	var inner_w: float = CARD_W - CARD_PAD * 2.0

	UiHelpers.mk_label(card, _phase_name(int(_meta.get("phase", 0))), 36,
			OutgameTheme.TEXT, Vector2(CARD_PAD, CARD_PAD - 4.0),
			Vector2(inner_w, 50))
	if bool(_meta.get("match_in_progress", false)):
		var chip_w: float = 170.0
		OutgameTheme.add_chip(card, "경기 진행 중",
				Vector2(CARD_W - CARD_PAD - chip_w, CARD_PAD + 2.0),
				Vector2(chip_w, 40), OutgameTheme.ACCENT_DIM,
				OutgameTheme.ACCENT_TEXT, 20)
	UiHelpers.mk_label(card, "%d년 %d월 %d일 (%s)" % [
				int(_meta.get("year", 1)),
				int(_meta.get("month", 12)),
				int(_meta.get("day", 1)),
				_weekday_name(int(_meta.get("weekday", 0))),
			], 24, OutgameTheme.TEXT_SUB,
			Vector2(CARD_PAD, CARD_PAD + 54.0), Vector2(inner_w, 34))

	OutgameTheme.add_divider(card, Vector2(CARD_PAD, CARD_PAD + 112.0), inner_w)

	UiHelpers.mk_label(card, String(_meta.get("team_name", "—")), 32,
			OutgameTheme.TEXT, Vector2(CARD_PAD, CARD_PAD + 136.0),
			Vector2(inner_w, 44))
	UiHelpers.mk_label(card, "우승 트로피 %d개" % int(_meta.get("trophies", 0)),
			24, OutgameTheme.ACCENT_TEXT,
			Vector2(CARD_PAD, CARD_PAD + 188.0), Vector2(inner_w, 34))
	var rank: int = int(_meta.get("rank", 0))
	var record: String = "리그 미시작"
	if rank > 0:
		record = "현재 리그 %d위 (%d승 %d패)" % [
			rank, int(_meta.get("wins", 0)), int(_meta.get("losses", 0)),
		]
	UiHelpers.mk_label(card, record, 24, OutgameTheme.TEXT,
			Vector2(CARD_PAD, CARD_PAD + 230.0), Vector2(inner_w, 34))

	UiHelpers.mk_label(card, "마지막 저장 " + String(_meta.get("saved_at", "")),
			20, OutgameTheme.TEXT_FAINT,
			Vector2(CARD_PAD, CARD_H - CARD_PAD - 28.0), Vector2(inner_w, 30),
			HORIZONTAL_ALIGNMENT_RIGHT)


func _build_empty_card() -> void:
	var card: Panel = OutgameTheme.add_card(self, Vector2(_card_x(), CARD_TOP),
			Vector2(CARD_W, EMPTY_CARD_H), 24)
	var l1 := UiHelpers.mk_label(card, "진행 중인 런이 없습니다", 30,
			OutgameTheme.TEXT_SUB, Vector2(0, 58), Vector2(CARD_W, 44),
			HORIZONTAL_ALIGNMENT_CENTER)
	l1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiHelpers.mk_label(card, "아래 '새 런' 으로 시즌을 시작하세요", 22,
			OutgameTheme.TEXT_FAINT, Vector2(0, 112), Vector2(CARD_W, 34),
			HORIZONTAL_ALIGNMENT_CENTER)


func _build_bottom_bar() -> void:
	# 런이 있으면 하단 구간을 1:2 로 나눈다 — 이어하기가 주 행동이라 오른쪽
	# 3분의 2, 새 런은 왼쪽 3분의 1. 없으면 새 런이 곧 주 행동이라 전폭.
	if _has_run:
		var bar: Array = OutgameTheme.add_bottom_bar(self, [
			{"text": "새 런",    "style": "ghost",   "font": 32, "weight": 1.0},
			{"text": "이어하기", "style": "primary", "font": 32, "weight": 2.0},
		])
		(bar[0] as Button).pressed.connect(_on_new_run_pressed)
		(bar[1] as Button).pressed.connect(_on_continue_pressed)
		# 런이 있을 때의 새 런은 `_on_new_run_pressed` 가 WARNING 을 직접 낸다 —
		# 자동 배선까지 울리면 한 누름에 두 번 떤다.
		HapticUi.mute(bar[0])
	else:
		var bar1: Array = OutgameTheme.add_bottom_bar(self, [
			{"text": "새 런", "style": "primary", "font": 32, "weight": 1.0},
		])
		(bar1[0] as Button).pressed.connect(_on_new_run_pressed)


func _phase_name(phase: int) -> String:
	return String(PHASE_NAMES.get(phase, "—"))


func _weekday_name(wd: int) -> String:
	if wd >= 0 and wd < WEEKDAY_NAMES.size():
		return String(WEEKDAY_NAMES[wd])
	return "?"


# ── Button handlers ──────────────────────────────────────────────────────────
func _on_continue_pressed() -> void:
	var err: String = SaveSystem.load_run()
	if err != "":
		_toast_lbl.text = "불러오기 실패: " + err
		Haptics.play(Haptics.Kind.ERROR)
		return
	# Mid-match save: jump straight back into MatchFlow (which reads
	# season_state.match_resume on _ready and skips ahead to the saved
	# phase). Otherwise drop into the campaign hub.
	if _gm.season_state.get("match_resume", null) != null:
		get_tree().change_scene_to_file("res://scenes/MatchFlow.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Season.tscn")


func _on_new_run_pressed() -> void:
	if not _has_run:
		_start_new_run()
		return
	# 아직 안 지웠다 — 다만 이 누름이 평범한 누름이 아님은 말해야 한다.
	Haptics.play(Haptics.Kind.WARNING)
	_confirm.open("진행 중인 런을 포기할까요?",
			"지금까지의 진척으로 실패 정산하고 런을 끝냅니다.\n점수 · 재화 보상은 받지만 런은 되돌릴 수 없습니다.",
			"취소", "포기하고 정산", true)


func _on_abandon_confirmed() -> void:
	# 포기 = 그 시점 진척으로 실패 정산(`docs/outgame_dev_plan.md` §10.3) — 셀 수
	# 있게 런을 먼저 싣는다. 정산이 프로필에 쓰고 run.save 를 지운다.
	var lerr: String = SaveSystem.load_run()
	if lerr == "":
		# 되돌릴 수 없는 종료. 아웃게임에서 가장 무거운 조작이다.
		Haptics.play(Haptics.Kind.ERROR)
		RunResult.settle_current_run(RunResult.OUTCOME_ABANDON)
		get_tree().change_scene_to_file(RunResult.SCENE_PATH)
		return
	# 깨진 런 — 정산할 것이 없다. 예전처럼 지우고 새 런으로.
	push_warning("Lobby: abandon could not load run (%s) — deleting without settlement" % lerr)
	var err: String = SaveSystem.delete_run()
	if err != "":
		_toast_lbl.text = "런 삭제 실패: " + err
		Haptics.play(Haptics.Kind.ERROR)
		return
	Haptics.play(Haptics.Kind.ERROR)
	_toast_lbl.text = "런을 읽을 수 없어 정산 없이 삭제했습니다"
	_start_new_run()


func _on_manager_type_chosen(type_id: int) -> void:
	var err: String = _pm.set_manager_type(type_id)
	if err != "":
		# Profile write failed — say so; the choice still holds for this session.
		_toast_lbl.text = "감독 유형 저장 실패: " + err
		Haptics.play(Haptics.Kind.ERROR)


func _start_new_run() -> void:
	_gm.reset_season_state()
	get_tree().change_scene_to_file(RUN_SETUP_SCENE)
