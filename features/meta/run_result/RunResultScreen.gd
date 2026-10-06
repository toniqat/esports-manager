extends Control

# 런 정산 화면 — `GameManager.last_run_result` 를 읽어 보여 준다.
# 계약: docs/outgame_dev_plan.md §10.3. 계산은 `RunResult.gd`, 여기는 그리기만.
#
# 위에서부터: 결과 머리(클리어 / 실패 / 포기) · 시나리오와 팀 · (테스트 런 칩) →
# 스크롤 본문 카드 넷(진척 · 점수 내역 · 보상 · 이번 런 업적) → 전폭 하단 바 하나.
# 하단 바는 평소 `로비로`, 로비에서 런을 포기하고 왔으면(`outcome == "abandon"`)
# `새 런`(→ 런 준비). 결과가 비어 있으면(씬을 바로 연 경우) 빈 상태 한 장.
#
# 결과 딕셔너리만으로 그린다 — 표시용 키(`team_name` · `scenario_name` · `pilots` ·
# `breakdown` · `phase_reached_count`)를 `RunResult.build_result` 가 미리 담아 둔다.

const LOBBY_SCENE: String = "res://scenes/Lobby.tscn"
const RUN_SETUP_SCENE: String = "res://scenes/RunSetup.tscn"

const CARD_X: float = 80.0
const CARD_W: float = 920.0
const CARD_PAD: float = 40.0
const CARD_GAP: float = 28.0
const SECTION_TITLE_H: float = 56.0
const ROW_H: float = 48.0
const PILOT_ROW_H: float = 104.0
const PORTRAIT_D: float = 76.0
const BODY_TOP: float = 360.0

const OUTCOME_TITLES: Dictionary = {
	"clear":   "런 클리어",
	"fail":    "런 실패",
	"abandon": "런 포기",
}

@onready var _gm: Node = get_node("/root/GameManager")

var _result: Dictionary = {}
var _built: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_result = _gm.last_run_result
	if not _built:
		_build()
		_built = true
	if String(_result.get("outcome", "")) == RunResult.OUTCOME_CLEAR:
		Haptics.play(Haptics.Kind.SUCCESS)


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	ScreenMetrics.indent_to_safe_top(self)
	OutgameTheme.add_background(self)
	if _result.is_empty():
		_build_empty()
	else:
		_build_header()
		_build_body()
	_build_bottom_bar()


func _card_x() -> float:
	return maxf(CARD_X, ScreenMetrics.center_x() - CARD_W * 0.5)


func _build_header() -> void:
	var vp_w: float = ScreenMetrics.vp_w()
	var outcome: String = String(_result.get("outcome", ""))
	var color: Color = OutgameTheme.TEXT_SUB
	if outcome == RunResult.OUTCOME_CLEAR:
		color = OutgameTheme.ACCENT_TEXT
	elif outcome == RunResult.OUTCOME_FAIL:
		color = OutgameTheme.NEGATIVE
	UiHelpers.mk_label(self, String(OUTCOME_TITLES.get(outcome, "런 종료")), 64, color,
			Vector2(0, 120), Vector2(vp_w, 88), HORIZONTAL_ALIGNMENT_CENTER)
	var rule := ColorRect.new()
	rule.color = OutgameTheme.ACCENT
	rule.position = Vector2(ScreenMetrics.center_x() - 40.0, 218)
	rule.size = Vector2(80, 6)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)

	var parts: Array = []
	var scen: String = String(_result.get("scenario_name", ""))
	var team: String = String(_result.get("team_name", ""))
	if scen != "":
		parts.append(scen)
	if team != "":
		parts.append(team)
	UiHelpers.mk_label(self, " · ".join(PackedStringArray(parts)) if not parts.is_empty() else "—", 26,
			OutgameTheme.TEXT, Vector2(0, 244), Vector2(vp_w, 38),
			HORIZONTAL_ALIGNMENT_CENTER)
	if bool(_result.get("test_run", false)):
		var chip_w: float = 380.0
		OutgameTheme.add_chip(self, "테스트 런 — 프로필 미반영",
				Vector2(ScreenMetrics.center_x() - chip_w * 0.5, 296),
				Vector2(chip_w, 42), OutgameTheme.ACCENT_DIM,
				OutgameTheme.ACCENT_TEXT, 20)


func _build_body() -> void:
	var top: float = BODY_TOP
	var h: float = OutgameTheme.bottom_bar_top() - 16.0 - top
	var sv: Dictionary = OutgameTheme.add_vscroll(self, Vector2(0, top),
			Vector2(ScreenMetrics.vp_w(), h))
	var body: Control = sv["body"]
	var y: float = 0.0
	y = _build_progress_card(body, y) + CARD_GAP
	y = _build_score_card(body, y) + CARD_GAP
	y = _build_reward_card(body, y) + CARD_GAP
	y = _build_achievement_card(body, y) + CARD_GAP
	body.custom_minimum_size.y = y


func _build_progress_card(parent: Control, y: float) -> float:
	var rows: Array = [
		["도달 페이즈", "%s (%d/%d)" % [
				_phase_name(int(_result.get("phase_reached", 0))),
				int(_result.get("phase_reached_count", 0)),
				RunResult.CAMPAIGN_ORDER.size()]],
		["전적", "%d승 %d패" % [int(_result.get("wins", 0)), int(_result.get("losses", 0))]],
		["대회 우승", "%d회" % int(_result.get("titles", 0))],
	]
	var card: Panel = _section_card(parent, y, "진척", rows.size())
	for i in rows.size():
		_row(card, SECTION_TITLE_H + CARD_PAD * 0.5 + i * ROW_H,
				String(rows[i][0]), String(rows[i][1]), OutgameTheme.TEXT)
	return y + card.size.y


func _build_score_card(parent: Control, y: float) -> float:
	var bd: Dictionary = _result.get("breakdown", {})
	var rows: Array = [
		["페이즈 도달 × %d" % int(_result.get("phase_reached_count", 0)), int(bd.get("phase", 0))],
		["승리 × %d" % int(_result.get("wins", 0)), int(bd.get("wins", 0))],
		["대회 우승 × %d" % int(_result.get("titles", 0)), int(bd.get("titles", 0))],
		["클리어 보너스", int(bd.get("clear", 0))],
		["보너스 점수", int(bd.get("bonus", _result.get("bonus_points", 0)))],
	]
	# 합계 줄은 구분선 + 큰 글씨라 한 줄 반을 쓴다.
	var card: Panel = _section_card(parent, y, "점수", rows.size() + 2)
	var ry: float = SECTION_TITLE_H + CARD_PAD * 0.5
	for r in rows:
		var v: int = int(r[1])
		_row(card, ry, String(r[0]), "+%d" % v,
				OutgameTheme.TEXT if v > 0 else OutgameTheme.TEXT_FAINT)
		ry += ROW_H
	OutgameTheme.add_divider(card, Vector2(CARD_PAD, ry + 12.0), CARD_W - CARD_PAD * 2.0)
	ry += 28.0
	UiHelpers.mk_label(card, "합계", 28, OutgameTheme.TEXT,
			Vector2(CARD_PAD, ry), Vector2(300, 56))
	UiHelpers.mk_label(card, "%d" % int(_result.get("score", 0)), 44,
			OutgameTheme.ACCENT_TEXT, Vector2(CARD_W * 0.5, ry - 6.0),
			Vector2(CARD_W * 0.5 - CARD_PAD, 60), HORIZONTAL_ALIGNMENT_RIGHT)
	return y + card.size.y


func _build_reward_card(parent: Control, y: float) -> float:
	var test_run: bool = bool(_result.get("test_run", false))
	var card: Panel = _section_card(parent, y, "보상", 3 if test_run else 2)
	var cur: int = int((_result.get("currency", {}) as Dictionary).get("outgame", 0))
	var ry: float = SECTION_TITLE_H + CARD_PAD * 0.5
	_row(card, ry, "아웃게임 재화", "+%d" % cur, OutgameTheme.POSITIVE)
	_row(card, ry + ROW_H, "감독 EXP", "+%d" % int(_result.get("manager_exp", 0)),
			OutgameTheme.POSITIVE)
	if test_run:
		UiHelpers.mk_label(card, "테스트 런이라 프로필에 더하지 않았습니다", 22,
				OutgameTheme.TEXT_FAINT, Vector2(CARD_PAD, ry + ROW_H * 2.0),
				Vector2(CARD_W - CARD_PAD * 2.0, ROW_H))
	return y + card.size.y


func _build_achievement_card(parent: Control, y: float) -> float:
	var pilots: Array = _result.get("pilots", [])
	var ach: Dictionary = _result.get("achievements", {})
	var rows_h: float = maxf(1.0, float(pilots.size())) * PILOT_ROW_H
	var card: Panel = OutgameTheme.add_card(parent, Vector2(_card_x(), y),
			Vector2(CARD_W, SECTION_TITLE_H + CARD_PAD * 1.5 + rows_h), 24)
	_section_title(card, "이번 런 업적")
	var ry: float = SECTION_TITLE_H + CARD_PAD * 0.5
	if pilots.is_empty():
		UiHelpers.mk_label(card, "기록된 선수가 없습니다", 24, OutgameTheme.TEXT_FAINT,
				Vector2(CARD_PAD, ry + 30.0), Vector2(CARD_W - CARD_PAD * 2.0, 40))
		return y + card.size.y
	for p in pilots:
		var pd: Dictionary = p
		var pid: int = int(pd.get("id", -1))
		var a: Dictionary = ach.get(str(pid), {})
		var tex: Texture2D = PilotImages.circle_for(pid)
		OutgameTheme.add_round_portrait(card, tex,
				Vector2(CARD_PAD, ry + (PILOT_ROW_H - PORTRAIT_D) * 0.5), PORTRAIT_D)
		var tx: float = CARD_PAD + PORTRAIT_D + 24.0
		UiHelpers.mk_label(card, String(pd.get("name", "")), 28, OutgameTheme.TEXT,
				Vector2(tx, ry + 18.0), Vector2(360, 40))
		var role: int = int(pd.get("role", -1))
		var role_name: String = String(OutgameTheme.ROLE_NAMES[role]) \
				if role >= 0 and role < OutgameTheme.ROLE_NAMES.size() else ""
		UiHelpers.mk_label(card, role_name, 20, OutgameTheme.TEXT_SUB,
				Vector2(tx, ry + 58.0), Vector2(360, 30))
		var mvp_n: int = int(a.get("mvp", 0))
		var pom_n: int = int(a.get("pom", 0))
		var chip_w: float = 140.0
		var cx: float = CARD_W - CARD_PAD - chip_w
		_count_chip(card, "POM %d" % pom_n, pom_n > 0, Vector2(cx, ry + 32.0), chip_w)
		_count_chip(card, "MVP %d" % mvp_n, mvp_n > 0,
				Vector2(cx - chip_w - 16.0, ry + 32.0), chip_w)
		ry += PILOT_ROW_H
	return y + card.size.y


func _build_empty() -> void:
	var vp_w: float = ScreenMetrics.vp_w()
	UiHelpers.mk_label(self, "런 정산", 64, OutgameTheme.TEXT,
			Vector2(0, 120), Vector2(vp_w, 88), HORIZONTAL_ALIGNMENT_CENTER)
	var card: Panel = OutgameTheme.add_card(self, Vector2(_card_x(), 420),
			Vector2(CARD_W, 220), 24)
	var l1 := UiHelpers.mk_label(card, "표시할 정산 결과가 없습니다", 30,
			OutgameTheme.TEXT_SUB, Vector2(0, 58), Vector2(CARD_W, 44),
			HORIZONTAL_ALIGNMENT_CENTER)
	l1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiHelpers.mk_label(card, "런이 끝나면 이 화면에 점수와 보상이 나옵니다", 22,
			OutgameTheme.TEXT_FAINT, Vector2(0, 112), Vector2(CARD_W, 34),
			HORIZONTAL_ALIGNMENT_CENTER)


func _build_bottom_bar() -> void:
	var to_new_run: bool = String(_result.get("outcome", "")) == RunResult.OUTCOME_ABANDON
	var bar: Array = OutgameTheme.add_bottom_bar(self, [
		{"text": "새 런" if to_new_run else "로비로", "style": "primary",
				"font": 32, "weight": 1.0},
	])
	(bar[0] as Button).pressed.connect(_on_new_run_pressed if to_new_run else _on_lobby_pressed)


# ── 그리기 조각 ──────────────────────────────────────────────────────────────
# 제목 + `row_count` 줄짜리 카드 한 장.
func _section_card(parent: Control, y: float, title: String, row_count: int) -> Panel:
	var card: Panel = OutgameTheme.add_card(parent, Vector2(_card_x(), y),
			Vector2(CARD_W, SECTION_TITLE_H + CARD_PAD * 1.5 + row_count * ROW_H), 24)
	_section_title(card, title)
	return card


func _section_title(card: Control, title: String) -> void:
	UiHelpers.mk_label(card, title, 24, OutgameTheme.TEXT_SUB,
			Vector2(CARD_PAD, CARD_PAD * 0.5 + 8.0), Vector2(CARD_W - CARD_PAD * 2.0, 34))
	OutgameTheme.add_divider(card, Vector2(CARD_PAD, SECTION_TITLE_H + 8.0),
			CARD_W - CARD_PAD * 2.0)


func _row(card: Control, ry: float, label: String, value: String, value_color: Color) -> void:
	UiHelpers.mk_label(card, label, 24, OutgameTheme.TEXT_SUB,
			Vector2(CARD_PAD, ry + 6.0), Vector2(CARD_W * 0.55, 36))
	UiHelpers.mk_label(card, value, 26, value_color,
			Vector2(CARD_W * 0.45, ry + 4.0), Vector2(CARD_W * 0.55 - CARD_PAD, 38),
			HORIZONTAL_ALIGNMENT_RIGHT)


func _count_chip(card: Control, text: String, lit: bool, pos: Vector2, w: float) -> void:
	OutgameTheme.add_chip(card, text, pos, Vector2(w, 40),
			OutgameTheme.ACCENT_DIM if lit else OutgameTheme.SURFACE_SUNK,
			OutgameTheme.ACCENT_TEXT if lit else OutgameTheme.TEXT_FAINT, 20)


func _phase_name(idx: int) -> String:
	if idx < 0 or idx >= RunResult.CAMPAIGN_ORDER.size():
		return "—"
	return String(HubView.PHASE_NAMES.get(RunResult.CAMPAIGN_ORDER[idx], "—"))


# ── Button handlers ──────────────────────────────────────────────────────────
# 정산은 이미 프로필에 썼고 run.save 도 지웠다 — 남은 런 상태를 비우고 떠난다.
func _on_lobby_pressed() -> void:
	_gm.reset_season_state()
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_new_run_pressed() -> void:
	_gm.reset_season_state()
	get_tree().change_scene_to_file(RUN_SETUP_SCENE)
