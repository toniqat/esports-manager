class_name TrainingScheduler
extends Node

# 7-day × pilot training grid. Default-fill + player override + per-week
# stat application. The grid still reads as Mon..Sun but the campaign
# applies the whole week atomically once per "주 진행" tick.

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

const STAT_DELTAS: Dictionary = {
	GameEnums.TrainingType.REST:      {"mental": 2},
	GameEnums.TrainingType.LANING:    {"laning": 1},
	GameEnums.TrainingType.MECHANICS: {"mechanics": 1},
	GameEnums.TrainingType.GAMESENSE: {"gamesense": 1},
	GameEnums.TrainingType.TEAMFIGHT: {"teamfight": 1},
	GameEnums.TrainingType.SCRIM:     {"mental": -1, "teamfight": 1, "gamesense": 1},
	GameEnums.TrainingType.MATCH:     {"mental": -2},   # match days are physically taxing
}

const STAT_KEYS: Array = ["laning", "mechanics", "gamesense", "teamfight", "mental"]


# Default week template for a freshly-drafted pilot. Mon–Thu = role-relevant
# training, Fri–Sun = MATCH (will be auto-overridden when a real match isn't
# scheduled). Player can override any non-MATCH cell from the UI.
func default_week_for_pilot(p: PlayerData) -> Array:
	var role_focus: int = GameEnums.TrainingType.MECHANICS
	match p.role:
		GameEnums.Role.TANK:     role_focus = GameEnums.TrainingType.LANING
		GameEnums.Role.FIGHTER:  role_focus = GameEnums.TrainingType.MECHANICS
		GameEnums.Role.ASSASSIN: role_focus = GameEnums.TrainingType.MECHANICS
		GameEnums.Role.SUPPORT:  role_focus = GameEnums.TrainingType.GAMESENSE
		GameEnums.Role.SNIPER:   role_focus = GameEnums.TrainingType.MECHANICS
	return [
		GameEnums.TrainingType.REST,        # Mon
		role_focus,                         # Tue
		GameEnums.TrainingType.SCRIM,       # Wed
		GameEnums.TrainingType.TEAMFIGHT,   # Thu
		GameEnums.TrainingType.MATCH,       # Fri
		GameEnums.TrainingType.MATCH,       # Sat
		GameEnums.TrainingType.MATCH,       # Sun
	]


# Refill the player team's schedule for the upcoming week. Called when a new
# week begins (SeasonHub.advance_to_next_week → CalendarSystem.advance_week).
func refill_player_team_defaults() -> void:
	var pool: Array = _gm.season_state["all_pilots"]
	var sched: Dictionary = _gm.season_state["training_schedule"]
	for p in pool:
		if p.team_id == _gm.season_state["player_team_id"]:
			sched[p.id] = default_week_for_pilot(p)


# Apply the full week's training to all player-team pilots. Returns a dict
# of per-pilot {before: {stat:int}, after: {stat:int}} so TrainingResultView
# can render the deltas. Match cells fall back to REST when the player has
# no real match this week (so off-week-end weekends don't bleed mental).
#
# Idempotent-ish: stat changes are written directly to PlayerData; calling
# twice in a row would double-apply. SeasonHub controls the call site.
func apply_week_training() -> Dictionary:
	var pool: Array = _gm.season_state["all_pilots"]
	var sched: Dictionary = _gm.season_state["training_schedule"]
	var has_real_match: bool = _player_has_real_match_this_week()
	var pid: int = int(_gm.season_state["player_team_id"])
	var result: Dictionary = {}
	for p in pool:
		if p.team_id != pid:
			continue
		if not sched.has(p.id):
			continue
		var before: Dictionary = _snapshot(p)
		var week: Array = sched[p.id]
		for d in 7:
			var t: int = int(week[d])
			if t == GameEnums.TrainingType.MATCH and not has_real_match:
				t = GameEnums.TrainingType.REST
			if not STAT_DELTAS.has(t):
				continue
			for stat in STAT_DELTAS[t].keys():
				var cur: int = int(p.get(stat))
				var delta: int = int(STAT_DELTAS[t][stat])
				p.set(stat, clamp(cur + delta, 1, 100))
		var after: Dictionary = _snapshot(p)
		result[p.id] = {"before": before, "after": after, "name": p.name, "role": int(p.role), "pilot_id": int(p.id)}
	return result


func _snapshot(p: PlayerData) -> Dictionary:
	return {
		"laning":    int(p.laning),
		"mechanics": int(p.mechanics),
		"gamesense": int(p.gamesense),
		"teamfight": int(p.teamfight),
		"mental":    int(p.mental),
	}


func _player_has_real_match_this_week() -> bool:
	if _hub == null:
		return false
	# League?
	var league: LeagueManager = _hub.get_node_or_null("LeagueManager") as LeagueManager
	if league != null and league.player_match_this_week() != null:
		return true
	# Active tournament (playoff or INTL)?
	var tm: TournamentManager = _hub.get_node_or_null("TournamentManager") as TournamentManager
	if tm != null and tm.find_player_match_this_week_idx() >= 0:
		return true
	var intl: InternationalTournament = _hub.get_node_or_null("InternationalTournament") as InternationalTournament
	if intl != null and intl.find_player_match_this_week_idx() >= 0:
		return true
	return false


# Projected end-of-week stats for a single pilot if the current 7-day schedule
# runs to completion. Used by TrainingView's preview header. Applies the same
# clamp(1, 100) per stat per day as apply_week_training.
func projected_week_stats(p: PlayerData) -> Dictionary:
	var stats: Dictionary = _snapshot(p)
	var sched: Dictionary = _gm.season_state["training_schedule"]
	if not sched.has(p.id):
		return stats
	var week: Array = sched[p.id]
	var has_real_match: bool = _player_has_real_match_this_week()
	for d in 7:
		var t: int = int(week[d])
		if t == GameEnums.TrainingType.MATCH and not has_real_match:
			t = GameEnums.TrainingType.REST
		if not STAT_DELTAS.has(t):
			continue
		for stat_name in STAT_DELTAS[t].keys():
			var cur: int = int(stats[stat_name])
			var delta: int = int(STAT_DELTAS[t][stat_name])
			stats[stat_name] = clamp(cur + delta, 1, 100)
	return stats
