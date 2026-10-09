class_name CalendarSystem
extends Node

# Week-by-week clock for the campaign. Owns calendar arithmetic and
# SeasonPhase transitions. Reads/writes GameManager.season_state.
#
# The calendar date (`year/month/day/weekday`) always sits on the week's Monday;
# the day the player is on is `season_state.week_day` (0 = Mon … 6 = Sun, owned
# by the week screen). The player's one match of the week is on Sunday, its
# ban/pick on Saturday. After advance_week() the calendar jumps 7 days forward
# and phase_week increments.

signal week_advanced(new_date: Dictionary)        # {year, month, day, weekday}
signal phase_changed(new_phase: int)              # GameEnums.SeasonPhase

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

const DAYS_IN_MONTH: Array = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

# ── Days of a week ───────────────────────────────────────────────────────────
# A week runs Mon–Sun (`season_state["week_day"]` 0..6). Mon–Fri are the five rows of
# the training board. **The player plays one match per week, always on Sunday**:
#   Sat (PREP_DAY)  morning = stadium → match prep (intel · ban/pick); afternoon /
#                   evening = a normal day without training
#   Sun (MATCH_DAY) morning = stadium → the match; afternoon = press conference;
#                   evening = a normal evening → week end
# A week without a player match has plain Sat / Sun (no stadium, no press).
const DAYS_PER_WEEK: int = 7
## Training days (Mon–Fri) = the training board's rows (`TrainingBoard.ROWS`).
const TRAINING_DAYS: int = 5
## Match prep (ban/pick) day — Saturday.
const PREP_DAY: int = 5
## Match day — Sunday.
const MATCH_DAY: int = 6
## Weekday index → match-day number. Sunday is the only match day, so this is 0
## (`matchday` of every schedule / bracket entry is 0).
const MATCH_DAYS: Dictionary = {MATCH_DAY: 0}
## League rounds per week — one, on Sunday.
const ROUNDS_PER_WEEK: int = 1
## `season_state.schedule_format` — 2 = one round per week, Sunday matches (this table).
## Old saves without the key (two rounds on Sat · Sun) are fixed on load by
## `migrate_weekly_format`.
const SCHEDULE_FORMAT: int = 2

# Total length (in weeks) of each SeasonPhase. Every league phase is a **single
# round robin** (8 teams = 7 rounds) at **1 round per week** (Sunday) = 7 league
# weeks, plus a 2-week playoff (SF week + F week). INTL phases are 3-week 8-team
# SE tournaments (QF week + SF week + F week). Campaign = 9+3+9+3+9+3 = 36 weeks.
const PHASE_WEEKS: Dictionary = {
	GameEnums.SeasonPhase.PRESEASON:      9,    # 7 league + 2 playoff
	GameEnums.SeasonPhase.PRESEASON_INTL: 3,    # QF / SF / F
	GameEnums.SeasonPhase.MIDSEASON:      9,    # 7 league + 2 playoff
	GameEnums.SeasonPhase.MIDSEASON_INTL: 3,
	GameEnums.SeasonPhase.REGULAR:        9,    # 7 league + 2 playoff
	GameEnums.SeasonPhase.REGULAR_INTL:   3,
}

# League-only weeks per phase (excludes the trailing 2 playoff weeks). Used
# by LeagueManager to enumerate scheduled rounds, and to gate
# is_league_match_week(). = rounds / ROUNDS_PER_WEEK.
const LEAGUE_WEEKS: Dictionary = {
	GameEnums.SeasonPhase.PRESEASON: 7,    # 7 rounds (single RR)
	GameEnums.SeasonPhase.MIDSEASON: 7,
	GameEnums.SeasonPhase.REGULAR:   7,
}

## League weeks of the old 2-rounds-per-week format (format 1, no `schedule_format`
## key) — only `migrate_weekly_format` reads it.
const _OLD_LEAGUE_WEEKS: Dictionary = {
	GameEnums.SeasonPhase.PRESEASON: 4,
	GameEnums.SeasonPhase.MIDSEASON: 7,
	GameEnums.SeasonPhase.REGULAR:   7,
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


# ── 요일 ────────────────────────────────────────────────────────────────────
## 지금 화면이 보고 있는 요일(0 = 월 … 6 = 일). 주 진행이 시작되기 전이면 -1.
func week_day() -> int:
	return int(_gm.season_state.get("week_day", -1))


## 그 요일이 훈련하는 날인가 (월~금).
static func is_training_day(day: int) -> bool:
	return day >= 0 and day < TRAINING_DAYS


## Match-day number of a weekday (Sunday = 0), -1 when no match can stand on it.
## **경기가 실제로 배정돼 있는가는 이 함수가 답하지 않는다** — 그건 스케줄이
## 답한다(`LeagueManager.player_match_on_day` 등).
static func matchday_of(day: int) -> int:
	return int(MATCH_DAYS.get(day, -1))


## A weekday index inside the week (0..6). Sat / Sun without training still have the
## morning talk / afternoon / evening halves.
static func is_week_day(day: int) -> bool:
	return day >= 0 and day < DAYS_PER_WEEK


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


# ── Old saves (format 1 → 2) ─────────────────────────────────────────────────
## Brings a run saved under the old week format (2 league rounds per week on Sat · Sun,
## 4 preseason league weeks, double round robin in MID / REGULAR, tournaments on
## Saturday) onto the current one. No-op once `schedule_format` is
## `SCHEDULE_FORMAT`. Called by `SaveSystem.load_run`; static, so no scene is needed.
##
## * In a league week: the **unplayed rounds** of the current phase are re-stamped one
##   per week from the current `phase_week` (all on Sunday, `matchday` 0); rounds that no
##   longer fit before the playoffs are voided (`played` true, `winner` -1, `phase_week` 0,
##   `void` true — kept in the array so `pending_match.schedule_idx` stays valid).
## * In a playoff week: `phase_week` and the playoff bracket move by the added league weeks.
## * Matches keep their array index; tournament entries keep `matchday` 0 (now Sunday).
static func migrate_weekly_format(state: Dictionary) -> void:
	if int(state.get("schedule_format", 1)) >= SCHEDULE_FORMAT:
		return
	state["schedule_format"] = SCHEDULE_FORMAT
	var phase: int = int(state.get("current_phase", 0))
	var new_lw: int = int(LEAGUE_WEEKS.get(phase, 0))
	var old_lw: int = int(_OLD_LEAGUE_WEEKS.get(phase, 0))
	var sched: Array = state.get("match_schedule", [])
	if new_lw <= 0:
		return   # INTL phase — 3 weeks before and after
	var pweek: int = int(state.get("phase_week", 1))
	if pweek > old_lw:
		# Playoff weeks: shift onto the new numbering, with the bracket.
		var delta: int = new_lw - old_lw
		state["phase_week"] = pweek + delta
		var t: Variant = state.get("current_tournament", null)
		if t is Dictionary and String((t as Dictionary).get("type", "")) == "PLAYOFF":
			for m in ((t as Dictionary).get("bracket", []) as Array):
				(m as Dictionary)["phase_week"] = int((m as Dictionary).get("phase_week", 0)) + delta
		return
	# League weeks: one unplayed round per week from this week on.
	var rounds: Array = []
	for m_raw in sched:
		var m: Dictionary = m_raw
		if int(m.get("phase", -1)) != phase or bool(m.get("played", false)):
			continue
		var r: int = int(m.get("round", 0))
		if not rounds.has(r):
			rounds.append(r)
	rounds.sort()
	for m_raw in sched:
		var m: Dictionary = m_raw
		if int(m.get("phase", -1)) != phase:
			continue
		m["matchday"] = 0
		if bool(m.get("played", false)):
			continue
		var k: int = rounds.find(int(m.get("round", 0)))
		var week: int = pweek + k
		if week > new_lw:
			m["played"] = true
			m["winner"] = -1
			m["phase_week"] = 0
			m["void"] = true
		else:
			m["phase_week"] = week
