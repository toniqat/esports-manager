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

# ── 한 주 안의 요일 ─────────────────────────────────────────────────────────
# 주는 **월~일 이레**로 흐른다(`season_state["week_day"]` 0..6). 월~금 닷새는
# 훈련판의 다섯 줄이고, **토·일 이틀이 경기일**이다. 그 두 날에 실제로 경기가
# 배정되는지는 스케줄이 정한다 — 없으면 그날은 그냥 넘어간다.
const DAYS_PER_WEEK: int = 7
## 훈련이 있는 요일 수 (월~금). 훈련판의 행 수(`TrainingBoard.ROWS`)와 같다.
const TRAINING_DAYS: int = 5
## 경기가 설 수 있는 요일 index → 경기일 번호(0 = 토, 1 = 일).
const MATCH_DAYS: Dictionary = {5: 0, 6: 1}
## 리그가 한 주에 소화하는 라운드 수. 토 한 라운드, 일 한 라운드.
const ROUNDS_PER_WEEK: int = 2

# Total length (in weeks) of each SeasonPhase. League phases run **2 rounds
# per week** (토 · 일), so PRESEASON (single round-robin = 7 rounds) = 4 league
# weeks — 마지막 주는 토요일 한 라운드만 남는다 — plus a 2-week playoff
# (SF week + F week). MID/REGULAR (double round-robin = 14 rounds) = 7 league
# weeks + 2 playoff. INTL phases are 3-week 8-team SE tournaments
# (QF week + SF week + F week).
#
# **토너먼트는 여전히 주 1경기다** — 플레이오프도 국제대회도 한 주에 자기
# 라운드 하나뿐이고, 그 경기는 **토요일**(matchday 0)에 선다. 8강·4강·결승은
# 라운드 사이에 한 주씩 쉬어야 대진표가 읽히고, 리그처럼 이틀에 몰면
# 3주짜리 국제대회가 이틀 반으로 줄어든다.
const PHASE_WEEKS: Dictionary = {
	GameEnums.SeasonPhase.PRESEASON:      6,    # 4 league + 2 playoff
	GameEnums.SeasonPhase.PRESEASON_INTL: 3,    # QF / SF / F
	GameEnums.SeasonPhase.MIDSEASON:      9,    # 7 league + 2 playoff
	GameEnums.SeasonPhase.MIDSEASON_INTL: 3,
	GameEnums.SeasonPhase.REGULAR:        9,    # 7 league + 2 playoff
	GameEnums.SeasonPhase.REGULAR_INTL:   3,
}

# League-only weeks per phase (excludes the trailing 2 playoff weeks). Used
# by LeagueManager to enumerate scheduled rounds, and to gate
# is_league_match_week(). = ceil(rounds / ROUNDS_PER_WEEK).
const LEAGUE_WEEKS: Dictionary = {
	GameEnums.SeasonPhase.PRESEASON: 4,    # 7 rounds
	GameEnums.SeasonPhase.MIDSEASON: 7,    # 14 rounds
	GameEnums.SeasonPhase.REGULAR:   7,    # 14 rounds
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


## 그 요일의 경기일 번호(0 = 토, 1 = 일). 경기가 설 수 없는 요일이면 -1.
## **경기가 실제로 배정돼 있는가는 이 함수가 답하지 않는다** — 그건 스케줄이
## 답한다(`LeagueManager.player_match_on_day` 등).
static func matchday_of(day: int) -> int:
	return int(MATCH_DAYS.get(day, -1))


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
