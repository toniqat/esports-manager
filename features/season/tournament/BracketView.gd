class_name BracketView
extends Control

# Phase 7 — playoff bracket screen. 4-team single elimination visualised as
# two semifinal panels stacked on the left and a final panel on the right.
# Each match panel shows team_a / team_b, the winner indicator, and the
# scheduled date. Player team is tinted gold, played matches dim losers.

const WEEKDAY_NAMES: Array = ["월", "화", "수", "목", "금", "토", "일"]
const SLOT_LABELS: Array = ["4강 1경기", "4강 2경기", "결승"]

const MATCH_W: float = 420.0
const MATCH_H: float = 200.0

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _league: LeagueManager = null
var _tournament: TournamentManager = null
var _phase_lbl: Label
var _stage_lbl: Label
var _next_match_lbl: Label
var _empty_lbl: Label
var _match_widgets: Array = []   # 3 dicts of {panel, stylebox, slot_lbl, date_lbl, team_a_lbl, team_b_lbl}
var _next_btn: Button
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


# Idempotent — SeasonHub calls this each time it routes to PLAYOFF.
func ensure_view() -> void:
	if not _built:
		_build()
		_built = true
	_resolve_refs()
	refresh()


func _resolve_refs() -> void:
	if _hub == null:
		return
	if _league == null:
		_league = _hub.get_node_or_null("LeagueManager") as LeagueManager
	if _tournament == null:
		_tournament = _hub.get_node_or_null("TournamentManager") as TournamentManager


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.14, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	UiHelpers.mk_label(self, "플레이오프 브래킷", 36, Color(1.0, 0.85, 0.20),
			Vector2(0, 18), Vector2(1080, 44), HORIZONTAL_ALIGNMENT_CENTER)

	_phase_lbl = UiHelpers.mk_label(self, "", 22, Color(0.55, 0.85, 1.0),
			Vector2(0, 70), Vector2(1080, 28), HORIZONTAL_ALIGNMENT_CENTER)
	_stage_lbl = UiHelpers.mk_label(self, "", 22, Color(0.85, 0.85, 0.95),
			Vector2(0, 102), Vector2(1080, 28), HORIZONTAL_ALIGNMENT_CENTER)
	_next_match_lbl = UiHelpers.mk_label(self, "", 22, Color(1.0, 0.85, 0.40),
			Vector2(0, 134), Vector2(1080, 28), HORIZONTAL_ALIGNMENT_CENTER)

	_empty_lbl = UiHelpers.mk_label(self, "플레이오프 진행 전입니다.", 26, Color(0.85, 0.85, 0.9),
			Vector2(0, 720), Vector2(1080, 36), HORIZONTAL_ALIGNMENT_CENTER)
	_empty_lbl.visible = false

	_build_match_panels()
	_build_back_button()


func _build_match_panels() -> void:
	# Layout: SF1 + SF2 stacked left, F right. Connector lines drawn implicitly
	# via the gap between panels — the labels carry the semantic.
	var left_x: float = 90.0
	var right_x: float = 580.0
	var sf_y_top: float = 250.0
	var sf_gap: float = 60.0
	var f_y: float = sf_y_top + (MATCH_H + sf_gap) / 2.0  # vertically centered between SFs

	var positions: Array = [
		Vector2(left_x,  sf_y_top),
		Vector2(left_x,  sf_y_top + MATCH_H + sf_gap),
		Vector2(right_x, f_y),
	]

	for i in 3:
		_match_widgets.append(_build_match_panel(positions[i], i))


func _build_match_panel(pos: Vector2, slot: int) -> Dictionary:
	var panel := Panel.new()
	panel.position = pos
	panel.size     = Vector2(MATCH_W, MATCH_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sty := StyleBoxFlat.new()
	sty.bg_color     = Color(0.10, 0.12, 0.18, 1.0)
	sty.border_color = Color(0.30, 0.35, 0.50, 1.0)
	sty.border_width_left = 2; sty.border_width_right = 2
	sty.border_width_top = 2;  sty.border_width_bottom = 2
	sty.corner_radius_top_left     = 8
	sty.corner_radius_top_right    = 8
	sty.corner_radius_bottom_left  = 8
	sty.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", sty)
	add_child(panel)

	var slot_lbl := UiHelpers.mk_label(panel, SLOT_LABELS[slot], 22, Color(1.0, 0.85, 0.40),
			Vector2(12, 8), Vector2(MATCH_W - 24, 28), HORIZONTAL_ALIGNMENT_LEFT)
	var date_lbl := UiHelpers.mk_label(panel, "", 18, Color(0.7, 0.75, 0.9),
			Vector2(12, 8), Vector2(MATCH_W - 24, 28), HORIZONTAL_ALIGNMENT_RIGHT)

	var team_a_lbl := UiHelpers.mk_label(panel, "", 28, Color(1, 1, 1),
			Vector2(20, 60), Vector2(MATCH_W - 40, 38), HORIZONTAL_ALIGNMENT_LEFT)
	var team_b_lbl := UiHelpers.mk_label(panel, "", 28, Color(1, 1, 1),
			Vector2(20, 120), Vector2(MATCH_W - 40, 38), HORIZONTAL_ALIGNMENT_LEFT)

	return {
		"panel":      panel,
		"stylebox":   sty,
		"slot_lbl":   slot_lbl,
		"date_lbl":   date_lbl,
		"team_a_lbl": team_a_lbl,
		"team_b_lbl": team_b_lbl,
	}


func _build_back_button() -> void:
	var w: float = 320.0
	var h: float = 100.0
	var gap: float = 30.0
	var total: float = w * 2 + gap
	var x0: float = (1080.0 - total) / 2.0
	var y: float = 1740.0

	_back_btn = Button.new()
	_back_btn.text = "돌아가기"
	_back_btn.position = Vector2(x0, y)
	_back_btn.size     = Vector2(w, h)
	_back_btn.add_theme_font_size_override("font_size", 30)
	_back_btn.pressed.connect(_on_back_pressed)
	add_child(_back_btn)

	_next_btn = Button.new()
	_next_btn.text = "다음 주 →"
	_next_btn.position = Vector2(x0 + w + gap, y)
	_next_btn.size     = Vector2(w, h)
	_next_btn.add_theme_font_size_override("font_size", 30)
	_next_btn.pressed.connect(_on_next_week_pressed)
	add_child(_next_btn)


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not _built:
		return
	_resolve_refs()
	if _tournament == null:
		return

	var phase: int = int(_gm.season_state["current_phase"])
	_phase_lbl.text = "현재 페이즈: %s" % HubView.PHASE_NAMES.get(phase, "—")

	if not _tournament.is_active():
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
	var nxt = _tournament.next_unplayed_player_match()
	if nxt == null:
		_next_match_lbl.text = "플레이어 경기 없음 / 종료됨"
	else:
		var opp_id: int = int(nxt["team_b"]) if int(nxt["team_a"]) == pid else int(nxt["team_a"])
		var opp_name: String = "TBD"
		if opp_id >= 0 and _league != null:
			opp_name = _league.team_name(opp_id)
		_next_match_lbl.text = "다음 매치: %s — %d주차 vs %s" % [
			_tournament.slot_label(int(nxt["slot"])),
			int(nxt["phase_week"]),
			opp_name,
		]

	var b: Array = _tournament.bracket()
	for i in 3:
		_refresh_match_panel(i, b[i] if i < b.size() else {}, pid)
	_refresh_buttons()


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

	# Winner / loser color treatment.
	w["team_a_lbl"].add_theme_color_override("font_color",
			_team_color(ta, pid, played, winner))
	w["team_b_lbl"].add_theme_color_override("font_color",
			_team_color(tb, pid, played, winner))

	# Panel border: gold when player participates, green when match decided.
	var sty: StyleBoxFlat = w["stylebox"]
	if ta == pid or tb == pid:
		sty.border_color = Color(1.0, 0.85, 0.20, 1.0)
		sty.border_width_left = 3; sty.border_width_right = 3
		sty.border_width_top = 3;  sty.border_width_bottom = 3
	elif played:
		sty.border_color = Color(0.40, 0.65, 0.45, 1.0)
		sty.border_width_left = 2; sty.border_width_right = 2
		sty.border_width_top = 2;  sty.border_width_bottom = 2
	else:
		sty.border_color = Color(0.30, 0.35, 0.50, 1.0)
		sty.border_width_left = 2; sty.border_width_right = 2
		sty.border_width_top = 2;  sty.border_width_bottom = 2


func _team_text(team_id: int) -> String:
	if team_id < 0:
		return "— TBD —"
	if _league == null:
		return "Team %d" % team_id
	return "%s  (%s)" % [_league.team_name(team_id), _league.team_short_name(team_id)]


func _team_color(team_id: int, pid: int, played: bool, winner: int) -> Color:
	if team_id < 0:
		return Color(0.5, 0.5, 0.55)
	if played:
		if team_id == winner:
			return Color(1.0, 0.95, 0.50) if team_id == pid else Color(0.55, 0.95, 0.55)
		return Color(0.55, 0.55, 0.60)
	return Color(1.0, 0.85, 0.40) if team_id == pid else Color(1, 1, 1)


func _stage_name(stage: int) -> String:
	match stage:
		GameEnums.TournamentStage.PLAYOFF_SF: return "4강 진행 중"
		GameEnums.TournamentStage.PLAYOFF_F:  return "결승 진행 중"
		GameEnums.TournamentStage.CHAMPION:   return "우승 결정"
	return "—"


# ── Button handlers ─────────────────────────────────────────────────────────
func _refresh_buttons() -> void:
	if _next_btn == null or _hub == null:
		return
	_next_btn.disabled = _hub.has_player_match_this_week()


func _on_back_pressed() -> void:
	if _hub != null:
		_hub.goto(SeasonHub.Screen.HUB)


func _on_next_week_pressed() -> void:
	if _hub != null and _hub.has_method("on_proceed_to_next_week"):
		_hub.on_proceed_to_next_week()
