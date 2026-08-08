class_name CalendarSystem
extends Node

# Week-by-week clock for the campaign. Owns calendar arithmetic and
# SeasonPhase transitions. Reads/writes GameManager.season_state.
#
# The campaign progresses one week at a time — not one day. The internal
# weekday is conceptually always Monday at the start of a week; matches
# happen on Fri/Sat/Sun internally during the week but those days are never
# exposed to the player. After advance_week() the calendar jumps 7 days
# forward and phase_week increments.

signal week_advanced(new_date: Dictionary)        # {year, month, day, weekday}
signal phase_changed(new_phase: int)              # GameEnums.SeasonPhase

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

const DAYS_IN_MONTH: Array = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

# Total length (in weeks) of each SeasonPhase. League phases run 1 round per
# week, so PRESEASON (single round-robin = 7 rounds) = 7 league weeks, plus a
# 2-week playoff (SF week + F week). MID/REGULAR (double round-robin = 14
# rounds) = 14 league weeks + 2 playoff. INTL phases are 3-week 8-team SE
# tournaments (QF week + SF week + F week).
const PHASE_WEEKS: Dictionary = {
	GameEnums.SeasonPhase.PRESEASON:      9,    # 7 league + 2 playoff
	GameEnums.SeasonPhase.PRESEASON_INTL: 3,    # QF / SF / F
	GameEnums.SeasonPhase.MIDSEASON:      16,   # 14 league + 2 playoff
	GameEnums.SeasonPhase.MIDSEASON_INTL: 3,
	GameEnums.SeasonPhase.REGULAR:        16,   # 14 league + 2 playoff
	GameEnums.SeasonPhase.REGULAR_INTL:   3,
}

# League-only weeks per phase (excludes the trailing 2 playoff weeks). Used
# by LeagueManager to enumerate scheduled rounds, and to gate
# is_league_match_week().
const LEAGUE_WEEKS: Dictionary = {
	GameEnums.SeasonPhase.PRESEASON: 7,
	GameEnums.SeasonPhase.MIDSEASON: 14,
	GameEnums.SeasonPhase.REGULAR:   14,
}

# Playoff bracket spans (in weeks) at the tail of each league phase.
# Week LEAGUE_WEEKS+1 = SF week (SF1 + SF2). Week LEAGUE_WEEKS+2 = F week.
const PLAYOFF_WEEKS: int = 2


# Returns current date dict from season_state.
func today() -> Dictionary:
	var s: Dictionary = _gm.season_state
	return {
		"year": s["year"],
		"month": s["month"],
		"day": s["day"],
		"weekday": s["weekday"],
	}


# Configured length (in weeks) of the given SeasonPhase.
func phase_max_weeks(phase: int) -> int:
	return int(PHASE_WEEKS.get(phase, 1))


# League-week count of the given SeasonPhase (0 for non-league/INTL phases).
func phase_league_weeks(phase: int) -> int:
	return int(LEAGUE_WEEKS.get(phase, 0))


# True iff the current phase is a league phase AND we're inside its league
# weeks (i.e., before the trailing playoff weeks). Drives schedule lookups.
func is_league_match_week() -> bool:
	var s: Dictionary = _gm.season_state
	var phase: int = int(s["current_phase"])
	var lw: int = phase_league_weeks(phase)
	return lw > 0 and int(s["phase_week"]) <= lw


# True iff the current phase is a league phase AND we're inside one of its
# trailing playoff weeks (LEAGUE_WEEKS+1 = SF, LEAGUE_WEEKS+2 = F).
func is_playoff_week() -> bool:
	var s: Dictionary = _gm.season_state
	var phase: int = int(s["current_phase"])
	var lw: int = phase_league_weeks(phase)
	if lw <= 0:
		return false
	var pweek: int = int(s["phase_week"])
	return pweek > lw and pweek <= phase_max_weeks(phase)


# True iff today is the first day (Mon) of a playoff week. Used by
# TournamentManager to bootstrap the bracket exactly once per league phase.
func is_playoff_bootstrap_week() -> bool:
	var s: Dictionary = _gm.season_state
	var phase: int = int(s["current_phase"])
	var lw: int = phase_league_weeks(phase)
	return lw > 0 and int(s["phase_week"]) == lw + 1


# Advance the clock by one full week. Rolls 7 days forward, bumps phase_week,
# transitions phase if the week count exceeds the phase length. Emits
# week_advanced (and phase_changed when applicable).
#
# Training application and AI match resolution happen BEFORE this in the
# season flow (SeasonHub orchestrates the order: training → result → match →
# standings → next-week call). This function just rolls the clock.
func advance_week() -> void:
	var s: Dictionary = _gm.season_state
	for _i in 7:
		s["day"] = int(s["day"]) + 1
		var dim: int = DAYS_IN_MONTH[int(s["month"]) - 1]
		if int(s["day"]) > dim:
			s["day"] = 1
			s["month"] = int(s["month"]) + 1
			if int(s["month"]) > 12:
				s["month"] = 1
				s["year"] = int(s["year"]) + 1
	# Weekday stays at 0 (Monday) — we always sit at the start of a week.
	s["weekday"] = 0
	s["phase_week"] = int(s["phase_week"]) + 1
	if int(s["phase_week"]) > phase_max_weeks(int(s["current_phase"])):
		_advance_phase()
	week_advanced.emit(today())


# Returns a {year, month, day} dict offset `week_delta` weeks from today's
# Monday. Used by schedulers to stamp matches with the Monday of their week.
func date_of_week_offset(week_delta: int) -> Dictionary:
	var s: Dictionary = _gm.season_state
	var year: int = int(s["year"])
	var month: int = int(s["month"])
	var day: int = int(s["day"])
	var delta: int = week_delta * 7
	if delta >= 0:
		for _i in delta:
			day += 1
			var dim: int = int(DAYS_IN_MONTH[month - 1])
			if day > dim:
				day = 1
				month += 1
				if month > 12:
					month = 1
					year += 1
	else:
		for _i in -delta:
			day -= 1
			if day < 1:
				month -= 1
				if month < 1:
					month = 12
					year -= 1
				day = int(DAYS_IN_MONTH[month - 1])
	return {"year": year, "month": month, "day": day, "weekday": 0}


# Roll into the next SeasonPhase. Caps at REGULAR_INTL — the campaign-end
# routing (ENDING/GAME_OVER screens) is handled by SeasonHub.
func _advance_phase() -> void:
	var s: Dictionary = _gm.season_state
	var cur: int = int(s["current_phase"])
	if cur >= GameEnums.SeasonPhase.REGULAR_INTL:
		return
	s["current_phase"] = cur + 1
	s["phase_week"] = 1
	phase_changed.emit(int(s["current_phase"]))
