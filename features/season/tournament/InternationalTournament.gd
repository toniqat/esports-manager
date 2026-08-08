class_name InternationalTournament
extends Node


# Phase 8 — INTL bracket manager. Activates on the first week of an INTL
# phase (PRESEASON_INTL, MIDSEASON_INTL, REGULAR_INTL). 8-team single
# elimination using the previous league phase's top-4 + 4 fixed external
# INTL teams. Each round happens in its own week (1 match per week per
# team): QF in week 1 (4 matches), SF in week 2 (2 matches), F in week 3.
# AI matches resolve at week-advance time; player matches go through
# SeasonHub → MatchFlow → BattleSim with pending_match.source = "intl".
#
# REGULAR_INTL is the campaign-end gate:
#   - Player wins F   → intl_completed → SeasonHub routes to ENDING
#   - Player loses    → intl_failed_campaign → SeasonHub routes to GAME_OVER
# PRESEASON_INTL / MIDSEASON_INTL only emit intl_completed; the campaign
# rolls into the next league phase regardless of who wins.

signal intl_started(phase: int)
signal intl_completed(phase: int, champion_team_id: int)
signal intl_failed_campaign(phase: int)   # REGULAR_INTL player elimination only

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
	return t != null and String(t.get("type", "")) == "INTL"


func bracket() -> Array:
	if not is_active():
		return []
	return _gm.season_state["current_tournament"]["bracket"]


# ── Phase identification ────────────────────────────────────────────────────
func is_intl_phase(phase: int) -> bool:
	return phase == GameEnums.SeasonPhase.PRESEASON_INTL \
		or phase == GameEnums.SeasonPhase.MIDSEASON_INTL \
		or phase == GameEnums.SeasonPhase.REGULAR_INTL


# ── Lifecycle ───────────────────────────────────────────────────────────────
# Bootstrap when entering an INTL phase. SeasonHub also calls ensure_active()
# at HUB entry so loaded saves bootstrap correctly.
func ensure_active() -> void:
	var s: Dictionary = _gm.season_state
	var phase: int = int(s["current_phase"])
	if not is_intl_phase(phase):
		return
	if int(s["phase_week"]) != 1:
		return
	if is_active():
		return
	_bootstrap_intl(phase)


# Phase-end cleanup: when leaving an INTL phase, drop the bracket so the next
# league phase starts clean.
func _on_phase_changed(_new_phase: int) -> void:
	var t = _gm.season_state.get("current_tournament", null)
	if t != null and String(t.get("type", "")) == "INTL":
		_gm.season_state["current_tournament"] = null


func _bootstrap_intl(phase: int) -> void:
	if _league == null:
		return
	var s: Dictionary = _gm.season_state
	var ranked: Array = _league.standings_ranked()
	if ranked.size() < 4:
		push_error("InternationalTournament: not enough ranked league teams (%d)" % ranked.size())
		return
	var top4: Array = []
	for i in 4:
		top4.append(int(ranked[i]["team_id"]))

	var intl_meta: Array = s.get("intl_team_meta", [])
	if intl_meta.size() < 4:
		push_error("InternationalTournament: intl_team_meta has %d entries (need 4)" % intl_meta.size())
		return
	var intl_ids: Array = []
	for i in 4:
		intl_ids.append(int(intl_meta[i]["id"]))

	var cal: CalendarSystem = _hub.get_node_or_null("CalendarSystem") as CalendarSystem
	var qf_date: Dictionary = cal.date_of_week_offset(0) if cal != null else _today()
	var sf_date: Dictionary = cal.date_of_week_offset(1) if cal != null else _today()
	var f_date:  Dictionary = cal.date_of_week_offset(2) if cal != null else _today()

	# 8-team bracket. QF1..QF4 in week 1 (4 different teams pair up so each
	# team plays once), SF1+SF2 in week 2, F in week 3. High-low pairing
	# intercrosses league seed against INTL seed:
	#   QF1: L1 vs I4 → SF1.team_a
	#   QF4: L4 vs I1 → SF1.team_b
	#   QF2: L2 vs I3 → SF2.team_a
	#   QF3: L3 vs I2 → SF2.team_b
	var pweek: int = int(s["phase_week"])  # always 1 here
	var b: Array = []
	b.append(_mk_match(0, 1, top4[0], intl_ids[3], pweek,     qf_date))   # QF1
	b.append(_mk_match(1, 1, top4[1], intl_ids[2], pweek,     qf_date))   # QF2
	b.append(_mk_match(2, 1, top4[2], intl_ids[1], pweek,     qf_date))   # QF3
	b.append(_mk_match(3, 1, top4[3], intl_ids[0], pweek,     qf_date))   # QF4
	b.append(_mk_match(4, 2, -1, -1,               pweek + 1, sf_date))   # SF1
	b.append(_mk_match(5, 2, -1, -1,               pweek + 1, sf_date))   # SF2
	b.append(_mk_match(6, 3, -1, -1,               pweek + 2, f_date))    # F

	s["current_tournament"] = {
		"type":           "INTL",
		"phase_at_start": phase,
		"stage":          GameEnums.TournamentStage.INTL_QF,
		"bracket":        b,
	}
	intl_started.emit(phase)


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
		"played":     false,
		"winner":     -1,
	}


func _today() -> Dictionary:
	var s: Dictionary = _gm.season_state
	return {"year": int(s["year"]), "month": int(s["month"]), "day": int(s["day"]), "weekday": 0}


# ── Week-level resolution ───────────────────────────────────────────────────
func resolve_current_week() -> void:
	if not is_active():
		return
	var s: Dictionary = _gm.season_state
	var pweek: int = int(s["phase_week"])
	var pid: int = int(s["player_team_id"])
	var t: Dictionary = s["current_tournament"]
	var b: Array = t["bracket"]
	for m in b:
		if bool(m["played"]):
			continue
		if int(m["phase_week"]) != pweek:
			continue
		var ta: int = int(m["team_a"]); var tb: int = int(m["team_b"])
		if ta < 0 or tb < 0:
			continue   # next round not seeded yet
		if ta == pid or tb == pid:
			continue   # player match — SeasonHub launches MatchFlow
		var winner: int = simulate_ai_match(ta, tb)
		m["played"] = true
		m["winner"] = winner
		_seed_next_round(int(m["slot"]), winner)
	_maybe_complete()


# Apply a player-match result. Called by SeasonHub._consume_pending_match_result
# after BattleSim returns with pending_match.source == "intl".
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


func _seed_next_round(slot: int, winner: int) -> void:
	var t: Dictionary = _gm.season_state["current_tournament"]
	var b: Array = t["bracket"]
	match slot:
		0: b[4]["team_a"] = winner   # QF1.W → SF1.team_a
		3: b[4]["team_b"] = winner   # QF4.W → SF1.team_b
		1: b[5]["team_a"] = winner   # QF2.W → SF2.team_a
		2: b[5]["team_b"] = winner   # QF3.W → SF2.team_b
		4: b[6]["team_a"] = winner   # SF1.W → F.team_a
		5: b[6]["team_b"] = winner   # SF2.W → F.team_b
	if slot >= 0 and slot <= 3:
		var qf_done: bool = true
		for i in 4:
			if not bool(b[i]["played"]):
				qf_done = false
				break
		if qf_done:
			t["stage"] = GameEnums.TournamentStage.INTL_SF
	elif slot == 4 or slot == 5:
		if bool(b[4]["played"]) and bool(b[5]["played"]):
			t["stage"] = GameEnums.TournamentStage.INTL_F
	elif slot == 6:
		t["stage"] = GameEnums.TournamentStage.CHAMPION


func _maybe_complete() -> void:
	var s: Dictionary = _gm.season_state
	var t: Dictionary = s["current_tournament"]
	var b: Array = t["bracket"]
	var phase: int = int(t["phase_at_start"])
	var pid: int = int(s["player_team_id"])

	if b.size() >= 7 and bool(b[6]["played"]):
		var champ: int = int(b[6]["winner"])
		_record_phase_results(phase, champ)
		if phase == GameEnums.SeasonPhase.REGULAR_INTL and champ != pid:
			intl_failed_campaign.emit(phase)
		else:
			intl_completed.emit(phase, champ)
		return

	# REGULAR_INTL only — mid-bracket fail-fast.
	if phase == GameEnums.SeasonPhase.REGULAR_INTL and not _player_still_alive():
		_record_phase_results(phase, -1)
		intl_failed_campaign.emit(phase)


func _record_phase_results(phase: int, champ: int) -> void:
	var s: Dictionary = _gm.season_state
	var pr: Dictionary = s.get("phase_results", {})
	var existing: Dictionary = pr.get(phase, {}).duplicate(true) if pr.has(phase) else {}
	existing["intl_played"]   = true
	existing["intl_champion"] = champ
	pr[phase] = existing
	s["phase_results"] = pr


func _player_still_alive() -> bool:
	var s: Dictionary = _gm.season_state
	var pid: int = int(s["player_team_id"])
	var b: Array = s["current_tournament"]["bracket"]
	for m in b:
		var ta: int = int(m["team_a"]); var tb: int = int(m["team_b"])
		if ta != pid and tb != pid:
			continue
		if not bool(m["played"]):
			return true
		if int(m["winner"]) == pid:
			continue
		return false
	return true


# ── Queries (BracketView, HubView toast, SeasonHub launch wiring) ──────────
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


func find_player_match_this_week_idx() -> int:
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
		var ta: int = int(m["team_a"]); var tb: int = int(m["team_b"])
		if ta == pid or tb == pid:
			return i
	return -1


func slot_label(slot: int) -> String:
	match slot:
		0: return "8강 1경기"
		1: return "8강 2경기"
		2: return "8강 3경기"
		3: return "8강 4경기"
		4: return "4강 1경기"
		5: return "4강 2경기"
		6: return "결승"
	return ""


# ── AI vs AI simulation (handles both league + INTL pools) ──────────────────
func simulate_ai_match(team_a: int, team_b: int) -> int:
	var a: float = team_avg_stat(team_a)
	var b: float = team_avg_stat(team_b)
	var total: float = a + b
	if total <= 0.0:
		return team_a
	return team_a if randf() * total < a else team_b


# Average lane stat for `team_id`. Pulls from intl_pilots when team_id is in
# the INTL range (>= 100), otherwise from the league pool.
func team_avg_stat(team_id: int) -> float:
	var pool: Array
	if team_id >= 100:
		pool = _gm.season_state.get("intl_pilots", [])
	else:
		pool = _gm.season_state.get("all_pilots", [])
	var sum: float = 0.0
	var count: int = 0
	for p in pool:
		if p.team_id != team_id:
			continue
		sum += float(p.laning + p.mechanics + p.gamesense + p.teamfight + p.mental) / 5.0
		count += 1
	if count == 0:
		return 0.0
	return sum / float(count)


# Team metadata accessors (handle both league + INTL teams).
func team_name(team_id: int) -> String:
	if team_id >= 100:
		var meta: Array = _gm.season_state.get("intl_team_meta", [])
		for t in meta:
			if int(t["id"]) == team_id:
				return String(t["name"])
		return "INTL %d" % team_id
	if _league != null:
		return _league.team_name(team_id)
	return "Team %d" % team_id


func team_short_name(team_id: int) -> String:
	if team_id >= 100:
		var meta: Array = _gm.season_state.get("intl_team_meta", [])
		for t in meta:
			if int(t["id"]) == team_id:
				return String(t["short_name"])
		return "I%d" % team_id
	if _league != null:
		return _league.team_short_name(team_id)
	return "T%d" % team_id


# ── Signal handlers ─────────────────────────────────────────────────────────
func _on_week_advanced(_d: Dictionary) -> void:
	# Bootstrap on entry to week 1 of an INTL phase. Resolution is invoked
	# explicitly by SeasonHub.resolve_current_week() during the weekly flow.
	var s: Dictionary = _gm.season_state
	var phase: int = int(s["current_phase"])
	if not is_intl_phase(phase):
		return
	if int(s["phase_week"]) == 1 and not is_active():
		_bootstrap_intl(phase)
