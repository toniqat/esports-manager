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
# ─── 파일럿 다섯을 늘어놓는 순서 ───────────────────────────────────────────
# **탑 · 정글 · 미드 · 원딜 · 서폿** — MOBA 라인 순서이고, 전장의 왼쪽에서
# 오른쪽으로 훑은 순서(LEFT · GUERRILLA · CENTER · RIGHT · RIGHT)와도 같다.
# `Role` 열거값 순서(TANK · FIGHTER · ASSASSIN · SUPPORT · SNIPER)를 그대로 쓰면
# 정글러가 세 번째, 원딜이 다섯 번째로 앉는데 그 배열은 플레이어가 아는
# 라인업과도 지도와도 대응하지 않는다.
#
# **인게임과 아웃게임이 이 표 하나를 함께 읽는다** — 전장 파일럿 스트립,
# 밴픽 화면의 양 팀 블록, 시즌 허브 로스터, 훈련 격자, 훈련 결과, 경기 전
# 대시보드가 전부 같은 순서로 선다. 예전에는 화면마다 자기 순서를 들고 있어
# 같은 다섯 명이 화면마다 다른 자리에 앉았다.
const ROLE_DISPLAY_ORDER: Array = [
	Role.TANK,      # 탑   — LEFT
	Role.ASSASSIN,  # 정글 — GUERRILLA
	Role.FIGHTER,   # 미드 — CENTER
	Role.SNIPER,    # 원딜 — RIGHT
	Role.SUPPORT,   # 서폿 — RIGHT
]


## 역할 → 화면 자리 번호(0..4). 범위 밖 역할은 맨 뒤로 보낸다.
static func role_seat(role: int) -> int:
	var idx: int = ROLE_DISPLAY_ORDER.find(role)
	return idx if idx >= 0 else ROLE_DISPLAY_ORDER.size()


# ─── 포지션 키 (카드 시전자 제약 · 파일럿 카드 슬롯) ─────────────────────────
# `cards.scope` 와 `pilot_card_slots.position` 이 쓰는 문자열. 역할 열거값이 아니라
# 문자열인 이유는 CSV 에 사람이 직접 적는 값이기 때문이다.
const POS_TOP     := "top"
const POS_JUNGLE  := "jungle"
const POS_MID     := "mid"
const POS_CARRY   := "carry"
const POS_SUPPORT := "support"
## 라인 순서(탑 · 정글 · 미드 · 원딜 · 서폿) — `ROLE_DISPLAY_ORDER` 와 같은 줄.
const POSITION_KEYS: Array = [POS_TOP, POS_JUNGLE, POS_MID, POS_CARRY, POS_SUPPORT]
## `scope = lane` 이 뜻하는 네 포지션.
const LANE_POSITIONS: Array = [POS_TOP, POS_MID, POS_CARRY, POS_SUPPORT]
const POSITION_LABELS: Dictionary = {
	POS_TOP: "탑", POS_JUNGLE: "정글", POS_MID: "미드",
	POS_CARRY: "원딜", POS_SUPPORT: "서폿",
}
## 포지션 배지(`PositionBadge`)의 영문 약칭 — 파일럿 포지션을 보여 주는 모든 화면이 이 글자를 쓴다.
const POSITION_ABBREVS: Dictionary = {
	POS_TOP: "TOP", POS_JUNGLE: "JGL", POS_MID: "MID",
	POS_CARRY: "ADC", POS_SUPPORT: "SUP",
}


## 역할 → 포지션 키. 범위 밖 역할은 빈 문자열.
static func position_key(role: int) -> String:
	var idx: int = ROLE_DISPLAY_ORDER.find(role)
	return String(POSITION_KEYS[idx]) if idx >= 0 else ""


enum SeasonPhase {
	PRESEASON,        # Dec      — short league before first international
	PRESEASON_INTL,   # Jan      — international tournament #1
	MIDSEASON,        # Feb–Apr  — league
	MIDSEASON_INTL,   # May      — international tournament #2
	REGULAR,          # Jun–Sep  — main league
	REGULAR_INTL,     # Oct–Nov  — final international (win = ending)
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
