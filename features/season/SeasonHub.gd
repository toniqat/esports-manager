class_name SeasonHub
extends Control

# Thin orchestrator for the weekly outgame loop. Owns the screen-routing
# state machine and the per-week flow:
#
#   HUB → TRAINING → (apply week) → TRAINING_RESULT → (player match? →
#   MatchFlow → BattleSim → back here) → resolve AI matches → STANDINGS
#   (LEAGUE / PLAYOFF / INTL_BRACKET) → (다음 주 → CalendarSystem.advance_week)
#   → HUB
#
# Autosave triggers (4):
#   1. Post-draft         — DRAFT → HUB on a fresh campaign.
#   2. Pre-ban-pick       — MatchFlow.gd, after PREP confirmation.
#   3. Post-gambit        — MatchFlow.gd, after jungle direction picked.
#   4. Post-week-end      — landing on HUB at the start of a new week
#                            (covers both post-match and no-match weeks).

@onready var _gm: Node = get_node("/root/GameManager")
@onready var _placeholder: Label = get_node_or_null("Placeholder")
@onready var _draft: Control = get_node_or_null("TeamDraft")

enum Screen { DRAFT, HUB, TRAINING, TRAINING_RESULT, MATCH_DAY, LEAGUE, PLAYOFF, INTL_BRACKET, RESULT, GAME_OVER, ENDING }

var current_screen: int = Screen.DRAFT
var _hub_view: HubView = null
var _training_view: TrainingView = null
var _training_result_view: TrainingResultView = null
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
	# just finished a match. Apply the result, resolve any remaining AI
	# matches for the week, then route to the standings/bracket screen so
	# the player can review the week before pressing 다음 주.
	#
	# Signal handlers in record_result may route to ENDING / GAME_OVER (the
	# REGULAR_INTL win/loss paths). Respect that — only fall back to
	# STANDINGS if nothing else routed us.
	if _consume_pending_match_result():
		if current_screen == Screen.DRAFT:
			current_screen = _post_match_screen()
		_gm.season_state["match_resume"] = null
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
		Screen.TRAINING:
			_show_training()
		Screen.TRAINING_RESULT:
			_show_training_result()
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
	if _training_view:
		_training_view.visible = false
	if _training_result_view:
		_training_result_view.visible = false
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


func _show_training_result() -> void:
	_ensure_training_result_view()
	_hide_all_screens()
	if _training_result_view:
		_training_result_view.ensure_view()
		_training_result_view.visible = true


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


func _ensure_training_result_view() -> void:
	if _training_result_view != null:
		return
	_training_result_view = TrainingResultView.new()
	_training_result_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_training_result_view)


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


# ── Weekly flow handlers (called by views) ─────────────────────────────────

# TrainingView "주 진행" → apply training, route to TRAINING_RESULT.
func on_training_save_and_advance() -> void:
	var sched: TrainingScheduler = get_node_or_null("TrainingScheduler") as TrainingScheduler
	if sched == null:
		current_screen = Screen.TRAINING_RESULT
		_route()
		return
	var result: Dictionary = sched.apply_week_training()
	_ensure_training_result_view()
	if _training_result_view != null:
		_training_result_view.result_data = result
		# Set "다음 →" label based on what comes next.
		var has_match: bool = _has_player_match_this_week()
		_training_result_view.set_next_label("경기 준비 →" if has_match else "주간 결산 →")
	current_screen = Screen.TRAINING_RESULT
	_route()


# TrainingResultView "다음" → match (or skip to standings).
func on_training_result_continue() -> void:
	if _has_player_match_this_week():
		_launch_player_match_this_week()
		return
	_resolve_remaining_ai_for_week()
	current_screen = _post_match_screen()
	_route()


# Standings views' "다음 주" → roll calendar one week forward, refill
# training defaults, return to HUB.
func on_proceed_to_next_week() -> void:
	var cal: CalendarSystem = get_node_or_null("CalendarSystem") as CalendarSystem
	if cal != null:
		cal.advance_week()
	var sched: TrainingScheduler = get_node_or_null("TrainingScheduler") as TrainingScheduler
	if sched != null:
		sched.refill_player_team_defaults()
	current_screen = Screen.HUB
	_route()
	_autosave("post_week")


# ── Player-match handoff ───────────────────────────────────────────────────
# Public — called by standings views to decide whether the "다음 주 →"
# button should be enabled (no unplayed player match remaining this week).
func has_player_match_this_week() -> bool:
	return _has_player_match_this_week()


func _has_player_match_this_week() -> bool:
	var intl: InternationalTournament = get_node_or_null("InternationalTournament") as InternationalTournament
	if intl != null and intl.find_player_match_this_week_idx() >= 0:
		return true
	var tm: TournamentManager = get_node_or_null("TournamentManager") as TournamentManager
	if tm != null and tm.find_player_match_this_week_idx() >= 0:
		return true
	var league: LeagueManager = get_node_or_null("LeagueManager") as LeagueManager
	if league != null and league.player_match_this_week() != null:
		return true
	return false


# Find this week's player match (priority INTL > playoff > league), populate
# pending_match, scene-change to MatchFlow.
func _launch_player_match_this_week() -> void:
	if _try_launch_intl_match_this_week():
		return
	if _try_launch_playoff_match_this_week():
		return
	_try_launch_league_match_this_week()


func _try_launch_intl_match_this_week() -> bool:
	var intl: InternationalTournament = get_node_or_null("InternationalTournament") as InternationalTournament
	if intl == null or not intl.is_active():
		return false
	var idx: int = intl.find_player_match_this_week_idx()
	if idx < 0:
		return false
	var s: Dictionary = _gm.season_state
	var pid: int = int(s["player_team_id"])
	var m: Dictionary = (s["current_tournament"]["bracket"] as Array)[idx]
	var enemy_team_id: int = int(m["team_b"]) if int(m["team_a"]) == pid else int(m["team_a"])
	s["pending_match"] = {
		"source":        "intl",
		"schedule_idx":  idx,
		"enemy_team_id": enemy_team_id,
		"winner_side":   -1,
	}
	get_tree().change_scene_to_file("res://scenes/MatchFlow.tscn")
	return true


func _try_launch_playoff_match_this_week() -> bool:
	var tm: TournamentManager = get_node_or_null("TournamentManager") as TournamentManager
	if tm == null or not tm.is_active():
		return false
	var idx: int = tm.find_player_match_this_week_idx()
	if idx < 0:
		return false
	var s: Dictionary = _gm.season_state
	var pid: int = int(s["player_team_id"])
	var m: Dictionary = (s["current_tournament"]["bracket"] as Array)[idx]
	var enemy_team_id: int = int(m["team_b"]) if int(m["team_a"]) == pid else int(m["team_a"])
	s["pending_match"] = {
		"source":        "playoff",
		"schedule_idx":  idx,
		"enemy_team_id": enemy_team_id,
		"winner_side":   -1,
	}
	get_tree().change_scene_to_file("res://scenes/MatchFlow.tscn")
	return true


func _try_launch_league_match_this_week() -> bool:
	var league: LeagueManager = get_node_or_null("LeagueManager") as LeagueManager
	if league == null:
		return false
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
		var ta: int = int(m["team_a"]); var tb: int = int(m["team_b"])
		if ta != pid and tb != pid:
			continue
		var enemy_team_id: int = tb if ta == pid else ta
		s["pending_match"] = {
			"source":        "league",
			"schedule_idx":  i,
			"enemy_team_id": enemy_team_id,
			"winner_side":   -1,
		}
		get_tree().change_scene_to_file("res://scenes/MatchFlow.tscn")
		return true
	return false


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
