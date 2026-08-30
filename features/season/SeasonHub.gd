class_name SeasonHub
extends Control

# Thin orchestrator for the weekly outgame loop. Owns the screen-routing
# state machine and the per-week flow.
#
# ── 한 주 ───────────────────────────────────────────────────
# 주는 **이레 내내 한 날씩 흘러간다**(`season_state["week_day"]` 0..6).
#
#   HUB(주 시작 직전) → PRESS(기자회견) → TRAINING(주간 훈련 타일 배치)
#     → WEEK 월 → 화 → 수 → 목 → 금          (매일 그날 훈련 결과 + 확인)
#     → WEEK 토 → 경기가 있으면 MatchFlow → BattleSim → STANDINGS → 확인 → WEEK 토
#     → WEEK 일 → 같은 식
#     → 주 종료 → CalendarSystem.advance_week → HUB
#
# **훈련은 요일 단위로 먹는다** — 예전에는 TRAINING 확정이
# `apply_week_training()` 한 번으로 한 주를 통째로 정산하고 TRAINING_RESULT
# 한 장이 그 결과를 보였는데, 시간 경과 화면이 "그날 무슨 일이 있었는가"를
# 요일마다 묻게 되면서 정산도 `TrainingBoard.apply_day_training(day)` 로
# 쪼개졌다. `Screen.TRAINING_RESULT` 와 `TrainingResultView` 는 그때
# **삭제됐다** — 주간 결산 한 장이 하던 일을 요일 다섯 장이 나누어 한다.
#
# ── 주말 ──────────────────────────────────────────────────
# 토 · 일 **이틀이 경기일**이다(`CalendarSystem.MATCH_DAYS`). 리그는 한 주에
# 두 라운드를 돌리므로 그 둘이 각각 한 날을 차지하고, 토너먼트(플레이오프 ·
# 국제대회)는 주에 라운드 하나라 언제나 **토요일**에만 선다.
# 그날 경기가 배정돼 있지 않으면 그 요일은 그냥 넘어간다.
#
# Autosave triggers (5):
#   1. Post-draft         — DRAFT → HUB on a fresh campaign.
#   2. Pre-ban-pick       — MatchFlow.gd, after PREP confirmation.
#   3. Post-gambit        — MatchFlow.gd, after jungle direction picked.
#   4. Post-match         — returning from BattleSim, once the result is applied.
#   5. Post-week-end      — landing on HUB at the start of a new week.

@onready var _gm: Node = get_node("/root/GameManager")
@onready var _placeholder: Label = get_node_or_null("Placeholder")
@onready var _draft: Control = get_node_or_null("TeamDraft")

enum Screen { DRAFT, HUB, PRESS, TRAINING, WEEK, LEAGUE, PLAYOFF, INTL_BRACKET, GAME_OVER, ENDING }

var current_screen: int = Screen.DRAFT
var _hub_view: HubView = null
var _press_view: PressConferenceView = null
var _training_view: TrainingView = null
var _week_view: WeekProgressView = null
var _league_view: LeagueView = null
var _bracket_view: BracketView = null
var _intl_bracket_view: IntlBracketView = null
var _game_over_view: GameOverView = null
var _ending_view: EndingView = null


func _ready() -> void:
	if not _gm.season_state["active"]:
		var err: String = _gm.init_season()
		if err != "":
			push_error("SeasonHub: init_season failed — " + err)
			if _placeholder:
				_placeholder.text = "Season init failed:\n" + err
				_placeholder.visible = true
			return

	# Phase 7 — playoff signals from TournamentManager.
	var tm: TournamentManager = get_node_or_null("TournamentManager") as TournamentManager
	if tm != null:
		if not tm.playoff_failed_qualification.is_connected(_on_playoff_failed):
			tm.playoff_failed_qualification.connect(_on_playoff_failed)

	# Phase 8 — INTL signals.
	var intl: InternationalTournament = get_node_or_null("InternationalTournament") as InternationalTournament
	if intl != null:
		if not intl.intl_completed.is_connected(_on_intl_completed):
			intl.intl_completed.connect(_on_intl_completed)
		if not intl.intl_failed_campaign.is_connected(_on_intl_failed_campaign):
			intl.intl_failed_campaign.connect(_on_intl_failed_campaign)

	# Returning from BattleSim: a pending_match with winner_side set means we
	# just finished a match. Apply the result, resolve the AI matches of that
	# **same match day**, then route to the standings/bracket screen. The
	# player presses 확인 there and drops back onto the week's day cursor.
	#
	# 그날 경기만 정산하는 것이 요점이다 — 주 통째로 돌리면 토요일 경기를
	# 마치고 보는 순위표에 아직 치르지도 않은 일요일 결과가 미리 들어가 있게 된다.
	#
	# Signal handlers in record_result may route to ENDING / GAME_OVER (the
	# REGULAR_INTL win/loss paths). Respect that — only fall back to
	# STANDINGS if nothing else routed us.
	if _consume_pending_match_result():
		if current_screen == Screen.DRAFT:
			current_screen = _post_match_screen()
		_gm.season_state["match_resume"] = null
		var md: int = CalendarSystem.matchday_of(week_day())
		if md >= 0:
			_resolve_ai_for_matchday(md)
		else:
			_resolve_remaining_ai_for_week()
		# Post-match save: results are now applied to standings/bracket. Save
		# before any cascade (ENDING/GAME_OVER routing or just sitting on the
		# standings view) so closing here preserves the outcome.
		_autosave("post_match")
		_route()
		return
	_route()


# Switch the active screen.
func goto(screen: int) -> void:
	# DRAFT → HUB is the brand-new-campaign save trigger. After this point the
	# slot has at least one valid save to load on the title screen.
	var was_draft: bool = current_screen == Screen.DRAFT
	current_screen = screen
	_route()
	if was_draft and screen == Screen.HUB:
		_autosave("DRAFT→HUB")


func _route() -> void:
	print("SeasonHub: route to %s" % Screen.keys()[current_screen])
	match current_screen:
		Screen.DRAFT:
			_show_draft()
		Screen.HUB:
			_show_hub()
		Screen.PRESS:
			_show_press()
		Screen.TRAINING:
			_show_training()
		Screen.WEEK:
			_show_week()
		Screen.LEAGUE:
			_show_league()
		Screen.PLAYOFF:
			_show_playoff()
		Screen.INTL_BRACKET:
			_show_intl_bracket()
		Screen.GAME_OVER:
			_show_game_over()
		Screen.ENDING:
			_show_ending()
		_:
			_show_hub()


func _hide_all_screens() -> void:
	if _draft:
		_draft.visible = false
	if _hub_view:
		_hub_view.visible = false
	if _press_view:
		_press_view.visible = false
	if _training_view:
		_training_view.visible = false
	if _week_view:
		_week_view.visible = false
	if _league_view:
		_league_view.visible = false
	if _bracket_view:
		_bracket_view.visible = false
	if _intl_bracket_view:
		_intl_bracket_view.visible = false
	if _game_over_view:
		_game_over_view.visible = false
	if _ending_view:
		_ending_view.visible = false
	if _placeholder:
		_placeholder.visible = false


func _show_draft() -> void:
	if _draft and _draft.has_method("ensure_view"):
		_draft.ensure_view()
	_hide_all_screens()
	if _draft:
		_draft.visible = true


func _show_hub() -> void:
	_ensure_hub_view()
	# First-time HUB entry (post-draft) seeds the PRESEASON schedule. Idempotent
	# afterwards. Also bootstraps any pending tournament that should be active
	# this week (covers the "load a save mid-INTL or mid-playoff" path).
	var league: LeagueManager = get_node_or_null("LeagueManager") as LeagueManager
	if league != null:
		league.ensure_phase_scheduled()
	var tm: TournamentManager = get_node_or_null("TournamentManager") as TournamentManager
	if tm != null and tm.has_method("ensure_active"):
		tm.ensure_active()
	var intl: InternationalTournament = get_node_or_null("InternationalTournament") as InternationalTournament
	if intl != null and intl.has_method("ensure_active"):
		intl.ensure_active()
	_hide_all_screens()
	if _hub_view:
		_hub_view.ensure_view()
		_hub_view.visible = true


func _show_training() -> void:
	_ensure_training_view()
	_hide_all_screens()
	if _training_view:
		_training_view.ensure_view()
		_training_view.visible = true


func _show_press() -> void:
	_ensure_press_view()
	_hide_all_screens()
	if _press_view:
		_press_view.ensure_view()
		_press_view.visible = true


func _show_week() -> void:
	_ensure_week_view()
	_hide_all_screens()
	if _week_view:
		_week_view.ensure_view()
		_week_view.visible = true


func _show_league() -> void:
	_ensure_league_view()
	_hide_all_screens()
	if _league_view:
		_league_view.ensure_view()
		_league_view.visible = true


func _show_playoff() -> void:
	_ensure_bracket_view()
	_hide_all_screens()
	if _bracket_view:
		_bracket_view.ensure_view()
		_bracket_view.visible = true


func _show_intl_bracket() -> void:
	_ensure_intl_bracket_view()
	_hide_all_screens()
	if _intl_bracket_view:
		_intl_bracket_view.ensure_view()
		_intl_bracket_view.visible = true


func _show_game_over() -> void:
	_ensure_game_over_view()
	_hide_all_screens()
	if _game_over_view:
		_game_over_view.ensure_view()
		_game_over_view.visible = true


func _show_ending() -> void:
	_ensure_ending_view()
	_hide_all_screens()
	if _ending_view:
		_ending_view.ensure_view()
		_ending_view.visible = true


func _ensure_hub_view() -> void:
	if _hub_view != null:
		return
	_hub_view = HubView.new()
	_hub_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_hub_view)


func _ensure_training_view() -> void:
	if _training_view != null:
		return
	_training_view = TrainingView.new()
	_training_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_training_view)


func _ensure_press_view() -> void:
	if _press_view != null:
		return
	_press_view = PressConferenceView.new()
	_press_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_press_view)


func _ensure_week_view() -> void:
	if _week_view != null:
		return
	_week_view = WeekProgressView.new()
	_week_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_week_view)


func _ensure_league_view() -> void:
	if _league_view != null:
		return
	_league_view = LeagueView.new()
	_league_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_league_view)


func _ensure_bracket_view() -> void:
	if _bracket_view != null:
		return
	_bracket_view = BracketView.new()
	_bracket_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bracket_view)


func _ensure_intl_bracket_view() -> void:
	if _intl_bracket_view != null:
		return
	_intl_bracket_view = IntlBracketView.new()
	_intl_bracket_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_intl_bracket_view)


func _ensure_game_over_view() -> void:
	if _game_over_view != null:
		return
	_game_over_view = GameOverView.new()
	_game_over_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_game_over_view)


func _ensure_ending_view() -> void:
	if _ending_view != null:
		return
	_ending_view = EndingView.new()
	_ending_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_ending_view)


# ── Weekly flow handlers (called by views) ────────────────────────

## 기자회견이 답변까지 끝났다 → 훈련 계획으로.
func on_press_finished() -> void:
	goto(Screen.TRAINING)


## TrainingView "훈련 확정" → **주가 시작된다**. 판을 정산하지 않고
## 요일 커서만 월요일에 세운다 — 정산은 시간 경과 화면이 그날에 닿을 때
## 하루씩 한다(`TrainingBoard.apply_day_training`).
func on_training_confirmed() -> void:
	var board: TrainingBoard = get_node_or_null("TrainingBoard") as TrainingBoard
	if board != null:
		board.reset_week_progress()
	_gm.season_state["week_day"] = 0
	goto(Screen.WEEK)


## 지금 화면이 보고 있는 요일(0 = 월 … 6 = 일). 주 진행 전이면 -1.
func week_day() -> int:
	return int(_gm.season_state.get("week_day", -1))


## 그 요일에 플레이어가 **아직 치르지 않은** 경기가 있는가.
## 시간 경과 화면이 "경기 시작" 버튼을 세울지 "확인"을 세울지를 이걸로 가른다.
func has_player_match_on_day(day: int) -> bool:
	var md: int = CalendarSystem.matchday_of(day)
	if md < 0:
		return false
	return _find_player_match_source(md) != ""


## 그 요일의 상대 팀 이름 (없으면 빈 문자열). 화면의 경기 카드가 쓴다.
func opponent_name_on_day(day: int) -> String:
	var md: int = CalendarSystem.matchday_of(day)
	if md < 0:
		return ""
	var pid: int = int(_gm.season_state["player_team_id"])
	var intl: InternationalTournament = get_node_or_null("InternationalTournament") as InternationalTournament
	if intl != null:
		var i: int = intl.find_player_match_on_day_idx(md)
		if i >= 0:
			var m: Dictionary = (_gm.season_state["current_tournament"]["bracket"] as Array)[i]
			return intl.team_name(_other_team(m, pid))
	var tm: TournamentManager = get_node_or_null("TournamentManager") as TournamentManager
	if tm != null:
		var i2: int = tm.find_player_match_on_day_idx(md)
		if i2 >= 0:
			var m2: Dictionary = (_gm.season_state["current_tournament"]["bracket"] as Array)[i2]
			return _league_team_name(_other_team(m2, pid))
	var league: LeagueManager = get_node_or_null("LeagueManager") as LeagueManager
	if league != null:
		var m3 = league.player_match_on_day(md)
		if m3 != null:
			return league.team_name(_other_team(m3, pid))
	return ""


## 시간 경과 화면의 "경기 시작" → 그 요일의 플레이어 경기를 연다.
func on_week_day_match_start() -> void:
	var md: int = CalendarSystem.matchday_of(week_day())
	if md < 0:
		return
	_launch_player_match_on_day(md)


## 시간 경과 화면의 "확인" → 다음 날로. 일요일이면 주를 닫는다.
##
## 넘어가기 **전에** 그날의 AI 경기를 쓸어 담는다 — 플레이어가 그날
## 경기가 없어 그냥 넘어가는 경우에도 그날 리그는 돌아가야 하기 때문이고,
## 그래야 다음에 보는 순위표가 날짜와 맞는다.
func on_week_day_confirmed() -> void:
	var day: int = week_day()
	var md: int = CalendarSystem.matchday_of(day)
	if md >= 0:
		_resolve_ai_for_matchday(md)
	if day >= CalendarSystem.DAYS_PER_WEEK - 1:
		_end_week()
		return
	_gm.season_state["week_day"] = day + 1
	goto(Screen.WEEK)


## 순위 · 대진표 화면의 "확인" → 주가 돌고 있으면 그 요일로, 아니면 허브로.
## 허브에서 "리그 순위"로 궸어본 경우와 경기 직후에 띄운 경우가 같은 버튼을
## 나눠 쓰므로, 돌아갈 자리는 버튼이 아니라 **주 진행 상태**가 정한다.
func on_standings_confirmed() -> void:
	if week_day() >= 0:
		goto(Screen.WEEK)
	else:
		goto(Screen.HUB)


## 주를 닫고 다음 주 직전(HUB)으로. 달력을 한 주 굴리고 판을 비운다.
func _end_week() -> void:
	# 혼자 남은 AI 경기(예: 배정이 어긋난 주)가 있으면 여기서 정리된다.
	_resolve_remaining_ai_for_week()
	var cal: CalendarSystem = get_node_or_null("CalendarSystem") as CalendarSystem
	if cal != null:
		cal.advance_week()
	# 다음 주 판은 **빈 채로** 시작한다 — 빈 칸은 기본 코스로 정산되므로
	# 비워 두는 것이 손해가 아니고, 비어 있어야 이번 주에 내가 놓은 것이 보인다.
	var board: TrainingBoard = get_node_or_null("TrainingBoard") as TrainingBoard
	if board != null:
		board.reset_for_new_week()
	else:
		_gm.season_state["week_day"] = -1
	current_screen = Screen.HUB
	_route()
	_autosave("post_week")


# ── Player-match handoff ─────────────────────────────────────

## 이번 주에 아직 치르지 않은 플레이어 경기가 하나라도 있는가.
func has_player_match_this_week() -> bool:
	return _find_player_match_source(-1) != ""


## 그 경기일의 플레이어 경기가 어느 대회 것인가 — `"intl"` / `"playoff"` /
## `"league"` / `""`(없음). 우선순위는 예전부터 INTL > 플레이오프 > 리그다.
## `matchday < 0` 이면 이번 주 아무 날이나.
func _find_player_match_source(matchday: int) -> String:
	var intl: InternationalTournament = get_node_or_null("InternationalTournament") as InternationalTournament
	if intl != null and intl.find_player_match_on_day_idx(matchday) >= 0:
		return "intl"
	var tm: TournamentManager = get_node_or_null("TournamentManager") as TournamentManager
	if tm != null and tm.find_player_match_on_day_idx(matchday) >= 0:
		return "playoff"
	var league: LeagueManager = get_node_or_null("LeagueManager") as LeagueManager
	if league != null and league.player_match_on_day(matchday) != null:
		return "league"
	return ""


static func _other_team(m: Dictionary, pid: int) -> int:
	return int(m["team_b"]) if int(m["team_a"]) == pid else int(m["team_a"])


func _league_team_name(team_id: int) -> String:
	var league: LeagueManager = get_node_or_null("LeagueManager") as LeagueManager
	if league != null:
		return league.team_name(team_id)
	return "Team %d" % team_id


# Find the player's match on that matchday (priority INTL > playoff > league),
# populate pending_match, scene-change to MatchFlow.
func _launch_player_match_on_day(matchday: int) -> void:
	match _find_player_match_source(matchday):
		"intl":
			_launch_bracket_match("intl",
					(get_node_or_null("InternationalTournament") as InternationalTournament)
							.find_player_match_on_day_idx(matchday))
		"playoff":
			_launch_bracket_match("playoff",
					(get_node_or_null("TournamentManager") as TournamentManager)
							.find_player_match_on_day_idx(matchday))
		"league":
			_launch_league_match(matchday)


func _launch_bracket_match(source: String, idx: int) -> void:
	if idx < 0:
		return
	var s: Dictionary = _gm.season_state
	var pid: int = int(s["player_team_id"])
	var m: Dictionary = (s["current_tournament"]["bracket"] as Array)[idx]
	s["pending_match"] = {
		"source":        source,
		"schedule_idx":  idx,
		"enemy_team_id": _other_team(m, pid),
		"winner_side":   -1,
	}
	get_tree().change_scene_to_file("res://scenes/MatchFlow.tscn")


func _launch_league_match(matchday: int) -> void:
	var s: Dictionary = _gm.season_state
	var pid: int = int(s["player_team_id"])
	var phase: int = int(s["current_phase"])
	var pweek: int = int(s["phase_week"])
	var sched: Array = s["match_schedule"]
	for i in sched.size():
		var m: Dictionary = sched[i]
		if bool(m["played"]):
			continue
		if int(m["phase"]) != phase or int(m["phase_week"]) != pweek:
			continue
		if matchday >= 0 and int(m.get("matchday", 0)) != matchday:
			continue
		if int(m["team_a"]) != pid and int(m["team_b"]) != pid:
			continue
		s["pending_match"] = {
			"source":        "league",
			"schedule_idx":  i,
			"enemy_team_id": _other_team(m, pid),
			"winner_side":   -1,
		}
		get_tree().change_scene_to_file("res://scenes/MatchFlow.tscn")
		return


## 그 경기일의 AI 경기만 정산한다. 토너먼트는 주에 라운드 하나라
## 경기일 0(토)에서만 돈다 — 일요일에 다시 불러도 배정된 경기가 없어 무위다.
func _resolve_ai_for_matchday(matchday: int) -> void:
	if matchday == 0:
		var intl: InternationalTournament = get_node_or_null("InternationalTournament") as InternationalTournament
		if intl != null and intl.is_active():
			intl.resolve_current_week()
		var tm: TournamentManager = get_node_or_null("TournamentManager") as TournamentManager
		if tm != null and tm.is_active():
			tm.resolve_current_week()
	var league: LeagueManager = get_node_or_null("LeagueManager") as LeagueManager
	if league != null:
		league.resolve_matchday(matchday)


# After the player's match returns: apply their result, then auto-resolve any
# remaining AI matches scheduled for this same week (so the standings the
# player sees are complete).
func _resolve_remaining_ai_for_week() -> void:
	var intl: InternationalTournament = get_node_or_null("InternationalTournament") as InternationalTournament
	if intl != null and intl.is_active():
		intl.resolve_current_week()
	var tm: TournamentManager = get_node_or_null("TournamentManager") as TournamentManager
	if tm != null and tm.is_active():
		tm.resolve_current_week()
	var league: LeagueManager = get_node_or_null("LeagueManager") as LeagueManager
	if league != null:
		league.resolve_current_week()


# Pick the right standings/bracket screen for the current state.
func _post_match_screen() -> int:
	var intl: InternationalTournament = get_node_or_null("InternationalTournament") as InternationalTournament
	if intl != null and intl.is_active():
		return Screen.INTL_BRACKET
	var tm: TournamentManager = get_node_or_null("TournamentManager") as TournamentManager
	if tm != null and tm.is_active():
		return Screen.PLAYOFF
	return Screen.LEAGUE


# Drain a finished player match: write the result into the right schedule
# (league or playoff or intl) + standings/bracket and clear pending_match.
# Returns true if a result was applied (i.e., we just returned from BattleSim).
func _consume_pending_match_result() -> bool:
	var s: Dictionary = _gm.season_state
	var pm = s.get("pending_match", null)
	if pm == null:
		return false
	var winner_side: int = int(pm.get("winner_side", -1))
	if winner_side < 0:
		s["pending_match"] = null
		return false
	var idx: int = int(pm["schedule_idx"])
	var pid: int = int(s["player_team_id"])
	var enemy_id: int = int(pm["enemy_team_id"])
	var winner_team_id: int = pid if winner_side == 0 else enemy_id
	var source: String = String(pm.get("source", "league"))

	if source == "playoff":
		_apply_playoff_result(idx, winner_team_id)
	elif source == "intl":
		_apply_intl_result(idx, winner_team_id)
	else:
		_apply_league_result(idx, winner_team_id)

	s["pending_match"] = null
	return true


func _apply_league_result(idx: int, winner_team_id: int) -> void:
	var s: Dictionary = _gm.season_state
	var sched: Array = s["match_schedule"]
	if idx < 0 or idx >= sched.size():
		return
	var entry: Dictionary = sched[idx]
	entry["played"] = true
	entry["winner"] = winner_team_id
	var league: LeagueManager = get_node_or_null("LeagueManager") as LeagueManager
	if league != null:
		league.record_result(int(entry["team_a"]), int(entry["team_b"]), winner_team_id)


func _apply_playoff_result(idx: int, winner_team_id: int) -> void:
	var tm: TournamentManager = get_node_or_null("TournamentManager") as TournamentManager
	if tm == null or not tm.is_active():
		return
	tm.record_result(idx, winner_team_id)


func _apply_intl_result(idx: int, winner_team_id: int) -> void:
	var intl: InternationalTournament = get_node_or_null("InternationalTournament") as InternationalTournament
	if intl == null or not intl.is_active():
		return
	intl.record_result(idx, winner_team_id)


# ── Phase 7 — playoff qualification failure ────────────────────────────────
func _on_playoff_failed(_phase: int) -> void:
	current_screen = Screen.GAME_OVER
	_route()


# ── Phase 8 — INTL completion / campaign end ───────────────────────────────
func _on_intl_completed(phase: int, champion_team_id: int) -> void:
	if phase != GameEnums.SeasonPhase.REGULAR_INTL:
		return
	var pid: int = int(_gm.season_state["player_team_id"])
	if champion_team_id == pid:
		current_screen = Screen.ENDING
	else:
		current_screen = Screen.GAME_OVER
	_route()


func _on_intl_failed_campaign(_phase: int) -> void:
	current_screen = Screen.GAME_OVER
	_route()


# ── Save system — autosave helper ──────────────────────────────────────────
func _autosave(reason: String) -> void:
	var slot: int = int(_gm.active_save_slot)
	if slot < 0:
		return
	var err: String = SaveSystem.save_slot(slot)
	if err != "":
		push_warning("SeasonHub: autosave (%s) failed — %s" % [reason, err])
	else:
		print("SeasonHub: autosave (%s) → slot %d" % [reason, slot])
