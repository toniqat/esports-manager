class_name SeasonHub
extends Control

# Thin orchestrator for the weekly outgame loop. Owns the screen-routing
# state machine and the per-week flow.
#
# ── A week ───────────────────────────────────────────────────
# The week flows one day at a time (`season_state["week_day"]` 0..6):
#
#   HUB (before the week) → TRAINING (tile board) → WEEK
#     Mon–Fri  training days (morning training → talk → afternoon → evening)
#     Sat      morning = stadium → MatchFlow PREP + BAN_PICK (split: picks are
#              stored in `pending_match.picks`, MatchFlow returns here), then a
#              normal afternoon / evening without training
#     Sun      morning = stadium → MatchFlow resumes at LAUNCH with the stored
#              picks → BattleSim → result → STANDINGS → afternoon = PRESS
#              (result-reactive) → evening → week end → HUB
#
# One player match per week, always on Sunday (`CalendarSystem.MATCH_DAY`); the
# AI matches of that round resolve on Sunday too. A week without a player match
# has plain Sat / Sun (no stadium, no press). Training is settled per weekday
# (`TrainingBoard.apply_day_training(day)`).
#
# Autosave triggers: run start (first HUB), pre-ban-pick / post-ban-pick
# (MatchFlow, Saturday), pre-match (Sunday launch, `match_resume` = the stored
# picks), post-match, and every step of the week (`autosave(reason)`).

@onready var _gm: Node = get_node("/root/GameManager")
@onready var _placeholder: Label = get_node_or_null("Placeholder")

# 런 준비(시나리오 · 팀 · 5인 편성)는 시즌 밖(`features/meta/run_setup/`)으로
# 나갔다 — 시즌은 언제나 HUB 부터 연다.
enum Screen { HUB, PRESS, TRAINING, WEEK, LEAGUE, PLAYOFF, INTL_BRACKET, GAME_OVER, ENDING }

var current_screen: int = Screen.HUB
var _hub_view: HubView = null
var _press_view: PressConferenceView = null
var _training_view: TrainingView = null
var _week_view: WeekProgressView = null
var _league_view: LeagueView = null
var _bracket_view: BracketView = null
var _intl_bracket_view: IntlBracketView = null
var _game_over_view: GameOverView = null
var _ending_view: EndingView = null
# 이 런의 결론 화면(Screen.GAME_OVER / ENDING), 아직 없으면 -1.
var _run_end_screen: int = -1
## 다음 HUB 표시 때 허브 하단 토스트로 띄울 줄들(주 마감 수지 등). 여러 줄이면
## 차례로 하나씩이 아니라 마지막 것 하나만 보인다 — 같은 순간에 둘을 쌓지 않는다.
var hub_toasts: Array = []


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
		if not tm.playoff_lost.is_connected(_on_playoff_lost):
			tm.playoff_lost.connect(_on_playoff_lost)

	# Phase 8 — INTL signals.
	var intl: InternationalTournament = get_node_or_null("InternationalTournament") as InternationalTournament
	if intl != null:
		if not intl.intl_completed.is_connected(_on_intl_completed):
			intl.intl_completed.connect(_on_intl_completed)
		if not intl.intl_failed_campaign.is_connected(_on_intl_failed_campaign):
			intl.intl_failed_campaign.connect(_on_intl_failed_campaign)

	# 페이즈 POM — 페이즈가 넘어가는 순간 직전 페이즈를 닫는다(`RunStats.finalize_phase`).
	var cal: CalendarSystem = get_node_or_null("CalendarSystem") as CalendarSystem
	if cal != null and not cal.phase_changed.is_connected(_on_phase_changed_close_pom):
		cal.phase_changed.connect(_on_phase_changed_close_pom)

	# Returning from BattleSim: a pending_match with winner_side set means we
	# just finished a match. Apply the result, resolve the AI matches of that
	# **same match day**, then route to the standings/bracket screen. The
	# player presses 확인 there and drops back onto the week's day cursor.
	#
	# Signal handlers in record_result may route to ENDING / GAME_OVER (the
	# REGULAR_INTL win/loss paths). Respect that — only fall back to
	# STANDINGS if nothing else routed us.
	if _consume_pending_match_result():
		# 결론 핸들러(`_enter_run_end`)는 `_run_end_screen` 을 동기로 세운다 —
		# 아직 아무도 결론을 내지 않았을 때만 순위 / 브래킷 화면으로 간다.
		if _run_end_screen < 0:
			current_screen = _post_match_screen()
		_gm.season_state["match_resume"] = null
		# Only on the match day — a result consumed on another day (editor cheat on
		# Saturday) leaves the round's AI matches for Sunday.
		var md: int = CalendarSystem.matchday_of(week_day())
		if md >= 0:
			_resolve_ai_for_matchday(md)
		# Post-match save: results are now applied to standings/bracket. Save
		# before any cascade (ENDING/GAME_OVER routing or just sitting on the
		# standings view) so closing here preserves the outcome.
		autosave("post_match")
		_route()
		return
	current_screen = _resume_screen()
	_route()


## Where a freshly loaded run continues: the week screen when a week is running
## (`week_day` ≥ 0 — every day stage, the Saturday picks, the Sunday press and open
## dialogs are read back from the records), else the hub. Entering a screen other
## than HUB skips `_show_hub`, so the schedule / tournament bootstrap it does runs
## here first.
func _resume_screen() -> int:
	if week_day() >= 0:
		_ensure_schedule()
		return Screen.WEEK
	return Screen.HUB


# Switch the active screen.
func goto(screen: int) -> void:
	current_screen = screen
	_route()


func _route() -> void:
	print("SeasonHub: route to %s" % Screen.keys()[current_screen])
	match current_screen:
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


func _show_hub() -> void:
	_ensure_hub_view()
	# 런 시작 직후의 첫 HUB 인지는 일정을 깔기 **전에** 잰다(아래 참고).
	var run_start: bool = _is_run_start()
	_ensure_schedule()
	_hide_all_screens()
	if _hub_view:
		_hub_view.ensure_view()
		_hub_view.visible = true
		if not hub_toasts.is_empty():
			_hub_view.show_toast(String(hub_toasts.back()))
			hub_toasts.clear()
	# 자동 저장 1번 — 런 시작 후. 런 준비(`RunSetupScreen` → `start_run`)든
	# 에디터 직접 실행(`init_season`)이든 새 런의 첫 HUB 에서 한 번.
	if run_start:
		autosave("run_start")


## First-time HUB entry (post-run-start) seeds the PRESEASON schedule. Idempotent
## afterwards. Also bootstraps any pending tournament that should be active
## this week (covers the "load a save mid-INTL or mid-playoff" path).
func _ensure_schedule() -> void:
	var league: LeagueManager = get_node_or_null("LeagueManager") as LeagueManager
	if league != null:
		league.ensure_phase_scheduled()
	var tm: TournamentManager = get_node_or_null("TournamentManager") as TournamentManager
	if tm != null and tm.has_method("ensure_active"):
		tm.ensure_active()
	var intl: InternationalTournament = get_node_or_null("InternationalTournament") as InternationalTournament
	if intl != null and intl.has_method("ensure_active"):
		intl.ensure_active()


## 새 런의 첫 HUB 인가 — **저장 키를 늘리지 않고 상태에서 읽는다.** PRESEASON
## 일정은 첫 HUB 진입(`ensure_phase_scheduled`)이 깔고, 그 직후의 저장부터는
## 언제나 일정이 들어 있다. 그래서 "PRESEASON 1주차, 주 시작 전, PRESEASON
## 일정 없음" 은 런을 막 연 순간에만 참이다.
func _is_run_start() -> bool:
	var s: Dictionary = _gm.season_state
	if int(s.get("current_phase", -1)) != GameEnums.SeasonPhase.PRESEASON:
		return false
	if int(s.get("phase_week", 0)) != 1 or int(s.get("week_day", -1)) != -1:
		return false
	for m in s.get("match_schedule", []):
		if int((m as Dictionary).get("phase", -1)) == GameEnums.SeasonPhase.PRESEASON:
			return false
	return true


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
	_settle_run("fail")
	_ensure_game_over_view()
	_hide_all_screens()
	if _game_over_view:
		_game_over_view.ensure_view()
		_game_over_view.visible = true


func _show_ending() -> void:
	_settle_run("clear")
	_ensure_ending_view()
	_hide_all_screens()
	if _ending_view:
		_ending_view.ensure_view()
		_ending_view.visible = true


func _ensure_hub_view() -> void:
	if _hub_view != null:
		return
	_hub_view = HubView.create()
	_hub_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_hub_view)


func _ensure_training_view() -> void:
	if _training_view != null:
		return
	_training_view = TrainingView.create()
	_training_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_training_view)


func _ensure_press_view() -> void:
	if _press_view != null:
		return
	_press_view = PressConferenceView.create()
	_press_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_press_view)


func _ensure_week_view() -> void:
	if _week_view != null:
		return
	_week_view = WeekProgressView.create()
	_week_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_week_view)


func _ensure_league_view() -> void:
	if _league_view != null:
		return
	_league_view = LeagueView.create()
	_league_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_league_view)


func _ensure_bracket_view() -> void:
	if _bracket_view != null:
		return
	_bracket_view = BracketView.create()
	_bracket_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bracket_view)


func _ensure_intl_bracket_view() -> void:
	if _intl_bracket_view != null:
		return
	_intl_bracket_view = IntlBracketView.create()
	_intl_bracket_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_intl_bracket_view)


func _ensure_game_over_view() -> void:
	if _game_over_view != null:
		return
	_game_over_view = GameOverView.create()
	_game_over_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_game_over_view)


func _ensure_ending_view() -> void:
	if _ending_view != null:
		return
	_ending_view = EndingView.create()
	_ending_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_ending_view)


# ── Weekly flow handlers (called by views) ────────────────────────

## The press conference is answered (Sunday afternoon) → back to the week (Sunday
## evening). Outside a running week (old saves) → the training plan.
func on_press_finished() -> void:
	goto(Screen.WEEK if week_day() >= 0 else Screen.TRAINING)


## The week screen's "기자회견" (Sunday afternoon, `press_pending`).
func open_press() -> void:
	goto(Screen.PRESS)


## TrainingView "훈련 확정" → **주가 시작된다**. 판을 정산하지 않고
## 요일 커서만 월요일에 세운다 — 정산은 시간 경과 화면이 그날에 닿을 때
## 하루씩 한다(`TrainingBoard.apply_day_training`).
func on_training_confirmed() -> void:
	var board: TrainingBoard = get_node_or_null("TrainingBoard") as TrainingBoard
	if board != null:
		board.reset_week_progress()
	_gm.season_state["week_day"] = 0
	autosave("week_start")
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


## Saturday morning still needs the match prep: a player match is scheduled this
## Sunday and its picks are not stored yet (`match_picks_ready`).
func needs_match_prep(day: int) -> bool:
	if day != CalendarSystem.PREP_DAY or bool(_gm.season_state.get("run_over", false)):
		return false
	if not has_player_match_on_day(CalendarSystem.MATCH_DAY):
		return false
	return not match_picks_ready()


## The Saturday ban/pick of this week's Sunday match is stored (`pending_match.picks`)
## and still belongs to that match.
func match_picks_ready() -> bool:
	var pm: Variant = _gm.season_state.get("pending_match", null)
	if not (pm is Dictionary) or not ((pm as Dictionary).get("picks", null) is Dictionary):
		return false
	var ref: Dictionary = _player_match_ref(CalendarSystem.matchday_of(CalendarSystem.MATCH_DAY))
	return not ref.is_empty() and String(ref["source"]) == String((pm as Dictionary).get("source", "")) \
			and int(ref["idx"]) == int((pm as Dictionary).get("schedule_idx", -1))


## "win" / "loss" of my match played this week, "" when none was played yet.
func player_result_this_week() -> String:
	var s: Dictionary = _gm.season_state
	var pid: int = int(s["player_team_id"])
	var phase: int = int(s["current_phase"])
	var pweek: int = int(s["phase_week"])
	var t: Variant = s.get("current_tournament", null)
	if t is Dictionary and int((t as Dictionary).get("phase_at_start", phase)) == phase:
		for m_raw in ((t as Dictionary).get("bracket", []) as Array):
			var r: String = _own_result(m_raw, pid, pweek)
			if r != "":
				return r
	for m_raw in (s.get("match_schedule", []) as Array):
		if int((m_raw as Dictionary).get("phase", -1)) != phase or bool((m_raw as Dictionary).get("void", false)):
			continue
		var r2: String = _own_result(m_raw, pid, pweek)
		if r2 != "":
			return r2
	return ""


static func _own_result(m_raw: Variant, pid: int, pweek: int) -> String:
	var m: Dictionary = m_raw
	if not bool(m.get("played", false)) or int(m.get("phase_week", -1)) != pweek:
		return ""
	if int(m.get("team_a", -1)) != pid and int(m.get("team_b", -1)) != pid:
		return ""
	return "win" if int(m.get("winner", -1)) == pid else "loss"


## Sunday afternoon: my match of the week is played and its press conference is not
## answered yet.
func press_pending() -> bool:
	return week_day() == CalendarSystem.MATCH_DAY and player_result_this_week() != "" \
			and not MentalSystem.press_answered(_gm.season_state)


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


## The week screen's "경기 시작" (Sunday morning) → this day's player match. With the
## Saturday picks stored, MatchFlow resumes at LAUNCH from them (`match_resume`, the
## same path as a mid-match resume) and goes straight to BattleSim; without them
## (old save, skipped prep) the whole PREP → BAN_PICK → BattleSim flow runs.
func on_week_day_match_start() -> void:
	var md: int = CalendarSystem.matchday_of(week_day())
	if md < 0:
		return
	if match_picks_ready():
		var s: Dictionary = _gm.season_state
		s["match_resume"] = ((s["pending_match"] as Dictionary)["picks"] as Dictionary).duplicate(true)
		autosave("pre_match")
		get_tree().change_scene_to_file("res://scenes/MatchFlow.tscn")
		return
	_launch_player_match_on_day(md)


## The week screen's "경기 준비" (Saturday morning) → MatchFlow PREP + BAN_PICK for
## this Sunday's match. `pending_match.split` makes MatchFlow store the picks and come
## back here instead of launching BattleSim.
func on_week_day_match_prep() -> void:
	if not needs_match_prep(week_day()):
		return
	_launch_player_match_on_day(CalendarSystem.matchday_of(CalendarSystem.MATCH_DAY), true)


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
	autosave("next_day")
	goto(Screen.WEEK)


## 순위 · 대진표 화면의 "확인" → 주가 돌고 있으면 그 요일로, 아니면 허브로.
## 허브에서 "리그 순위"로 궸어본 경우와 경기 직후에 띄운 경우가 같은 버튼을
## 나눠 쓰므로, 돌아갈 자리는 버튼이 아니라 **주 진행 상태**가 정한다.
## Right after the Sunday match the press conference comes next (Sunday afternoon).
func on_standings_confirmed() -> void:
	if press_pending():
		goto(Screen.PRESS)
	elif week_day() >= 0:
		goto(Screen.WEEK)
	else:
		goto(Screen.HUB)


## 주를 닫고 다음 주 직전(HUB)으로. 달력을 한 주 굴리고 판을 비운다.
func _end_week() -> void:
	# 혼자 남은 AI 경기(예: 배정이 어긋난 주)가 있으면 여기서 정리된다.
	_resolve_remaining_ai_for_week()
	# 주 마감 정산(M3~M7) — **달력이 넘어가기 전**, 순서 고정(계획서 §11.1):
	# 재무 수지 → 메크 연구 → 멘탈 주간 초기화 → 감독 · 선수 일시 보정 감소.
	var s: Dictionary = _gm.season_state
	var fin: Dictionary = FinanceSystem.settle_week(s)
	if String(fin.get("toast", "")) != "":
		hub_toasts.append(String(fin["toast"]))
	MechMastery.settle_week(s)
	MentalSystem.end_week(s)
	# A match that never got a result (stale Saturday picks) does not outlive its week.
	var pm: Variant = s.get("pending_match", null)
	if pm is Dictionary and int((pm as Dictionary).get("winner_side", -1)) < 0:
		s["pending_match"] = null
	StaffSystem.decay_mods(s)
	PilotMods.decay_week(s)
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
	autosave("post_week")


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
# populate pending_match, scene-change to MatchFlow. `split` = Saturday prep:
# MatchFlow stops after ban/pick and stores the picks (`pending_match.picks`).
func _launch_player_match_on_day(matchday: int, split: bool = false) -> void:
	var ref: Dictionary = _player_match_ref(matchday)
	if ref.is_empty():
		return
	var pm: Dictionary = {
		"source":        String(ref["source"]),
		"schedule_idx":  int(ref["idx"]),
		"enemy_team_id": int(ref["enemy"]),
		"winner_side":   -1,
	}
	if split:
		pm["split"] = true
	_gm.season_state["pending_match"] = pm
	get_tree().change_scene_to_file("res://scenes/MatchFlow.tscn")


## The player's unplayed match on that matchday: `{source, idx, enemy}` (`idx` = bracket
## index for "intl" / "playoff", `match_schedule` index for "league"), {} when none.
func _player_match_ref(matchday: int) -> Dictionary:
	var s: Dictionary = _gm.season_state
	var pid: int = int(s["player_team_id"])
	var source: String = _find_player_match_source(matchday)
	var idx: int = -1
	match source:
		"intl":
			idx = (get_node_or_null("InternationalTournament") as InternationalTournament) \
					.find_player_match_on_day_idx(matchday)
		"playoff":
			idx = (get_node_or_null("TournamentManager") as TournamentManager) \
					.find_player_match_on_day_idx(matchday)
		"league":
			idx = _league_match_idx(matchday)
	if idx < 0:
		return {}
	var m: Dictionary = (s["match_schedule"] as Array)[idx] if source == "league" \
			else (s["current_tournament"]["bracket"] as Array)[idx]
	return {"source": source, "idx": idx, "enemy": _other_team(m, pid)}


## `match_schedule` index of my unplayed league match this week on that matchday, or -1.
func _league_match_idx(matchday: int) -> int:
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
		return i
	return -1


## Resolves only that matchday's AI matches (matchday 0 = Sunday, the only one).
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
		# Saturday ban/pick done, Sunday match still to come — keep it with its picks.
		if (pm as Dictionary).get("picks", null) is Dictionary:
			return false
		s["pending_match"] = null
		return false
	var idx: int = int(pm["schedule_idx"])
	var pid: int = int(s["player_team_id"])
	var enemy_id: int = int(pm["enemy_team_id"])
	var winner_team_id: int = pid if winner_side == 0 else enemy_id
	var source: String = String(pm.get("source", "league"))

	# 경기 통계 · MVP 집계(`season_state.run_stats`) — 결과를 일정에 반영하기
	# **전에** 한 번. 반영이 신호를 타고 곧장 엔딩 / 게임오버 정산까지 갈 수
	# 있는데(정산이 지금 페이즈의 POM 을 닫는다), 그보다 늦으면 마지막 경기가
	# 집계에서 빠진다. 두 번 불려도 `stats_recorded` 표시로 한 번만 센다.
	RunStats.record_match(s, pm as Dictionary)
	# M4 · M6 · M7 — 숙련도(출전 메크) · 성적 보너스 · "다음 경기까지" 보정 소비.
	# RunStats 와 같은 이유로 결과 반영(→ 정산이 될 수 있다) **전에**.
	MechMastery.record_match(s, pm as Dictionary)
	FinanceSystem.record_match(s, pm as Dictionary, winner_side == 0)
	PilotMods.consume_match(s)
	StressSystem.record_match(s, pm as Dictionary)
	# §15 — limit-break goals and the awakening gauge read the match rows.
	LimitBreak.record_match(s, pm as Dictionary)
	Awakening.on_match(s, pm as Dictionary)

	if source == "playoff":
		_apply_playoff_result(idx, winner_team_id)
	elif source == "intl":
		_apply_intl_result(idx, winner_team_id)
	else:
		_apply_league_result(idx, winner_team_id)

	s["pending_match"] = null
	return true


## 페이즈는 언제나 한 칸씩만 넘어가므로(`CalendarSystem._advance_phase`) 닫을
## 페이즈는 `new_phase - 1` 이다. 이미 닫혔거나 경기가 없던 페이즈면 무위다.
func _on_phase_changed_close_pom(new_phase: int) -> void:
	if new_phase > 0:
		RunStats.finalize_phase(_gm.season_state, new_phase - 1)


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


# ── Run end — six titles or bust (§3 M2) ───────────────────────────────────
# 여섯 대회 중 하나라도 우승을 놓치면 그 결과 직후 GAME_OVER, 마지막
# REGULAR_INTL 우승이면 ENDING. 두 화면 다 들어서는 순간 정산한다.

## 리그 페이즈 플레이오프 진출 실패.
func _on_playoff_failed(_phase: int) -> void:
	_enter_run_end(Screen.GAME_OVER)


## 리그 페이즈 플레이오프 4강 / 결승 패배.
func _on_playoff_lost(_phase: int) -> void:
	_enter_run_end(Screen.GAME_OVER)


## 국제대회 우승. 앞의 두 국제대회는 다음 리그 페이즈로 이어진다 — 주 마감이
## 페이즈를 넘긴다. 마지막(REGULAR_INTL)만 엔딩.
func _on_intl_completed(phase: int, champion_team_id: int) -> void:
	if phase != GameEnums.SeasonPhase.REGULAR_INTL:
		return
	if champion_team_id != int(_gm.season_state["player_team_id"]):
		return   # InternationalTournament 는 이 경우 intl_failed_campaign 을 쏜다
	_enter_run_end(Screen.ENDING)


## 국제대회 탈락(어느 국제대회든).
func _on_intl_failed_campaign(_phase: int) -> void:
	_enter_run_end(Screen.GAME_OVER)


## 런의 결론(GAME_OVER / ENDING)을 정한다. 결론은 처음 것 하나로 고정되고,
## 정산은 **지금 바로**(뒤따르는 `autosave` 가 쓰지 않게), 화면 전환은
## **프레임 끝에** 한다 — 시그널은 `_end_week` 의 달력 굴리기나 `_show_hub` 의
## `ensure_active()` 한가운데서 터질 수 있고, 거기서 바로 그리면 그 함수의
## 나머지가 허브를 다시 세워 결론 화면을 덮는다.
func _enter_run_end(screen: int) -> void:
	if _run_end_screen < 0:
		_run_end_screen = screen
	current_screen = _run_end_screen
	_settle_run("clear" if _run_end_screen == Screen.ENDING else "fail")
	_show_run_end.call_deferred()


func _show_run_end() -> void:
	var view: Control = _ending_view if _run_end_screen == Screen.ENDING else _game_over_view
	if current_screen == _run_end_screen and view != null and view.visible:
		return   # 이미 그 화면이다(경기 직후 `_ready` 가 먼저 그렸다)
	current_screen = _run_end_screen
	_route()


## 런 정산은 한 런에 한 번 — GAME_OVER / ENDING 에 처음 들어설 때.
## 정산이 `run.save` 를 지우고 `run_over` 를 세우면 그 뒤 `autosave` 는 쓰지 않는다.
func _settle_run(outcome: String) -> void:
	if bool(_gm.season_state.get("run_over", false)):
		return
	RunResult.settle_current_run(outcome)
	_gm.season_state["run_over"] = true


# ── Save system — autosave helper ──────────────────────────────────────────
## Writes the run file. Also called by the press / week screens after every stage change
## and answer (`features/save_load/README.md` "Auto-save trigger points").
func autosave(reason: String) -> void:
	# 정산이 끝난 런은 저장하지 않는다 — 경기 직후 저장(`_ready`)이나 주 마감
	# 저장이 결과 처리 뒤에 와도 지워진 run.save 가 되살아나지 않게.
	if bool(_gm.season_state.get("run_over", false)):
		print("SeasonHub: autosave (%s) skipped — run is over" % reason)
		return
	var err: String = SaveSystem.save_run()
	if err != "":
		push_warning("SeasonHub: autosave (%s) failed — %s" % [reason, err])
	else:
		print("SeasonHub: autosave (%s) → %s" % [reason, SaveSystem.run_path()])
