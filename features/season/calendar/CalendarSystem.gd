class_name CalendarSystem
extends Node

# Week-by-week clock for the campaign. Owns calendar arithmetic and
# SeasonPhase transitions. Reads/writes GameManager.season_state.
#
# The calendar date (`year/month/day/weekday`) always sits on the week's Monday;
# the day the player is on is `season_state.week_day` (0 = Mon … 6 = Sun, owned
# by the week screen). The player's matches stand on Saturday and Sunday, one round
# a day (ban/pick and the match on the same day). After advance_week() the calendar
# jumps 7 days forward and phase_week increments.

signal week_advanced(new_date: Dictionary)        # {year, month, day, weekday}
signal phase_changed(new_phase: int)              # GameEnums.SeasonPhase

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

const DAYS_IN_MONTH: Array = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

# ── Days of a week ───────────────────────────────────────────────────────────
# A week runs Mon–Sun (`season_state["week_day"]` 0..6). Mon–Fri are the five rows of
# the training board. **Saturday and Sunday are match days**, one round each:
#   morning   = the day's tournament schedule → "경기 시작" → MatchFlow PREP → BAN_PICK →
#               BattleSim in one go → standings
#   afternoon / evening = a normal day without training (visit, incident)
# A match day without a player match (the last league week's Sunday) has the afternoon /
# evening only.
const DAYS_PER_WEEK: int = 7
## Training days (Mon–Fri) = the training board's rows (`TrainingBoard.ROWS`).
const TRAINING_DAYS: int = 5
## Weekday index → match-day number (`matchday` of schedule / bracket entries):
## Saturday = 0, Sunday = 1.
const MATCH_DAYS: Dictionary = {5: 0, 6: 1}
## League rounds per week: one on Saturday, one on Sunday.
const ROUNDS_PER_WEEK: int = 2
## `season_state.schedule_format`: 3 = one round a day on Sat · Sun (this table).
## Older runs are fixed on load by `migrate_weekly_format` (1 = two rounds on Sat · Sun
## with the old phase lengths, 2 = one round per week on Sunday).
const SCHEDULE_FORMAT: int = 3

# Total length (in weeks) of each SeasonPhase. Every league phase is a **single
# round robin** (8 teams = 7 rounds) at **2 rounds per week** (Sat · Sun) = 4 league
# weeks (the last one has Saturday only), plus a 1-week playoff (SF Saturday, F Sunday).
# INTL phases are 2-week 8-team SE tournaments (QF Saturday, SF Sunday, F next Saturday).
const PHASE_WEEKS: Dictionary = {
	GameEnums.SeasonPhase.PRESEASON:      5,    # 4 league + 1 playoff
	GameEnums.SeasonPhase.PRESEASON_INTL: 2,    # QF · SF / F
	GameEnums.SeasonPhase.MIDSEASON:      5,
	GameEnums.SeasonPhase.MIDSEASON_INTL: 2,
	GameEnums.SeasonPhase.REGULAR:        5,
	GameEnums.SeasonPhase.REGULAR_INTL:   2,
}

# League-only weeks per phase (excludes the trailing playoff week). Used by
# LeagueManager to enumerate scheduled rounds, and to gate is_league_match_week().
# = ceil(rounds / ROUNDS_PER_WEEK).
const LEAGUE_WEEKS: Dictionary = {
	GameEnums.SeasonPhase.PRESEASON: 4,    # 7 rounds (single RR)
	GameEnums.SeasonPhase.MIDSEASON: 4,
	GameEnums.SeasonPhase.REGULAR:   4,
}

## League weeks of the format-2 calendar (one round per week), only
## `migrate_weekly_format` reads it.
const _FORMAT2_LEAGUE_WEEKS: int = 7

# Playoff bracket span (in weeks) at the tail of each league phase.
# Week LEAGUE_WEEKS+1 = SF1 + SF2 on Saturday, F on Sunday.
const PLAYOFF_WEEKS: int = 1


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


## Match-day number of a weekday (Saturday = 0, Sunday = 1), -1 when no match can stand on it.
## **경기가 실제로 배정돼 있는가는 이 함수가 답하지 않는다** — 그건 스케줄이
## 답한다(`LeagueManager.player_match_on_day` 등).
static func matchday_of(day: int) -> int:
	return int(MATCH_DAYS.get(day, -1))


## A weekday index inside the week (0..6). Sat / Sun without training still have the
## morning / afternoon / evening halves.
static func is_week_day(day: int) -> bool:
	return day >= 0 and day < DAYS_PER_WEEK


## Day number inside the current phase, from 1: `(phase_week - 1) * 7 + week_day + 1`
## (the week screen's "DAY N"). A week not opened yet (`week_day` -1) counts as its Monday.
static func day_in_phase(state: Dictionary) -> int:
	var pweek: int = maxi(1, int(state.get("phase_week", 1)))
	var wday: int = clampi(int(state.get("week_day", 0)), 0, DAYS_PER_WEEK - 1)
	return (pweek - 1) * DAYS_PER_WEEK + wday + 1


# True iff the current phase is a league phase AND we're inside its league
# weeks (i.e., before the trailing playoff weeks). Drives schedule lookups.
func is_league_match_week() -> bool:
	var s: Dictionary = _gm.season_state
	var phase: int = int(s["current_phase"])
	var lw: int = phase_league_weeks(phase)
	return lw > 0 and int(s["phase_week"]) <= lw


# True iff the current phase is a league phase AND we're inside its trailing
# playoff week (LEAGUE_WEEKS+1: SF Saturday, F Sunday).
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


# ── Old saves (format 1 / 2 → 3) ─────────────────────────────────────────────
## Brings a run saved under an older week format onto the current one (one round a day
## on Sat · Sun, 4 league weeks + 1 playoff week, 2 INTL weeks). No-op once
## `schedule_format` is `SCHEDULE_FORMAT`. Called by `SaveSystem.load_run`; static, so no
## scene is needed.
##
## * League phase: every match of the phase is re-stamped by its round (round r → week
##   r / 2 + 1, `matchday` r % 2), results kept; in a league week `phase_week` moves to the
##   week of the first unplayed round. In the playoffs `phase_week` = the playoff week and
##   the bracket is re-stamped (SF Saturday, F Sunday).
## * INTL phase: QF week 1 Saturday, SF week 1 Sunday, F week 2 Saturday; `phase_week`
##   follows the first unplayed bracket round.
## * A stored Saturday ban/pick (`pending_match` without a result) is dropped: ban/pick
##   now runs right before the match.
## Matches keep their array index (`pending_match.schedule_idx` stays valid). Moving
## `phase_week` mid-week starts a fresh mental week record (`MentalSystem.week_key`).
static func migrate_weekly_format(state: Dictionary) -> void:
	if int(state.get("schedule_format", 1)) >= SCHEDULE_FORMAT:
		return
	state["schedule_format"] = SCHEDULE_FORMAT
	var pm: Variant = state.get("pending_match", null)
	if pm is Dictionary and int((pm as Dictionary).get("winner_side", -1)) < 0:
		state["pending_match"] = null
	var phase: int = int(state.get("current_phase", 0))
	var lw: int = int(LEAGUE_WEEKS.get(phase, 0))
	var t: Variant = state.get("current_tournament", null)
	var bracket: Array = (t as Dictionary).get("bracket", []) if t is Dictionary else []
	if lw <= 0:
		# INTL: slots 0..3 QF, 4..5 SF, 6 F.
		var first_open: int = -1
		for m_raw in bracket:
			var m: Dictionary = m_raw
			var slot: int = int(m.get("slot", 0))
			m["phase_week"] = 2 if slot >= 6 else 1
			m["matchday"] = 1 if slot == 4 or slot == 5 else 0
			if first_open < 0 and not bool(m.get("played", false)):
				first_open = slot
		if not bracket.is_empty():
			state["phase_week"] = 2 if first_open >= 6 or first_open < 0 else 1
		return
	var sched: Array = state.get("match_schedule", [])
	var first_open_round: int = -1
	var last_round: int = 0
	for m_raw in sched:
		var m: Dictionary = m_raw
		if int(m.get("phase", -1)) != phase or bool(m.get("void", false)):
			continue
		var r: int = int(m.get("round", 0))
		m["phase_week"] = floori(r / float(ROUNDS_PER_WEEK)) + 1
		m["matchday"] = r % ROUNDS_PER_WEEK
		if int(m["phase_week"]) > lw:
			# A format-1 double round robin's second half: no room left, voided.
			m["played"] = true
			m["winner"] = -1
			m["phase_week"] = 0
			m["void"] = true
			continue
		last_round = maxi(last_round, r)
		if not bool(m.get("played", false)) and (first_open_round < 0 or r < first_open_round):
			first_open_round = r
	var playoff: bool = int(state.get("phase_week", 1)) > _FORMAT2_LEAGUE_WEEKS \
			or (t is Dictionary and String((t as Dictionary).get("type", "")) == "PLAYOFF")
	if playoff:
		# SF1 · SF2 on Saturday, F on Sunday of the one playoff week.
		state["phase_week"] = lw + 1
		for m_raw in bracket:
			var m: Dictionary = m_raw
			m["phase_week"] = lw + 1
			m["matchday"] = 1 if int(m.get("slot", 0)) >= 2 else 0
		return
	var round_now: int = first_open_round if first_open_round >= 0 else last_round
	state["phase_week"] = mini(lw, floori(round_now / float(ROUNDS_PER_WEEK)) + 1)
