class_name IntlBracketView
extends Control


# Phase 8 — INTL bracket screen. 8-team single elimination visualised as
# 4 QF panels stacked left, 2 SF panels middle, 1 F panel right. Player team
# panels are tinted gold; played matches dim losers, winners pop.
#
# Mirrors features/season/tournament/BracketView.gd (Phase 7 4-team layout)
# but is a separate screen because the panel grid + slot count differ.

const WEEKDAY_NAMES: Array = ["월", "화", "수", "목", "금", "토", "일"]

const QF_W: float = 280.0
const QF_H: float = 130.0
const SF_W: float = 280.0
const SF_H: float = 150.0
const F_W:  float = 320.0
const F_H:  float = 170.0

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _intl: InternationalTournament = null
var _phase_lbl: Label
var _stage_lbl: Label
var _next_match_lbl: Label
var _empty_lbl: Label
var _match_widgets: Array = []   # 7 dicts of {panel, stylebox, slot_lbl, date_lbl, team_a_lbl, team_b_lbl}
var _back_btn: Button
var _built: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	if not _built:
		_build()
		_built = true
	_resolve_refs()
	refresh()


func ensure_view() -> void:
	if not _built:
		_build()
		_built = true
	_resolve_refs()
	refresh()


func _resolve_refs() -> void:
	if _hub == null:
		return
	if _intl == null:
		_intl = _hub.get_node_or_null("InternationalTournament") as InternationalTournament


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 제목이 깔리지 않게. 제목만 따로 내리면 본문과 겹친다.
	ScreenMetrics.indent_to_safe_top(self)
	OutgameTheme.add_background(self)

	UiHelpers.mk_label(self, "국제대회 브래킷", 36, OutgameTheme.TEXT,
			Vector2(0, 18), Vector2(1080, 44), HORIZONTAL_ALIGNMENT_CENTER)

	_phase_lbl = UiHelpers.mk_label(self, "", 22, OutgameTheme.TEXT_SUB,
			Vector2(0, 70), Vector2(1080, 28), HORIZONTAL_ALIGNMENT_CENTER)
	_stage_lbl = UiHelpers.mk_label(self, "", 22, OutgameTheme.TEXT_SUB,
			Vector2(0, 102), Vector2(1080, 28), HORIZONTAL_ALIGNMENT_CENTER)
	_next_match_lbl = UiHelpers.mk_label(self, "", 22, OutgameTheme.ACCENT_TEXT,
			Vector2(0, 134), Vector2(1080, 28), HORIZONTAL_ALIGNMENT_CENTER)

	_empty_lbl = UiHelpers.mk_label(self, "국제대회 진행 전입니다.", 26, OutgameTheme.TEXT_FAINT,
			Vector2(0, 720), Vector2(1080, 36), HORIZONTAL_ALIGNMENT_CENTER)
	_empty_lbl.visible = false

	_build_match_panels()
	_build_back_button()


# Layout: 4 QFs in left column, 2 SFs in middle, 1 F in right (vertically
# centered against the SF pair). Match-day order Fri→Sat→Sun reads left→right.
func _build_match_panels() -> void:
	var qf_x: float = 50.0
	var sf_x: float = 400.0
	var f_x:  float = 730.0

	var qf_top: float = 240.0
	var qf_gap: float = 50.0
	var sf_gap_y: float = (QF_H * 2.0 + qf_gap) - SF_H + 20.0  # rough vertical centering
	var sf_top: float = qf_top + (QF_H * 1.5 + qf_gap * 0.5) - SF_H * 0.5
	var f_top:  float = sf_top + (SF_H + sf_gap_y * 0.5) - F_H * 0.5

	# QF1..QF4
	for i in 4:
		var pos := Vector2(qf_x, qf_top + i * (QF_H + qf_gap))
		_match_widgets.append(_build_match_panel(pos, i, Vector2(QF_W, QF_H)))

	# SF1, SF2
	_match_widgets.append(_build_match_panel(Vector2(sf_x, sf_top), 4, Vector2(SF_W, SF_H)))
	_match_widgets.append(_build_match_panel(Vector2(sf_x, sf_top + SF_H + sf_gap_y), 5, Vector2(SF_W, SF_H)))

	# F
	_match_widgets.append(_build_match_panel(Vector2(f_x, f_top), 6, Vector2(F_W, F_H)))


func _build_match_panel(pos: Vector2, slot: int, sz: Vector2) -> Dictionary:
	var panel := Panel.new()
	panel.position = pos
	panel.size     = sz
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sty := StyleBoxFlat.new()
	sty.bg_color     = OutgameTheme.SURFACE
	sty.border_color = OutgameTheme.BORDER
	sty.border_width_left = 2; sty.border_width_right = 2
	sty.border_width_top = 2;  sty.border_width_bottom = 2
	sty.corner_radius_top_left     = 6
	sty.corner_radius_top_right    = 6
	sty.corner_radius_bottom_left  = 6
	sty.corner_radius_bottom_right = 6
	sty.shadow_color = OutgameTheme.SHADOW
	sty.shadow_size = 6
	sty.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", sty)
	add_child(panel)

	var slot_lbl := UiHelpers.mk_label(panel, _slot_label_static(slot), 18, OutgameTheme.ACCENT_TEXT,
			Vector2(8, 4), Vector2(sz.x - 16, 22), HORIZONTAL_ALIGNMENT_LEFT)
	var date_lbl := UiHelpers.mk_label(panel, "", 16, OutgameTheme.TEXT_SUB,
			Vector2(8, 4), Vector2(sz.x - 16, 22), HORIZONTAL_ALIGNMENT_RIGHT)
	var team_a_lbl := UiHelpers.mk_label(panel, "", 22, OutgameTheme.TEXT,
			Vector2(12, 36), Vector2(sz.x - 24, 32), HORIZONTAL_ALIGNMENT_LEFT)
	var team_b_lbl := UiHelpers.mk_label(panel, "", 22, OutgameTheme.TEXT,
			Vector2(12, sz.y - 50), Vector2(sz.x - 24, 32), HORIZONTAL_ALIGNMENT_LEFT)

	return {
		"panel":      panel,
		"stylebox":   sty,
		"slot_lbl":   slot_lbl,
		"date_lbl":   date_lbl,
		"team_a_lbl": team_a_lbl,
		"team_b_lbl": team_b_lbl,
	}


## 버튼은 하나뿐이다("확인") — 주를 넘기는 일은 시간 경과 화면의 일요일
## 마감이 가져갔고, 돌아갈 자리는 버튼이 아니라 주 진행 상태가 정한다
## (`SeasonHub.on_standings_confirmed`).
func _build_back_button() -> void:
	# 하나뿐인 행동이라 **하단 구간을 통째로 차지한다** — 좌우 끝에서 끝까지,
	# 아래는 안전선에 밀착(`OutgameTheme.add_bottom_bar`).
	var bar: Array = OutgameTheme.add_bottom_bar(self, [
		{"text": "확인", "style": "primary", "font": 34},
	])
	_back_btn = bar[0]
	_back_btn.pressed.connect(_on_back_pressed)


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not _built:
		return
	_resolve_refs()
	if _intl == null:
		return

	var phase: int = int(_gm.season_state["current_phase"])
	_phase_lbl.text = "현재 페이즈: %s" % HubView.PHASE_NAMES.get(phase, "—")

	if not _intl.is_active():
		_empty_lbl.visible = true
		_stage_lbl.text = ""
		_next_match_lbl.text = ""
		for w in _match_widgets:
			w["panel"].visible = false
		return
	_empty_lbl.visible = false
	for w in _match_widgets:
		w["panel"].visible = true

	var t: Dictionary = _gm.season_state["current_tournament"]
	var stage: int = int(t["stage"])
	_stage_lbl.text = "단계: %s" % _stage_name(stage)

	var pid: int = int(_gm.season_state["player_team_id"])
	var nxt = _intl.next_unplayed_player_match()
	if nxt == null:
		_next_match_lbl.text = "플레이어 경기 없음 / 종료됨"
	else:
		var opp_id: int = int(nxt["team_b"]) if int(nxt["team_a"]) == pid else int(nxt["team_a"])
		var opp_name: String = "TBD" if opp_id < 0 else _intl.team_name(opp_id)
		_next_match_lbl.text = "다음 매치: %s — %d주차 vs %s" % [
			_intl.slot_label(int(nxt["slot"])),
			int(nxt["phase_week"]),
			opp_name,
		]

	var b: Array = _intl.bracket()
	for i in 7:
		_refresh_match_panel(i, b[i] if i < b.size() else {}, pid)


func _refresh_match_panel(slot: int, m: Dictionary, pid: int) -> void:
	var w: Dictionary = _match_widgets[slot]
	if m.is_empty():
		w["team_a_lbl"].text = ""
		w["team_b_lbl"].text = ""
		w["date_lbl"].text = ""
		return
	var ta: int = int(m["team_a"]); var tb: int = int(m["team_b"])
	var winner: int = int(m["winner"])
	var played: bool = bool(m["played"])

	w["team_a_lbl"].text = _team_text(ta)
	w["team_b_lbl"].text = _team_text(tb)
	w["date_lbl"].text   = "%d주차" % int(m.get("phase_week", 0))

	w["team_a_lbl"].add_theme_color_override("font_color",
			_team_color(ta, pid, played, winner))
	w["team_b_lbl"].add_theme_color_override("font_color",
			_team_color(tb, pid, played, winner))

	var sty: StyleBoxFlat = w["stylebox"]
	if ta == pid or tb == pid:
		sty.border_color = OutgameTheme.ACCENT
		sty.border_width_left = 3; sty.border_width_right = 3
		sty.border_width_top = 3;  sty.border_width_bottom = 3
	elif played:
		sty.border_color = OutgameTheme.POSITIVE
		sty.border_width_left = 2; sty.border_width_right = 2
		sty.border_width_top = 2;  sty.border_width_bottom = 2
	else:
		sty.border_color = OutgameTheme.BORDER
		sty.border_width_left = 2; sty.border_width_right = 2
		sty.border_width_top = 2;  sty.border_width_bottom = 2


func _team_text(team_id: int) -> String:
	if team_id < 0:
		return "— TBD —"
	if _intl == null:
		return "Team %d" % team_id
	return "%s  (%s)" % [_intl.team_name(team_id), _intl.team_short_name(team_id)]


func _team_color(team_id: int, pid: int, played: bool, winner: int) -> Color:
	if team_id < 0:
		return OutgameTheme.TEXT_FAINT
	if played:
		if team_id == winner:
			return OutgameTheme.ACCENT_TEXT if team_id == pid else OutgameTheme.POSITIVE
		return OutgameTheme.TEXT_FAINT
	return OutgameTheme.ACCENT_TEXT if team_id == pid else OutgameTheme.TEXT


func _slot_label_static(slot: int) -> String:
	match slot:
		0: return "8강 1경기"
		1: return "8강 2경기"
		2: return "8강 3경기"
		3: return "8강 4경기"
		4: return "4강 1경기"
		5: return "4강 2경기"
		6: return "결승"
	return ""


func _stage_name(stage: int) -> String:
	match stage:
		GameEnums.TournamentStage.INTL_QF: return "8강 진행 중"
		GameEnums.TournamentStage.INTL_SF: return "4강 진행 중"
		GameEnums.TournamentStage.INTL_F:  return "결승 진행 중"
		GameEnums.TournamentStage.CHAMPION: return "우승 결정"
	return "—"


func _on_back_pressed() -> void:
	if _hub != null and _hub.has_method("on_standings_confirmed"):
		_hub.on_standings_confirmed()
