class_name HomeTab
extends Control

# 로비의 홈 탭 — 진행 중인 런 카드와 `새 런`(1) / `이어하기`(2) 행동 바.
# 런이 없으면 빈 상태 카드와 전폭 `새 런`. 탭 계약은 `LobbyScreen.gd` 머리말.
#
# `새 런` 을 누를 때 런이 이미 있으면 **포기 확인 모달**을 띄운다 — 확인하면 그 런을
# **포기로 정산**(`RunResult.settle_current_run("abandon")`, 실패 정산이지만 보상은
# 준다)하고 정산 화면으로 간다. 그 화면의 `새 런` 이 런 준비로 잇는다.

const PHASE_NAMES: Dictionary = HubView.PHASE_NAMES
const WEEKDAY_NAMES: Array = OutgameTheme.DAY_LETTERS
const RUN_SETUP_SCENE: String = "res://scenes/RunSetup.tscn"

const CARD_X: float = 80.0
const CARD_W: float = 920.0
const TITLE_Y: float = 64.0
const CARD_TOP: float = 300.0
const CARD_H: float = 400.0
const EMPTY_CARD_H: float = 220.0
const CARD_PAD: float = 44.0

var _host: LobbyScreen
var _gm: Node
var _pm: Node
var _has_run: bool = false
var _meta: Dictionary = {}


func bar_specs() -> Array:
	# 런이 있으면 1:2 — 이어하기가 주 행동이라 오른쪽 3분의 2. 없으면 새 런이 전폭.
	if SaveSystem.has_run():
		return [
			{"text": "새 런",    "style": "ghost",   "font": 32, "weight": 1.0},
			{"text": "이어하기", "style": "primary", "font": 32, "weight": 2.0},
		]
	return [{"text": "새 런", "style": "primary", "font": 32, "weight": 1.0}]


func setup(host: LobbyScreen) -> void:
	_host = host
	_gm = get_node("/root/GameManager")
	_pm = get_node("/root/ProfileManager")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_has_run = SaveSystem.has_run()
	_meta = SaveSystem.read_run_meta() if _has_run else {}
	_build()


func on_shown() -> void:
	pass


func on_bar_pressed(i: int) -> void:
	if _has_run and i == 1:
		_on_continue_pressed()
	else:
		_on_new_run_pressed()


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	var w: float = size.x
	UiHelpers.mk_label(self, "ESPORTS MANAGER", 64, OutgameTheme.TEXT,
			Vector2(0, TITLE_Y), Vector2(w, 88), HORIZONTAL_ALIGNMENT_CENTER)
	var rule := ColorRect.new()
	rule.color = OutgameTheme.ACCENT
	rule.position = Vector2(w * 0.5 - 40.0, TITLE_Y + 102.0)
	rule.size = Vector2(80, 6)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)
	var mgr_lv: int = ManagerProgress.level_of(_pm.profile)
	UiHelpers.mk_label(self, "감독 Lv%d · 보유 선수 %d명 · 특성 %d개" % [
				mgr_lv, (_pm.owned_pilot_ids() as Array).size(),
				(_pm.owned_trait_ids() as Array).size()],
			22, OutgameTheme.TEXT_SUB, Vector2(0, TITLE_Y + 124.0), Vector2(w, 32),
			HORIZONTAL_ALIGNMENT_CENTER)

	UiHelpers.mk_label(self, "진행 중인 런", 24, OutgameTheme.TEXT_SUB,
			Vector2(_card_x(), CARD_TOP - 50.0), Vector2(CARD_W, 34))
	if _has_run and not _meta.is_empty():
		_build_run_card()
	else:
		_build_empty_card()


func _card_x() -> float:
	return maxf(CARD_X, size.x * 0.5 - CARD_W * 0.5)


func _build_run_card() -> void:
	var card: Panel = OutgameTheme.add_card(self, Vector2(_card_x(), CARD_TOP),
			Vector2(CARD_W, CARD_H), 24)
	var inner_w: float = CARD_W - CARD_PAD * 2.0
	UiHelpers.mk_label(card, String(PHASE_NAMES.get(int(_meta.get("phase", 0)), "—")), 36,
			OutgameTheme.TEXT, Vector2(CARD_PAD, CARD_PAD - 4.0), Vector2(inner_w, 50))
	if bool(_meta.get("match_in_progress", false)):
		var chip_w: float = 170.0
		OutgameTheme.add_chip(card, "경기 진행 중",
				Vector2(CARD_W - CARD_PAD - chip_w, CARD_PAD + 2.0),
				Vector2(chip_w, 40), OutgameTheme.ACCENT_DIM, OutgameTheme.ACCENT_TEXT, 20)
	UiHelpers.mk_label(card, "%d년 %d월 %d일 (%s)" % [
				int(_meta.get("year", 1)), int(_meta.get("month", 12)),
				int(_meta.get("day", 1)), _weekday_name(int(_meta.get("weekday", 0))),
			], 24, OutgameTheme.TEXT_SUB,
			Vector2(CARD_PAD, CARD_PAD + 54.0), Vector2(inner_w, 34))
	OutgameTheme.add_divider(card, Vector2(CARD_PAD, CARD_PAD + 112.0), inner_w)
	UiHelpers.mk_label(card, String(_meta.get("team_name", "—")), 32,
			OutgameTheme.TEXT, Vector2(CARD_PAD, CARD_PAD + 136.0), Vector2(inner_w, 44))
	UiHelpers.mk_label(card, "우승 트로피 %d개" % int(_meta.get("trophies", 0)),
			24, OutgameTheme.ACCENT_TEXT, Vector2(CARD_PAD, CARD_PAD + 188.0), Vector2(inner_w, 34))
	var rank: int = int(_meta.get("rank", 0))
	var record: String = "리그 미시작"
	if rank > 0:
		record = "현재 리그 %d위 (%d승 %d패)" % [
			rank, int(_meta.get("wins", 0)), int(_meta.get("losses", 0))]
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


func _weekday_name(wd: int) -> String:
	if wd >= 0 and wd < WEEKDAY_NAMES.size():
		return String(WEEKDAY_NAMES[wd])
	return "?"


# ── Actions ──────────────────────────────────────────────────────────────────
func _on_continue_pressed() -> void:
	var err: String = SaveSystem.load_run()
	if err != "":
		_host.show_toast("불러오기 실패: " + err, true)
		return
	# Mid-match save: jump straight back into MatchFlow (which reads
	# season_state.match_resume on _ready and skips ahead to the saved phase).
	if _gm.season_state.get("match_resume", null) != null:
		get_tree().change_scene_to_file("res://scenes/MatchFlow.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Season.tscn")


func _on_new_run_pressed() -> void:
	if not _has_run:
		_start_new_run()
		return
	Haptics.play(Haptics.Kind.WARNING)
	_host.open_confirm("진행 중인 런을 포기할까요?",
			"지금까지의 진척으로 실패 정산하고 런을 끝냅니다.\n점수 · 재화 보상은 받지만 런은 되돌릴 수 없습니다.",
			"취소", "포기하고 정산", true, _on_abandon_confirmed)


func _on_abandon_confirmed() -> void:
	# 포기 = 그 시점 진척으로 실패 정산(계획서 §10.3) — 셀 수 있게 런을 먼저 싣는다.
	var lerr: String = SaveSystem.load_run()
	if lerr == "":
		Haptics.play(Haptics.Kind.ERROR)
		RunResult.settle_current_run(RunResult.OUTCOME_ABANDON)
		get_tree().change_scene_to_file(RunResult.SCENE_PATH)
		return
	# 깨진 런 — 정산할 것이 없다. 지우고 새 런으로.
	push_warning("Lobby: abandon could not load run (%s) — deleting without settlement" % lerr)
	var err: String = SaveSystem.delete_run()
	if err != "":
		_host.show_toast("런 삭제 실패: " + err, true)
		return
	Haptics.play(Haptics.Kind.ERROR)
	_start_new_run()


func _start_new_run() -> void:
	_gm.reset_season_state()
	get_tree().change_scene_to_file(RUN_SETUP_SCENE)
