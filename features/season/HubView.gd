class_name HubView
extends Control

# Simplified weekly hub. The campaign progresses week-by-week, so this
# screen surfaces the current phase, the phase-week counter, and the player
# roster, with two action buttons: "이번 주 시작" (route to TRAINING) and a
# context-sensitive standings button (INTL → playoff → league).
#
# **Layout lives in `UI_View_HubView.tscn`** (header labels, five `SeasonPilotCard` instances, the
# `HubManageCard` row, the team base map slot `%MapHolder`, toast, bottom bar). The map (§16) is the
# team's `BaseMap` with one `ResearchBubble` per facility spot; tapping a bubble (or the facility
# under its tail) switches to that facility's screen (`SeasonHub.open_facility` → `FacilityView`).
# "이번 주 시작" first warns (`ConfirmPopup`) when a facility still has no research picked
# (`ResearchSystem.unset_facilities`). This script binds `%` nodes, fills data, wires
# signals and applies the device safe-area offsets (pattern B, `docs/mobile_safe_area.md`):
# the whole screen is lowered to the safe top, the background stretched back up, and the
# bottom bar hung from the safe bottom (`OutgameTheme.fit_bottom_bar`). Create with `HubView.create()`.

const SCENE_PATH: String = "res://features/season/UI_View_HubView.tscn"

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _phase_lbl: Label
var _week_lbl: Label
var _next_match_lbl: Label
var _toast_lbl: Label
var _roster_cards: Array = []   # SeasonPilotCard, seat order (tap = SeasonPilotDetail)
var _manage_cards: Array = []   # HubManageCard, `_manage_panels()` order
var _map: BaseMap = null        # team base map in %MapHolder (built on the first refresh)
var _start_btn: Button
var _standings_btn: Button
var _built: bool = false
var _start_confirm: ConfirmPopup = null


## Instantiates the scene. `HubView.new()` is an empty Control — don't use it.
## Load (not preload) — preloading its own scene is a script ↔ scene cycle.
static func create() -> HubView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as HubView


func _ready() -> void:
	_bind()
	_connect_signals()
	if UiPreview.is_standalone(self):
		_fill_preview()
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

	# 카드 순서는 **역할 열거값 순서가 아니라 화면 순서**다(탑 · 정글 · 미드 ·
	# 원딜 · 서폿) — `GameEnums.ROLE_DISPLAY_ORDER`. 씬의 카드도 자리 순서로 서 있어
	# `_refresh_roster` 가 같은 표로 되읽는다. 카드를 누르면 선수 상세 시트.
	_roster_cards = %Roster.get_children()
	for c in _roster_cards:
		(c as SeasonPilotCard).pressed.connect(_on_pilot_pressed)

	_manage_cards = %Manage.get_children()
	for i in _manage_cards.size():
		(_manage_cards[i] as HubManageCard).pressed.connect(_on_manage_pressed.bind(i))

	_standings_btn = %Standings
	_start_btn = %Start
	_standings_btn.pressed.connect(_on_standings_pressed)
	_start_btn.pressed.connect(_on_start_pressed)


# ── Trust (M7 data, shown since §14 T4) ──────────────────────────────────────
## Trust band colour by **level** (`MentalSystem.trust_level`). Thresholds come from the mental
## consts — no new numbers: below `TRUST_OUTING_LEVEL` grey (no outing yet), from there green
## (outing unlocked), past halfway between that and `TRUST_LEVEL_MAX` amber (close bond).
static func trust_color(level: int) -> Color:
	var outing_lv: int = ConstTable.int_of("TRUST_OUTING_LEVEL")
	var high: float = float(outing_lv) + float(ConstTable.int_of("TRUST_LEVEL_MAX") - outing_lv) * 0.5
	if float(level) >= high:
		return OutgameTheme.ACCENT
	if level >= outing_lv:
		return OutgameTheme.POSITIVE
	return OutgameTheme.TEXT_SUB


# ── 관리 카드 줄 (M3~M6) ─────────────────────────────────────────────────────
## 로스터 아래 가로 한 줄에 작은 카드 둘 — 스태프 · 재무. (§16: 메크 연구 카드는 지도의
## 메크 연구소 시설로 옮겨 갔다.)
## 카드 내용은 각 기능의 패널이 소유한다(`<Panel>.hub_summary(state)` →
## `{title, value, sub, owner, alert}`), 누르면 `<Panel>.open(self)` 가
## `HubSheet` 를 띄운다. 시트가 닫히면 허브 전체를 다시 그린다 — 시트 안에서
## 바꾼 값(연구 메크 · 배분 · 업그레이드)이 허브 숫자에 바로 비치게.
## 씬의 `%Manage` 카드 순서가 이 배열 순서다.
# 클래스 참조는 상수식이 아니라 `const` 로 못 둔다 — 함수로 돌려준다.
static func _manage_panels() -> Array:
	return [StaffPanel, FinancePanel]


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


# ── 팀 부지 맵 + 시설 연구 말풍선 (§16) ──────────────────────────────────────
## 팀 맵은 처음 한 번만 만들고, 말풍선은 매 refresh 마다 제자리에서 다시 채운다
## (`ResearchBubble.populate` 가 있던 말풍선을 재사용). 말풍선을 누르면 시설 시트.
func _refresh_map() -> void:
	var s: Dictionary = _gm.season_state
	if _map == null:
		_map = BaseMap.create(RunRules.team_map_id(int(s.get("player_team_id", 0))))
		_map.name = "BaseMap_Team"
		# 1200 폭 맵을 화면 가운데에 — 좌우 60 씩 화면 밖으로 잘린다 (`BaseMap.mount`).
		BaseMap.mount(_map, %MapHolder as Control)
	for raw in ResearchBubble.populate(_map, s, true):
		var b: ResearchBubble = raw
		if not b.pressed.is_connected(_on_facility_pressed):
			b.pressed.connect(_on_facility_pressed)


func _on_facility_pressed(fid: String) -> void:
	if _hub != null:
		_hub.open_facility(fid)
	else:
		print("[UiPreview] facility %s" % fid)


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
	_flash_toast(Loc.t(L.SEASON_HUB_TOAST_PLAYOFF_STARTED))


func _on_playoff_completed(_phase: int, champion_team_id: int) -> void:
	refresh()
	if _hub == null:
		return
	var league: LeagueManager = _hub.get_node_or_null("LeagueManager") as LeagueManager
	if league == null:
		_flash_toast(Loc.t(L.SEASON_HUB_TOAST_PLAYOFF_OVER))
		return
	var pid: int = int(_gm.season_state["player_team_id"])
	var msg: String = Loc.t(L.SEASON_HUB_TOAST_PLAYOFF_CHAMPION,
			{"team": league.team_name(champion_team_id)})
	if champion_team_id == pid:
		msg = Loc.t(L.SEASON_HUB_TOAST_PLAYOFF_WON)
	_flash_toast(msg)


func _on_intl_started(_phase: int) -> void:
	refresh()
	_flash_toast(Loc.t(L.SEASON_HUB_TOAST_INTL_STARTED))


# intl_completed 는 우리 팀이 우승했을 때만 온다 — 탈락은 intl_failed_campaign
# 으로 바로 GAME_OVER 다(남의 우승을 알리고 계속하는 길은 없다).
func _on_intl_completed(_phase: int, _champion_team_id: int) -> void:
	refresh()
	_flash_toast(Loc.t(L.SEASON_HUB_TOAST_INTL_WON))


func _on_week_advanced(_d: Dictionary) -> void:
	refresh()


func _on_phase_changed(new_phase: int) -> void:
	refresh()
	_flash_toast(Loc.t(L.SEASON_HUB_TOAST_PHASE_ENTERED, {"phase": GameEnums.phase_label(new_phase)}))


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

	_phase_lbl.text = Loc.t(L.SEASON_COMMON_CURRENT_PHASE, {"phase": GameEnums.phase_label(phase)})
	_week_lbl.text  = Loc.t(L.SEASON_HUB_WEEK_PROGRESS, {"week": pweek, "max": max_weeks})

	_refresh_next_match()
	_refresh_roster()
	_refresh_manage_row()
	_refresh_map()
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
			_next_match_lbl.text = Loc.t(L.SEASON_HUB_MATCH_BRACKET, {
				"slot": intl.slot_label(int(m["slot"])), "team": intl.team_name(opp)})
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
			_next_match_lbl.text = Loc.t(L.SEASON_HUB_MATCH_BRACKET, {
				"slot": tm.slot_label(int(m["slot"])), "team": opp_name})
			return
	var league2: LeagueManager = _hub.get_node_or_null("LeagueManager") as LeagueManager
	if league2 != null:
		var nxt = league2.player_match_this_week()
		if nxt != null:
			var opp: int = int(nxt["team_b"]) if int(nxt["team_a"]) == pid else int(nxt["team_a"])
			_next_match_lbl.text = Loc.t(L.SEASON_HUB_MATCH_LEAGUE, {"team": league2.team_name(opp)})
			return
	_next_match_lbl.text = Loc.t(L.SEASON_HUB_NO_MATCH)


func _refresh_standings_btn() -> void:
	if _standings_btn == null:
		return
	var tm: TournamentManager = null
	var intl: InternationalTournament = null
	if _hub != null:
		tm = _hub.get_node_or_null("TournamentManager") as TournamentManager
		intl = _hub.get_node_or_null("InternationalTournament") as InternationalTournament
	if intl != null and intl.is_active():
		_standings_btn.text = Loc.t(L.TERM_PHASE_INTL)
	elif tm != null and tm.is_active():
		_standings_btn.text = Loc.t(L.SEASON_HUB_BTN_PLAYOFF)
	else:
		_standings_btn.text = Loc.t(L.SEASON_HUB_BTN_STANDINGS)


func _refresh_roster() -> void:
	var pool: Array = _gm.season_state["all_pilots"]
	var pid: int = int(_gm.season_state["player_team_id"])
	var by_role: Dictionary = {}
	for raw in pool:
		var p := raw as PlayerData
		if p.team_id == pid:
			by_role[int(p.role)] = p
	for seat in _roster_cards.size():
		var r: int = int(GameEnums.ROLE_DISPLAY_ORDER[seat])
		var card: SeasonPilotCard = _roster_cards[seat]
		if not by_role.has(r):
			card.show_empty()
			continue
		var p: PlayerData = by_role[r]
		card.show_pilot(p.id, MentalSystem.trust(_gm.season_state, p.id),
				StressSystem.value(_gm.season_state, p.id))


func _on_pilot_pressed(pilot_id: int) -> void:
	var sheet: HubSheet = SeasonPilotDetail.open(self, pilot_id)
	if sheet != null:
		sheet.closed.connect(refresh)


# ── Button handlers ──────────────────────────────────────────────────────────
func _on_start_pressed() -> void:
	# Facilities still without a research → ask first (user decision 2026-10-09).
	var unset: Array = ResearchSystem.unset_facilities(_gm.season_state)
	if unset.is_empty():
		_start_week()
		return
	if _start_confirm == null:
		_start_confirm = ConfirmPopup.create()
		add_child(_start_confirm)
		_start_confirm.confirmed.connect(_start_week)
	var names: Array = []
	for fid in unset:
		names.append(FacilitySystem.facility_name(String(fid)))
	_start_confirm.open(Loc.t(L.FACILITY_UI_HUB_UNSET_TITLE),
			Loc.t(L.FACILITY_UI_HUB_UNSET_BODY, {"facilities": Loc.t(L.UI_LIST_SEPARATOR).join(names)}),
			Loc.t(L.UI_BUTTON_CANCEL), Loc.t(L.FACILITY_UI_HUB_UNSET_GO))


func _start_week() -> void:
	if _hub != null:
		# The week opens on the training plan — the press conference moved to Sunday
		# afternoon, after the match (`SeasonHub.press_pending`).
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


## F6 단독 실행 미리보기 — 메모리 런 + 두 주 치른 리그(`resources/UiPreview.gd`). 로스터 ·
## 관리 카드는 `_ready` 의 `refresh()` 가 채운다. 관리 카드를 누르면 실제 시트가 뜬다(메모리만).
## "이번 주 시작" · "리그 순위" 는 호스트(`SeasonHub`)가 없어 출력만 한다.
func _fill_preview() -> void:  # l10n-ignore
	UiPreview.stage(self)
	if UiPreview.ensure_run() == null:
		return
	var lm: LeagueManager = UiPreview.ensure_league(self)
	UiPreview.trace(_start_btn.pressed, "이번 주 시작")
	UiPreview.trace(_standings_btn.pressed, "리그 순위")
	_fill_preview_host_lines.call_deferred(lm)


## 주차 · 이번 주 경기 두 줄은 `refresh()` 가 호스트의 달력 · 리그에서 읽는다 — 단독 실행엔
## 호스트가 없어 같은 글을 미리보기 리그로 채운다(`_ready` 의 `refresh()` 뒤에 돈다).
func _fill_preview_host_lines(lm: LeagueManager) -> void:
	var s: Dictionary = _gm.season_state
	var phase: int = int(s["current_phase"])
	_week_lbl.text = Loc.t(L.SEASON_HUB_WEEK_PROGRESS, {"week": int(s["phase_week"]),
			"max": int(CalendarSystem.PHASE_WEEKS.get(phase, 1))})
	var nxt = lm.player_match_this_week()
	if nxt == null:
		_next_match_lbl.text = Loc.t(L.SEASON_HUB_NO_MATCH)
		return
	var pid: int = int(s["player_team_id"])
	var opp: int = int(nxt["team_b"]) if int(nxt["team_a"]) == pid else int(nxt["team_a"])
	_next_match_lbl.text = Loc.t(L.SEASON_HUB_MATCH_LEAGUE, {"team": lm.team_name(opp)})
