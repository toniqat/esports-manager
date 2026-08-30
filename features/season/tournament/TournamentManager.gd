class_name TournamentManager
extends Node

# Phase 7 — playoff bracket manager. Activates on the first week after the
# league weeks end. 4-team single elimination: SF1 (#1 vs #4), SF2 (#2 vs #3),
# then F. Distributed across 2 weeks (SF week + F week) since the campaign
# now progresses one match per week per team. If the player team did not
# finish top-4 the run is over — emits playoff_failed_qualification so
# SeasonHub can route to the game-over screen.

signal playoff_started(phase: int)
signal playoff_failed_qualification(phase: int)
signal playoff_completed(phase: int, champion_team_id: int)

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")
@onready var _league: LeagueManager = null


func _ready() -> void:
	if _hub == null:
		return
	_league = _hub.get_node_or_null("LeagueManager") as LeagueManager
	var cal: CalendarSystem = _hub.get_node_or_null("CalendarSystem") as CalendarSystem
	if cal == null:
		return
	if not cal.week_advanced.is_connected(_on_week_advanced):
		cal.week_advanced.connect(_on_week_advanced)
	if not cal.phase_changed.is_connected(_on_phase_changed):
		cal.phase_changed.connect(_on_phase_changed)


# ── Active state ────────────────────────────────────────────────────────────
func is_active() -> bool:
	var t = _gm.season_state.get("current_tournament", null)
	return t != null and String(t.get("type", "")) == "PLAYOFF"


func bracket() -> Array:
	if not is_active():
		return []
	return _gm.season_state["current_tournament"]["bracket"]


# ── Lifecycle ───────────────────────────────────────────────────────────────
# Bootstrap the playoff bracket on the first week of playoffs in a league
# phase (week LEAGUE_WEEKS + 1). SeasonHub calls this through ensure_active()
# at HUB entry so loaded saves also bootstrap correctly.
func ensure_active() -> void:
	if _hub == null:
		return
	var cal: CalendarSystem = _hub.get_node_or_null("CalendarSystem") as CalendarSystem
	if cal == null:
		return
	if not cal.is_playoff_bootstrap_week():
		return
	if is_active():
		return
	_bootstrap_playoff(int(_gm.season_state["current_phase"]))


# Phase change clears the previous playoff bracket so the next league phase
# starts fresh (LeagueManager already resets standings on phase entry). Only
# clears PLAYOFF type — InternationalTournament owns its own cleanup.
func _on_phase_changed(_new_phase: int) -> void:
	var t = _gm.season_state.get("current_tournament", null)
	if t != null and String(t.get("type", "")) == "PLAYOFF":
		_gm.season_state["current_tournament"] = null


func _bootstrap_playoff(phase: int) -> void:
	if _league == null:
		return
	var s: Dictionary = _gm.season_state
	if not _league.player_made_playoffs():
		var pr: Dictionary = s.get("phase_results", {})
		pr[phase] = {"made_playoffs": false, "champion": -1}
		s["phase_results"] = pr
		playoff_failed_qualification.emit(phase)
		return

	var ranked: Array = _league.standings_ranked()
	if ranked.size() < 4:
		return
	var top4: Array = []
	for i in 4:
		top4.append(int(ranked[i]["team_id"]))

	var cal: CalendarSystem = _hub.get_node_or_null("CalendarSystem") as CalendarSystem
	var sf_date: Dictionary = cal.date_of_week_offset(0) if cal != null else _today()
	var f_date:  Dictionary = cal.date_of_week_offset(1) if cal != null else _today()

	# 4-team SE. Both semis happen this week (SF1 = #1 vs #4, SF2 = #2 vs #3),
	# F next week. Different teams in SF1 vs SF2 so 1-match-per-week is
	# preserved per-team.
	var phase_week: int = int(s["phase_week"])
	var b: Array = []
	b.append(_mk_match(0, 1, top4[0], top4[3], phase_week,     sf_date))
	b.append(_mk_match(1, 1, top4[1], top4[2], phase_week,     sf_date))
	b.append(_mk_match(2, 2, -1,      -1,      phase_week + 1, f_date))

	s["current_tournament"] = {
		"type":           "PLAYOFF",
		"phase_at_start": phase,
		"stage":          GameEnums.TournamentStage.PLAYOFF_SF,
		"bracket":        b,
	}
	playoff_started.emit(phase)


func _mk_match(slot: int, round_: int, team_a: int, team_b: int, phase_week: int, date: Dictionary) -> Dictionary:
	return {
		"slot":       slot,
		"round":      round_,
		"phase_week": phase_week,
		"team_a":     team_a,
		"team_b":     team_b,
		"year":       int(date["year"]),
		"month":      int(date["month"]),
		"day":        int(date["day"]),
		"weekday":    0,
		# 토너먼트 경기는 언제나 **토요일**(경기일 0)에 선다 — 리그만 토·일
		# 두 라운드를 돌고, 8강 · 4강 · 결승은 주에 하나씩이다.
		"matchday":   0,
		"played":     false,
		"winner":     -1,
	}


func _today() -> Dictionary:
	var s: Dictionary = _gm.season_state
	return {"year": int(s["year"]), "month": int(s["month"]), "day": int(s["day"]), "weekday": 0}


# ── Week-level resolution (called by SeasonHub during weekly advance) ───────
func resolve_current_week() -> void:
	if not is_active():
		return
	var s: Dictionary = _gm.season_state
	var phase: int = int(s["current_phase"])
	var pweek: int = int(s["phase_week"])
	var t: Dictionary = s["current_tournament"]
	if int(t["phase_at_start"]) != phase:
		return
	var pid: int = int(s["player_team_id"])
	var b: Array = t["bracket"]
	for m in b:
		if bool(m["played"]):
			continue
		if int(m["phase_week"]) != pweek:
			continue
		var ta: int = int(m["team_a"]); var tb: int = int(m["team_b"])
		if ta < 0 or tb < 0:
			continue   # final not yet seeded (SF results pending)
		if ta == pid or tb == pid:
			continue   # player match — SeasonHub launches MatchFlow
		var winner: int = ta
		if _league != null:
			winner = _league.simulate_ai_match(ta, tb)
		m["played"] = true
		m["winner"] = winner
		_seed_next_round(int(m["slot"]), winner)
	_maybe_complete()


# Apply a player-match result (slot + winner) to the bracket. Called by
# SeasonHub._consume_pending_match_result after BattleSim returns.
func record_result(slot: int, winner: int) -> void:
	if not is_active():
		return
	var t: Dictionary = _gm.season_state["current_tournament"]
	var b: Array = t["bracket"]
	if slot < 0 or slot >= b.size():
		return
	b[slot]["played"] = true
	b[slot]["winner"] = winner
	_seed_next_round(slot, winner)
	_maybe_complete()


# SF1 winner → F.team_a; SF2 winner → F.team_b. Stage promotes once both
# semifinals are decided.
func _seed_next_round(slot: int, winner: int) -> void:
	var t: Dictionary = _gm.season_state["current_tournament"]
	var b: Array = t["bracket"]
	if slot == 0 and b.size() >= 3:
		b[2]["team_a"] = winner
	elif slot == 1 and b.size() >= 3:
		b[2]["team_b"] = winner
	if slot == 0 or slot == 1:
		if bool(b[0]["played"]) and bool(b[1]["played"]):
			t["stage"] = GameEnums.TournamentStage.PLAYOFF_F
	elif slot == 2:
		t["stage"] = GameEnums.TournamentStage.CHAMPION


func _maybe_complete() -> void:
	var t: Dictionary = _gm.season_state["current_tournament"]
	var b: Array = t["bracket"]
	if b.size() < 3 or not bool(b[2]["played"]):
		return
	var phase: int = int(t["phase_at_start"])
	var champ: int = int(b[2]["winner"])
	var s: Dictionary = _gm.season_state
	var pr: Dictionary = s.get("phase_results", {})
	pr[phase] = {"made_playoffs": true, "champion": champ}
	s["phase_results"] = pr
	playoff_completed.emit(phase, champ)


# ── Queries (HubView toast, BracketView, SeasonHub launch wiring) ──────────
func next_unplayed_player_match() -> Variant:
	if not is_active():
		return null
	var pid: int = int(_gm.season_state["player_team_id"])
	for m in bracket():
		if bool(m["played"]):
			continue
		if int(m["team_a"]) == pid or int(m["team_b"]) == pid:
			return m
	return null


# Returns the bracket index of the player's next unplayed match in the
# current phase_week of the active bracket, or -1 if none. Used by SeasonHub
# to populate pending_match.
func find_player_match_this_week_idx() -> int:
	return find_player_match_on_day_idx(-1)


## 이번 주 그 경기일(0 = 토, 1 = 일)의 플레이어 경기 인덱스. `matchday < 0`
## 이면 이번 주 아무 날이나. 토너먼트 경기는 전부 토요일이라 1 을 넘기면
## 언제나 -1 이 나온다 — 그래도 인자를 받는 것은 시간 경과 화면이 요일마다
## 같은 질문을 세 매니저에게 똑같이 던지기 때문이다.
func find_player_match_on_day_idx(matchday: int) -> int:
	if not is_active():
		return -1
	var s: Dictionary = _gm.season_state
	var pweek: int = int(s["phase_week"])
	var pid: int = int(s["player_team_id"])
	var b: Array = bracket()
	for i in b.size():
		var m: Dictionary = b[i]
		if bool(m["played"]):
			continue
		if int(m["phase_week"]) != pweek:
			continue
		if matchday >= 0 and int(m.get("matchday", 0)) != matchday:
			continue
		var ta: int = int(m["team_a"]); var tb: int = int(m["team_b"])
		if ta == pid or tb == pid:
			return i
	return -1


func slot_label(slot: int) -> String:
	match slot:
		0: return "4강 1경기"
		1: return "4강 2경기"
		2: return "결승"
	return ""


# ── Signal handlers ─────────────────────────────────────────────────────────
func _on_week_advanced(_d: Dictionary) -> void:
	# Bootstrap only fires when we LAND on the bootstrap week. Resolution
	# happens via SeasonHub.resolve_current_week(); we don't auto-resolve
	# here to keep the flow ordering deterministic.
	if _hub == null:
		return
	var cal: CalendarSystem = _hub.get_node_or_null("CalendarSystem") as CalendarSystem
	if cal == null:
		return
	if cal.is_playoff_bootstrap_week() and not is_active():
		_bootstrap_playoff(int(_gm.season_state["current_phase"]))
