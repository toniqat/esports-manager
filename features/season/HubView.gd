class_name HubView
extends Control

# Simplified weekly hub. The campaign progresses week-by-week, so this
# screen surfaces the current phase, the phase-week counter, and the player
# roster, with two action buttons: "이번 주 시작" (route to TRAINING) and a
# context-sensitive standings button (INTL → playoff → league).

const PHASE_NAMES: Dictionary = {
	GameEnums.SeasonPhase.PRESEASON:      "프리시즌",
	GameEnums.SeasonPhase.PRESEASON_INTL: "프리시즌 국제대회",
	GameEnums.SeasonPhase.MIDSEASON:      "미드시즌",
	GameEnums.SeasonPhase.MIDSEASON_INTL: "미드시즌 국제대회",
	GameEnums.SeasonPhase.REGULAR:        "정규시즌",
	GameEnums.SeasonPhase.REGULAR_INTL:   "정규시즌 국제대회",
}
const ROLE_NAMES: Array = ["TANK", "FIGHTER", "ASSASSIN", "SUPPORT", "SNIPER"]
const ROLE_COLORS: Array = [
	Color(0.30, 0.55, 1.00),
	Color(1.00, 0.55, 0.20),
	Color(0.75, 0.40, 1.00),
	Color(0.30, 0.85, 0.45),
	Color(1.00, 0.35, 0.35),
]
const STAT_KEYS: Array   = ["laning", "mechanics", "gamesense", "teamfight", "mental"]
const STAT_LABELS: Array = ["라", "메", "겜", "한", "멘"]

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _phase_lbl: Label
var _week_lbl: Label
var _next_match_lbl: Label
var _toast_lbl: Label
var _roster_widgets: Array = []   # 5 dicts of {name, total, stats}
var _start_btn: Button
var _standings_btn: Button
var _built: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	if not _built:
		_build()
		_built = true
	_connect_signals()
	refresh()


func ensure_view() -> void:
	if not _built:
		_build()
		_built = true
	_connect_signals()
	refresh()


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 제목이 깔리지 않게. 제목만 따로 내리면 본문과 겹친다.
	ScreenMetrics.indent_to_safe_top(self)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.14, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 배경만은 안전 영역 밖(노치 자리)까지 덮는다 — 안 그러면 그 띠가
	# 엔진 기본 배경색으로 남는다.
	ScreenMetrics.extend_background(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	UiHelpers.mk_label(self, "SEASON HUB", 40, Color(1.0, 0.85, 0.20),
			Vector2(0, 24), Vector2(1080, 50), HORIZONTAL_ALIGNMENT_CENTER)

	_phase_lbl = UiHelpers.mk_label(self, "", 30, Color(0.55, 0.85, 1.0),
			Vector2(0, 88), Vector2(1080, 36), HORIZONTAL_ALIGNMENT_CENTER)
	_week_lbl = UiHelpers.mk_label(self, "", 26, Color(0.92, 0.92, 0.98),
			Vector2(0, 132), Vector2(1080, 32), HORIZONTAL_ALIGNMENT_CENTER)
	_next_match_lbl = UiHelpers.mk_label(self, "", 24, Color(1.0, 0.85, 0.40),
			Vector2(0, 174), Vector2(1080, 30), HORIZONTAL_ALIGNMENT_CENTER)

	_build_roster_block()
	_build_buttons()

	_toast_lbl = UiHelpers.mk_label(self, "", 22, Color(1.0, 0.85, 0.40),
			Vector2(0, ScreenMetrics.safe_h() - 252.0),
			Vector2(ScreenMetrics.vp_w(), 28), HORIZONTAL_ALIGNMENT_CENTER)


func _build_roster_block() -> void:
	var x0: float = 30.0
	var y0: float = 240.0
	var row_h: float = 220.0
	var row_gap: float = 12.0
	var width: float = 1020.0

	UiHelpers.mk_label(self, "내 팀 로스터", 24, Color(1.0, 0.85, 0.20),
			Vector2(x0, y0 - 36), Vector2(360, 30), HORIZONTAL_ALIGNMENT_LEFT)

	for r in 5:
		var y: float = y0 + r * (row_h + row_gap)
		var role_col: Color = ROLE_COLORS[r]
		var panel := Panel.new()
		var sty := StyleBoxFlat.new()
		sty.bg_color = Color(0.10, 0.12, 0.18, 1.0)
		sty.border_color = role_col
		sty.border_width_left = 2; sty.border_width_right = 2
		sty.border_width_top  = 2; sty.border_width_bottom = 2
		sty.corner_radius_top_left = 6; sty.corner_radius_top_right = 6
		sty.corner_radius_bottom_left = 6; sty.corner_radius_bottom_right = 6
		panel.add_theme_stylebox_override("panel", sty)
		panel.position = Vector2(x0, y)
		panel.size     = Vector2(width, row_h)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)

		var face_rect := TextureRect.new()
		face_rect.position    = Vector2(16, 14)
		face_rect.size        = Vector2(160, 160)
		face_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		face_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(face_rect)

		UiHelpers.mk_label(panel, ROLE_NAMES[r], 20, role_col,
				Vector2(190, 14), Vector2(160, 26), HORIZONTAL_ALIGNMENT_LEFT)
		var name_lbl := UiHelpers.mk_label(panel, "—", 28, Color(1, 1, 1),
				Vector2(190, 44), Vector2(560, 36), HORIZONTAL_ALIGNMENT_LEFT)
		var total_lbl := UiHelpers.mk_label(panel, "", 22, Color(1.0, 0.85, 0.40),
				Vector2(190, 90), Vector2(280, 28), HORIZONTAL_ALIGNMENT_LEFT)

		# Stat strip
		var stat_x0: float = 480.0
		var stat_w: float = (width - stat_x0 - 20) / 5.0
		var stat_lbls: Array = []
		for s in STAT_KEYS.size():
			var sx: float = stat_x0 + s * stat_w
			UiHelpers.mk_label(panel, STAT_LABELS[s], 18, Color(0.65, 0.75, 0.90),
					Vector2(sx, 60), Vector2(stat_w, 22), HORIZONTAL_ALIGNMENT_CENTER)
			var v_lbl := UiHelpers.mk_label(panel, "", 32, Color(1, 1, 1),
					Vector2(sx, 88), Vector2(stat_w, 40), HORIZONTAL_ALIGNMENT_CENTER)
			stat_lbls.append(v_lbl)

		_roster_widgets.append({
			"name": name_lbl, "total": total_lbl, "stats": stat_lbls, "face": face_rect,
		})


func _build_buttons() -> void:
	var btn_w: float = 480.0
	var btn_h: float = 110.0
	# 하단 안전선에 매단다 — 이 자리는 아이폰 홈 인디케이터 / 안드로이드
	# 제스처 바가 터치를 가져가는 구간과 맞닿아 있다.
	var top: float = ScreenMetrics.safe_h() - 110.0 - btn_h
	var gap: float = 30.0
	var total_w: float = 2.0 * btn_w + gap
	var start_x: float = (1080.0 - total_w) / 2.0

	_start_btn = Button.new()
	_start_btn.text = "이번 주 시작"
	_start_btn.position = Vector2(start_x, top)
	_start_btn.size     = Vector2(btn_w, btn_h)
	_start_btn.add_theme_font_size_override("font_size", 36)
	_start_btn.pressed.connect(_on_start_pressed)
	add_child(_start_btn)

	_standings_btn = Button.new()
	_standings_btn.text = "리그 순위"
	_standings_btn.position = Vector2(start_x + btn_w + gap, top)
	_standings_btn.size     = Vector2(btn_w, btn_h)
	_standings_btn.add_theme_font_size_override("font_size", 36)
	_standings_btn.pressed.connect(_on_standings_pressed)
	add_child(_standings_btn)


# ── Signals ──────────────────────────────────────────────────────────────────
func _connect_signals() -> void:
	if _hub == null:
		return
	var cal: CalendarSystem = _hub.get_node_or_null("CalendarSystem") as CalendarSystem
	if cal != null:
		if not cal.week_advanced.is_connected(_on_week_advanced):
			cal.week_advanced.connect(_on_week_advanced)
		if not cal.phase_changed.is_connected(_on_phase_changed):
			cal.phase_changed.connect(_on_phase_changed)
	var tm: TournamentManager = _hub.get_node_or_null("TournamentManager") as TournamentManager
	if tm != null:
		if not tm.playoff_started.is_connected(_on_playoff_started):
			tm.playoff_started.connect(_on_playoff_started)
		if not tm.playoff_completed.is_connected(_on_playoff_completed):
			tm.playoff_completed.connect(_on_playoff_completed)
	var intl: InternationalTournament = _hub.get_node_or_null("InternationalTournament") as InternationalTournament
	if intl != null:
		if not intl.intl_started.is_connected(_on_intl_started):
			intl.intl_started.connect(_on_intl_started)
		if not intl.intl_completed.is_connected(_on_intl_completed):
			intl.intl_completed.connect(_on_intl_completed)


func _on_playoff_started(_phase: int) -> void:
	refresh()
	_flash_toast("플레이오프 진입! — 4강 매치 대기 중")


func _on_playoff_completed(_phase: int, champion_team_id: int) -> void:
	refresh()
	if _hub == null:
		return
	var league: LeagueManager = _hub.get_node_or_null("LeagueManager") as LeagueManager
	if league == null:
		_flash_toast("플레이오프 종료")
		return
	var pid: int = int(_gm.season_state["player_team_id"])
	var msg: String = "우승: %s" % league.team_name(champion_team_id)
	if champion_team_id == pid:
		msg = "우리 팀 우승!"
	_flash_toast(msg)


func _on_intl_started(_phase: int) -> void:
	refresh()
	_flash_toast("국제대회 진입! — 8팀 토너먼트")


func _on_intl_completed(_phase: int, champion_team_id: int) -> void:
	refresh()
	if _hub == null:
		return
	var intl: InternationalTournament = _hub.get_node_or_null("InternationalTournament") as InternationalTournament
	if intl == null:
		_flash_toast("국제대회 종료")
		return
	var pid: int = int(_gm.season_state["player_team_id"])
	var msg: String = "국제대회 우승: %s" % intl.team_name(champion_team_id)
	if champion_team_id == pid:
		msg = "국제대회 우승! — 우리 팀이 챔피언입니다"
	_flash_toast(msg)


func _on_week_advanced(_d: Dictionary) -> void:
	refresh()


func _on_phase_changed(new_phase: int) -> void:
	refresh()
	_flash_toast("페이즈 진입: %s" % PHASE_NAMES.get(new_phase, "—"))


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not _built:
		return
	var s: Dictionary = _gm.season_state
	var phase: int = int(s["current_phase"])
	var pweek: int = int(s["phase_week"])
	var max_weeks: int = 1
	if _hub != null:
		var cal: CalendarSystem = _hub.get_node_or_null("CalendarSystem") as CalendarSystem
		if cal != null:
			max_weeks = cal.phase_max_weeks(phase)

	_phase_lbl.text = "현재 페이즈: %s" % PHASE_NAMES.get(phase, "—")
	_week_lbl.text  = "%d주차 / %d주차" % [pweek, max_weeks]

	_refresh_next_match()
	_refresh_roster()
	_refresh_standings_btn()


func _refresh_next_match() -> void:
	if _hub == null:
		_next_match_lbl.text = ""
		return
	var pid: int = int(_gm.season_state["player_team_id"])
	# Priority: INTL > playoff > league.
	var intl: InternationalTournament = _hub.get_node_or_null("InternationalTournament") as InternationalTournament
	if intl != null and intl.is_active():
		var idx: int = intl.find_player_match_this_week_idx()
		if idx >= 0:
			var m: Dictionary = (_gm.season_state["current_tournament"]["bracket"] as Array)[idx]
			var opp: int = int(m["team_b"]) if int(m["team_a"]) == pid else int(m["team_a"])
			_next_match_lbl.text = "이번 주 경기: %s — vs %s" % [
				intl.slot_label(int(m["slot"])), intl.team_name(opp)]
			return
	var tm: TournamentManager = _hub.get_node_or_null("TournamentManager") as TournamentManager
	if tm != null and tm.is_active():
		var idx2: int = tm.find_player_match_this_week_idx()
		if idx2 >= 0:
			var m: Dictionary = (_gm.season_state["current_tournament"]["bracket"] as Array)[idx2]
			var opp: int = int(m["team_b"]) if int(m["team_a"]) == pid else int(m["team_a"])
			var league: LeagueManager = _hub.get_node_or_null("LeagueManager") as LeagueManager
			var opp_name: String = "Team %d" % opp
			if league != null:
				opp_name = league.team_name(opp)
			_next_match_lbl.text = "이번 주 경기: %s — vs %s" % [
				tm.slot_label(int(m["slot"])), opp_name]
			return
	var league2: LeagueManager = _hub.get_node_or_null("LeagueManager") as LeagueManager
	if league2 != null:
		var nxt = league2.player_match_this_week()
		if nxt != null:
			var opp: int = int(nxt["team_b"]) if int(nxt["team_a"]) == pid else int(nxt["team_a"])
			_next_match_lbl.text = "이번 주 경기: vs %s" % league2.team_name(opp)
			return
	_next_match_lbl.text = "이번 주 경기 없음"


func _refresh_standings_btn() -> void:
	if _standings_btn == null:
		return
	var tm: TournamentManager = null
	var intl: InternationalTournament = null
	if _hub != null:
		tm = _hub.get_node_or_null("TournamentManager") as TournamentManager
		intl = _hub.get_node_or_null("InternationalTournament") as InternationalTournament
	if intl != null and intl.is_active():
		_standings_btn.text = "국제대회"
	elif tm != null and tm.is_active():
		_standings_btn.text = "플레이오프"
	else:
		_standings_btn.text = "리그 순위"


func _refresh_roster() -> void:
	var pool: Array = _gm.season_state["all_pilots"]
	var pid: int = int(_gm.season_state["player_team_id"])
	var by_role: Dictionary = {}
	for raw in pool:
		var p := raw as PlayerData
		if p.team_id == pid:
			by_role[int(p.role)] = p
	for r in 5:
		var w: Dictionary = _roster_widgets[r]
		if not by_role.has(r):
			w["name"].text = "—"
			w["total"].text = ""
			(w["face"] as TextureRect).texture = null
			for s in STAT_KEYS.size():
				w["stats"][s].text = ""
			continue
		var p: PlayerData = by_role[r]
		w["name"].text = p.name
		(w["face"] as TextureRect).texture = PilotImages.face_for(p.id)
		var total: int = p.laning + p.mechanics + p.gamesense + p.teamfight + p.mental
		w["total"].text = "TOTAL %d" % total
		for s in STAT_KEYS.size():
			var key: String = STAT_KEYS[s]
			w["stats"][s].text = "%d" % int(p.get(key))


# ── Button handlers ──────────────────────────────────────────────────────────
func _on_start_pressed() -> void:
	if _hub != null:
		_hub.goto(SeasonHub.Screen.TRAINING)


func _on_standings_pressed() -> void:
	if _hub == null:
		return
	var intl: InternationalTournament = _hub.get_node_or_null("InternationalTournament") as InternationalTournament
	if intl != null and intl.is_active():
		_hub.goto(SeasonHub.Screen.INTL_BRACKET)
		return
	var tm: TournamentManager = _hub.get_node_or_null("TournamentManager") as TournamentManager
	if tm != null and tm.is_active():
		_hub.goto(SeasonHub.Screen.PLAYOFF)
	else:
		_hub.goto(SeasonHub.Screen.LEAGUE)


func _flash_toast(msg: String) -> void:
	if _toast_lbl == null:
		return
	_toast_lbl.text = msg
	var tween := create_tween()
	tween.tween_interval(2.5)
	tween.tween_callback(_clear_toast.bind(msg))


func _clear_toast(expected: String) -> void:
	if _toast_lbl != null and _toast_lbl.text == expected:
		_toast_lbl.text = ""
