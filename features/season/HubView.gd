class_name HubView
extends Control

# Simplified weekly hub. The campaign progresses week-by-week, so this
# screen surfaces the current phase, the phase-week counter, and the player
# roster, with two action buttons: "이번 주 시작" (route to TRAINING) and a
# context-sensitive standings button (INTL → playoff → league).
#
# **Layout lives in `HubView.tscn`** (header labels, five `HubRosterRow` instances, the
# `HubManageCard` row, toast, bottom bar). This script binds `%` nodes, fills data, wires
# signals and applies the device safe-area offsets (pattern B, `docs/mobile_safe_area.md`):
# the whole screen is lowered to the safe top, the background stretched back up, and the
# bottom bar hung from the safe bottom (`OutgameTheme.fit_bottom_bar`). Create with `HubView.create()`.

const SCENE_PATH: String = "res://features/season/HubView.tscn"

const PHASE_NAMES: Dictionary = {
	GameEnums.SeasonPhase.PRESEASON:      "프리시즌",
	GameEnums.SeasonPhase.PRESEASON_INTL: "프리시즌 국제대회",
	GameEnums.SeasonPhase.MIDSEASON:      "미드시즌",
	GameEnums.SeasonPhase.MIDSEASON_INTL: "미드시즌 국제대회",
	GameEnums.SeasonPhase.REGULAR:        "정규시즌",
	GameEnums.SeasonPhase.REGULAR_INTL:   "정규시즌 국제대회",
}

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _phase_lbl: Label
var _week_lbl: Label
var _next_match_lbl: Label
var _toast_lbl: Label
var _roster_rows: Array = []    # HubRosterRow, seat order
var _manage_cards: Array = []   # HubManageCard, `_manage_panels()` order
var _start_btn: Button
var _standings_btn: Button
var _built: bool = false


## Instantiates the scene. `HubView.new()` is an empty Control — don't use it.
## Load (not preload) — preloading its own scene is a script ↔ scene cycle.
static func create() -> HubView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as HubView


func _ready() -> void:
	_bind()
	_connect_signals()
	refresh()


func ensure_view() -> void:
	_bind()
	_connect_signals()
	refresh()


# ── Bind ─────────────────────────────────────────────────────────────────────
func _bind() -> void:
	if _built:
		return
	_built = true
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 제목이 깔리지 않게. 배경만은 노치 자리까지 다시 덮는다.
	ScreenMetrics.indent_to_safe_top(self)
	ScreenMetrics.extend_background(%Background)
	OutgameTheme.fit_bottom_bar(%BottomBar, %SafeBottom)

	_phase_lbl = %Phase
	_week_lbl = %Week
	_next_match_lbl = %NextMatch
	_toast_lbl = %Toast
	_toast_lbl.text = ""

	# 줄 순서는 **역할 열거값 순서가 아니라 화면 순서**다(탑 · 정글 · 미드 ·
	# 원딜 · 서폿) — `GameEnums.ROLE_DISPLAY_ORDER`. 씬의 줄도 자리 순서로 서 있어
	# `_refresh_roster` 가 같은 표로 되읽는다.
	_roster_rows = %Roster.get_children()
	for seat in _roster_rows.size():
		(_roster_rows[seat] as HubRosterRow).set_role(int(GameEnums.ROLE_DISPLAY_ORDER[seat]))

	_manage_cards = %Manage.get_children()
	for i in _manage_cards.size():
		(_manage_cards[i] as HubManageCard).pressed.connect(_on_manage_pressed.bind(i))

	_standings_btn = %Standings
	_start_btn = %Start
	_standings_btn.pressed.connect(_on_standings_pressed)
	_start_btn.pressed.connect(_on_start_pressed)


# ── Trust (M7 data, shown since §14 T4) ──────────────────────────────────────
## Trust band colour. Thresholds come from the mental consts — no new numbers:
## below `TRUST_OUTING_MIN` grey (no outing yet), from there green (outing unlocked),
## past halfway between that and `TRUST_MAX` amber (close bond).
static func trust_color(value: int) -> Color:
	var outing_min: int = ConstTable.int_of("TRUST_OUTING_MIN")
	var high: int = outing_min + int(float(ConstTable.int_of("TRUST_MAX") - outing_min) * 0.5)
	if value >= high:
		return OutgameTheme.ACCENT
	if value >= outing_min:
		return OutgameTheme.POSITIVE
	return OutgameTheme.TEXT_SUB


# ── 관리 카드 줄 (M3~M6) ─────────────────────────────────────────────────────
## 로스터 아래 가로 한 줄에 작은 카드 셋 — 스태프 · 메크 연구 · 재무.
## 카드 내용은 각 기능의 패널이 소유한다(`<Panel>.hub_summary(state)` →
## `{title, value, sub, owner, alert}`), 누르면 `<Panel>.open(self)` 가
## `HubSheet` 를 띄운다. 시트가 닫히면 허브 전체를 다시 그린다 — 시트 안에서
## 바꾼 값(연구 메크 · 배분 · 업그레이드)이 허브 숫자에 바로 비치게.
## 씬의 `%Manage` 카드 순서가 이 배열 순서다.
# 클래스 참조는 상수식이 아니라 `const` 로 못 둔다 — 함수로 돌려준다.
static func _manage_panels() -> Array:
	return [StaffPanel, MasteryPanel, FinancePanel]


func _refresh_manage_row() -> void:
	var s: Dictionary = _gm.season_state
	var panels: Array = _manage_panels()
	for i in mini(_manage_cards.size(), panels.size()):
		(_manage_cards[i] as HubManageCard).show_summary(panels[i].hub_summary(s))


func _on_manage_pressed(i: int) -> void:
	_manage_panels()[i].open(self)
	# 시트가 방금 붙었다 — 닫힐 때 허브를 다시 그린다.
	var sheet: HubSheet = null
	for c in get_children():
		if c is HubSheet:
			sheet = c
	if sheet != null and not sheet.closed.is_connected(refresh):
		sheet.closed.connect(refresh)


## 허브 하단 토스트 — 다른 화면(주 마감 수지 등)이 허브로 돌아오며 띄운다.
func show_toast(msg: String) -> void:
	_flash_toast(msg)


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


# intl_completed 는 우리 팀이 우승했을 때만 온다 — 탈락은 intl_failed_campaign
# 으로 바로 GAME_OVER 다(남의 우승을 알리고 계속하는 길은 없다).
func _on_intl_completed(_phase: int, _champion_team_id: int) -> void:
	refresh()
	_flash_toast("국제대회 우승! — 우리 팀이 챔피언입니다")


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
	_week_lbl.text  = "%d / %d주차" % [pweek, max_weeks]

	_refresh_next_match()
	_refresh_roster()
	_refresh_manage_row()
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
	var t_max: int = ConstTable.int_of("TRUST_MAX")
	for seat in _roster_rows.size():
		var r: int = int(GameEnums.ROLE_DISPLAY_ORDER[seat])
		var row: HubRosterRow = _roster_rows[seat]
		if not by_role.has(r):
			row.show_pilot(null)
			continue
		var p: PlayerData = by_role[r]
		row.show_pilot(p, MentalSystem.trust(_gm.season_state, p.id), t_max)


# ── Button handlers ──────────────────────────────────────────────────────────
func _on_start_pressed() -> void:
	if _hub != null:
		# 주는 기자회견으로 열린다 — 훈련 계획은 그 다음이다.
		_hub.goto(SeasonHub.Screen.PRESS)


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
