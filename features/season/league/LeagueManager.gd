class_name LeagueManager
extends Node

# Round-robin schedule + standings + AI-vs-AI resolution. Reads/writes
# GameManager.season_state. Each league phase = a single round robin (7 rounds),
# one round per week on Sunday (4 matches across 8 teams) — the player plays
# exactly one match per league week.

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")


func _ready() -> void:
	if _hub == null:
		return
	var cal: CalendarSystem = _hub.get_node_or_null("CalendarSystem") as CalendarSystem
	if cal == null:
		return
	if not cal.phase_changed.is_connected(_on_phase_changed):
		cal.phase_changed.connect(_on_phase_changed)


# ── Phase identification ────────────────────────────────────────────────────
func is_league_phase(phase: int) -> bool:
	return phase == GameEnums.SeasonPhase.PRESEASON \
		or phase == GameEnums.SeasonPhase.MIDSEASON \
		or phase == GameEnums.SeasonPhase.REGULAR


# ── Schedule generation ─────────────────────────────────────────────────────
# Idempotent — generates the current phase's schedule if no matches for it
# exist yet. Called by SeasonHub on hub entry (covers initial PRESEASON) and
# on phase transitions.
func ensure_phase_scheduled() -> void:
	var phase: int = int(_gm.season_state["current_phase"])
	if not is_league_phase(phase):
		return
	if _phase_already_scheduled(phase):
		return
	generate_phase_schedule(phase)


func _phase_already_scheduled(phase: int) -> bool:
	for m in _gm.season_state["match_schedule"]:
		if int(m.get("phase", -1)) == phase:
			return true
	return false


# Generate the round-robin schedule for the given league phase. Resets the
# standings and writes match entries into season_state["match_schedule"].
# Every league phase = single round-robin (7 rounds × 1 round/week = 7 weeks,
# all on Sunday, `matchday` 0). Each match is stamped with the Monday of its
# phase_week so save metadata and views stay coherent.
func generate_phase_schedule(phase: int) -> void:
	if not is_league_phase(phase):
		return
	var s: Dictionary = _gm.season_state
	var n: int = _gm.TEAM_COUNT
	var rounds: Array = generate_round_robin(n)  # 7 rounds, 4 pairs each

	var cal: CalendarSystem = null
	if _hub != null:
		cal = _hub.get_node_or_null("CalendarSystem") as CalendarSystem

	# Reset standings — each league phase starts fresh.
	var standings: Dictionary = {}
	for t in n:
		standings[t] = {"wins": 0, "losses": 0}
	s["league_standings"] = standings

	# Strip any orphaned entries for this phase.
	var sched: Array = (s["match_schedule"] as Array).filter(
			func(m): return int(m.get("phase", -1)) != phase)

	# One round per week (`ROUNDS_PER_WEEK` = 1): round r → week r + 1, Sunday
	# (`matchday` 0 = `CalendarSystem.MATCH_DAY`). `weekday` stays 0 (the save card
	# shows the week's Monday); the day the match stands on is `matchday`.
	var per_week: int = CalendarSystem.ROUNDS_PER_WEEK
	for r_idx in rounds.size():
		@warning_ignore("integer_division")
		var week_idx: int = r_idx / per_week
		var matchday: int = r_idx % per_week
		var pweek: int = week_idx + 1
		var date: Dictionary = {"year": int(s["year"]), "month": int(s["month"]), "day": int(s["day"])}
		if cal != null:
			date = cal.date_of_week_offset(week_idx)
		for pair in rounds[r_idx]:
			sched.append({
				"phase":      phase,
				"phase_week": pweek,
				"year":       int(date["year"]),
				"month":      int(date["month"]),
				"day":        int(date["day"]),
				"weekday":    0,
				"matchday":   matchday,
				"round":      r_idx,
				"team_a":     int(pair[0]),
				"team_b":     int(pair[1]),
				"played":     false,
				"winner":     -1,
			})
	s["match_schedule"] = sched
	s["schedule_format"] = CalendarSystem.SCHEDULE_FORMAT


# Build a round-robin pairing list for `team_count` teams. Returns an Array
# of rounds, each round an Array of [team_a, team_b] pairs. Standard circle
# method (one team fixed, others rotate).
func generate_round_robin(team_count: int) -> Array:
	if team_count % 2 != 0:
		push_error("LeagueManager: odd team_count not supported")
		return []
	var teams: Array = range(team_count)
	var rounds: Array = []
	for r in team_count - 1:
		var pairs: Array = []
		@warning_ignore("integer_division")
		for i in team_count / 2:
			pairs.append([teams[i], teams[team_count - 1 - i]])
		rounds.append(pairs)
		var last: int = teams[team_count - 1]
		for i in range(team_count - 1, 1, -1):
			teams[i] = teams[i - 1]
		teams[1] = last
	return rounds


# ── Week-level resolution (called by SeasonHub during weekly advance) ───────
# Auto-resolve every AI-vs-AI match scheduled for the current phase_week of
# the current league phase. Leaves player-team matches unplayed for SeasonHub
# to launch via MatchFlow → BattleSim. No-op outside league weeks.
func resolve_current_week() -> void:
	resolve_matchday(-1)


## Resolves the AI matches of one matchday (0 = Sunday, the only one); `matchday < 0` =
## the whole week (the week-end sweep). The player's match is left for SeasonHub.
func resolve_matchday(matchday: int) -> void:
	if _hub != null:
		var cal: CalendarSystem = _hub.get_node_or_null("CalendarSystem") as CalendarSystem
		if cal != null and not cal.is_league_match_week():
			return
	var s: Dictionary = _gm.season_state
	var phase: int = int(s["current_phase"])
	var pweek: int = int(s["phase_week"])
	var pid: int = int(s["player_team_id"])
	for m in s["match_schedule"]:
		if bool(m["played"]):
			continue
		if int(m["phase"]) != phase or int(m["phase_week"]) != pweek:
			continue
		if matchday >= 0 and int(m.get("matchday", 0)) != matchday:
			continue
		var ta: int = int(m["team_a"]); var tb: int = int(m["team_b"])
		if ta == pid or tb == pid:
			continue  # player match — SeasonHub handles via MatchFlow
		var winner: int = simulate_ai_match(ta, tb)
		m["played"] = true
		m["winner"] = winner
		record_result(ta, tb, winner)


# ── Standings ───────────────────────────────────────────────────────────────
func record_result(team_a: int, team_b: int, winner: int) -> void:
	var s: Dictionary = _gm.season_state["league_standings"]
	if winner == team_a:
		s[team_a]["wins"] = int(s[team_a]["wins"]) + 1
		s[team_b]["losses"] = int(s[team_b]["losses"]) + 1
	elif winner == team_b:
		s[team_b]["wins"] = int(s[team_b]["wins"]) + 1
		s[team_a]["losses"] = int(s[team_a]["losses"]) + 1


# Returns rows ranked best-first. Each row = {team_id, wins, losses}.
# Tie-break: fewer losses, then ascending team_id.
func standings_ranked() -> Array:
	var rows: Array = []
	for t in _gm.season_state["league_standings"].keys():
		var entry: Dictionary = _gm.season_state["league_standings"][t]
		rows.append({
			"team_id": int(t),
			"wins":    int(entry["wins"]),
			"losses":  int(entry["losses"]),
		})
	rows.sort_custom(func(a, b):
		if a["wins"] != b["wins"]:
			return a["wins"] > b["wins"]
		if a["losses"] != b["losses"]:
			return a["losses"] < b["losses"]
		return a["team_id"] < b["team_id"])
	return rows


func player_made_playoffs() -> bool:
	var ranked: Array = standings_ranked()
	var pid: int = int(_gm.season_state["player_team_id"])
	for i in ranked.size():
		if int(ranked[i]["team_id"]) == pid:
			return i < _gm.PLAYOFF_TEAMS
	return false


# Average lane stat for a team — drives AI-vs-AI quick-sim weight.
func _team_avg_stat(team_id: int) -> float:
	var sum: float = 0.0
	var count: int = 0
	for p in _gm.season_state["all_pilots"]:
		if p.team_id != team_id:
			continue
		sum += p.stat_avg()
		count += 1
	if count == 0:
		return 0.0
	return sum / float(count)


# Unfair coin weighted by team-avg ratio. Returns the winning team_id.
func simulate_ai_match(team_a: int, team_b: int) -> int:
	var a: float = _team_avg_stat(team_a)
	var b: float = _team_avg_stat(team_b)
	var total: float = a + b
	if total <= 0.0:
		return team_a
	var roll: float = randf() * total
	return team_a if roll < a else team_b


# ── Queries (used by views, save metadata, MatchFlow handoff) ───────────────
# Returns the next unplayed player-team match (across the whole campaign), or
# null if none. Used by views' "next match" header and Phase 6 wiring.
func next_unplayed_player_match() -> Variant:
	var pid: int = int(_gm.season_state["player_team_id"])
	for m in _gm.season_state["match_schedule"]:
		if bool(m["played"]):
			continue
		if int(m["team_a"]) == pid or int(m["team_b"]) == pid:
			return m
	return null


# Returns the player's match scheduled for the current phase/week, or null
# if none (rare — a player might bye one week if a tournament gives them a
# pass, but in normal RR they always play).
func player_match_this_week() -> Variant:
	return player_match_on_day(-1)


## My unplayed league match this week on that matchday (0 = Sunday), or null.
## `matchday < 0` = any day of this week. Played matches do not count, so the week
## screen does not offer the same match again after it was played.
func player_match_on_day(matchday: int) -> Variant:
	var s: Dictionary = _gm.season_state
	var phase: int = int(s["current_phase"])
	var pweek: int = int(s["phase_week"])
	var pid: int = int(s["player_team_id"])
	for m in s["match_schedule"]:
		if bool(m["played"]):
			continue
		if int(m["phase"]) != phase or int(m["phase_week"]) != pweek:
			continue
		if matchday >= 0 and int(m.get("matchday", 0)) != matchday:
			continue
		if int(m["team_a"]) == pid or int(m["team_b"]) == pid:
			return m
	return null


# Returns matches scheduled for the current phase/week (any team).
func matches_this_week() -> Array:
	var s: Dictionary = _gm.season_state
	var phase: int = int(s["current_phase"])
	var pweek: int = int(s["phase_week"])
	var out: Array = []
	for m in s["match_schedule"]:
		if int(m.get("phase", -1)) == phase and int(m.get("phase_week", -1)) == pweek:
			out.append(m)
	return out


# ── Team metadata accessors ─────────────────────────────────────────────────
# 팀 메타에는 l10n key 만 있다(D7) — 표시는 `GameManager.team_name` 이 푼다.
func team_name(team_id: int) -> String:
	return String(_gm.team_name(team_id))


func team_short_name(team_id: int) -> String:
	return String(_gm.team_short_name(team_id))


# ── Signal handlers ─────────────────────────────────────────────────────────
func _on_phase_changed(_new_phase: int) -> void:
	ensure_phase_scheduled()
