class_name GameEnums
extends RefCounted

enum Role  { TANK, FIGHTER, ASSASSIN, SUPPORT, SNIPER }
enum LanePosition  { LEFT = 0, CENTER = 1, RIGHT = 2, GUERRILLA = 3 }
enum BattlePhase { GAMBIT, CARD_PHASE, BATTLE, ENGAGE }
enum TowerLevel { HQ, LEVEL_2, LEVEL_1 }
enum Lane { NONE = -1, LEFT = 0, CENTER = 1, RIGHT = 2 }

# Match flow (out-of-battle) phases. PREP is a pre-match dashboard showing
# both rosters' stats; the player confirms with "경기 시작" to enter BAN_PICK.
enum MatchPhase { LOAD, PREP, BAN_PICK, ASSIGN, JUNGLE_START, LAUNCH }
enum JungleStartDir { LEFT = 0, RIGHT = 1 }
enum DraftSide { BLUE = 0, RED = 1 }

# Season (out-game) phases. Six events from December → next year.
enum SeasonPhase {
	PRESEASON,        # Dec      — short league before first international
	PRESEASON_INTL,   # Jan      — international tournament #1
	MIDSEASON,        # Feb–Apr  — league
	MIDSEASON_INTL,   # May      — international tournament #2
	REGULAR,          # Jun–Sep  — main league
	REGULAR_INTL,     # Oct–Nov  — final international (win = ending)
}

# Training categories. MATCH is locked on Fri/Sat/Sun afternoons during seasons.
enum TrainingType {
	REST,
	LANING,
	MECHANICS,
	GAMESENSE,
	TEAMFIGHT,
	SCRIM,
	MATCH,
}

# Result of a single league match-day or playoff series.
enum MatchDayResult { PENDING, WIN, LOSS }

# Tournament progression — used to track playoff/elimination state.
# PLAYOFF_* = Phase 7 4-team SE bracket. INTL_* = Phase 8 8-team SE bracket.
enum TournamentStage {
	LEAGUE,
	PLAYOFF_QF,
	PLAYOFF_SF,
	PLAYOFF_F,
	INTL_QF,
	INTL_SF,
	INTL_F,
	ELIMINATED,
	CHAMPION,
}
