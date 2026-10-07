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
## 포지션 키 → 이름 l10n key. 화면은 `position_label(key)` 로 읽는다.
const POSITION_LABELS: Dictionary = {  # l10n-keys: term.position.*
	POS_TOP: L.TERM_POSITION_TOP, POS_JUNGLE: L.TERM_POSITION_JUNGLE, POS_MID: L.TERM_POSITION_MID,
	POS_CARRY: L.TERM_POSITION_CARRY, POS_SUPPORT: L.TERM_POSITION_SUPPORT,
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


## 포지션 키 → 현재 로케일 이름("탑" · "Top"). 모르는 키는 "—".
static func position_label(pos_key: String) -> String:
	if not POSITION_LABELS.has(pos_key):
		return "—"
	return Loc.t(String(POSITION_LABELS[pos_key]))  # l10n-dynamic: term.position.*


## 역할 → 포지션 이름 (`position_label(position_key(role))`).
static func role_position_label(role: int) -> String:
	return position_label(position_key(role))


enum SeasonPhase {
	PRESEASON,        # Dec      — short league before first international
	PRESEASON_INTL,   # Jan      — international tournament #1
	MIDSEASON,        # Feb–Apr  — league
	MIDSEASON_INTL,   # May      — international tournament #2
	REGULAR,          # Jun–Sep  — main league
	REGULAR_INTL,     # Oct–Nov  — final international (win = ending)
}

## 시즌 페이즈 → 이름 l10n key. 화면은 `phase_label(phase)` 로 읽는다 — 화면마다
## 페이즈 이름 표를 따로 들지 않는다.
const PHASE_LABELS: Dictionary = {  # l10n-keys: term.phase.*
	SeasonPhase.PRESEASON:      L.TERM_PHASE_PRESEASON,
	SeasonPhase.PRESEASON_INTL: L.TERM_PHASE_PRESEASON_INTL,
	SeasonPhase.MIDSEASON:      L.TERM_PHASE_MIDSEASON,
	SeasonPhase.MIDSEASON_INTL: L.TERM_PHASE_MIDSEASON_INTL,
	SeasonPhase.REGULAR:        L.TERM_PHASE_REGULAR,
	SeasonPhase.REGULAR_INTL:   L.TERM_PHASE_REGULAR_INTL,
}


## 시즌 페이즈 → 현재 로케일 이름("프리시즌 국제대회" …). 모르는 값은 "—".
static func phase_label(phase: int) -> String:
	if not PHASE_LABELS.has(phase):
		return "—"
	return Loc.t(String(PHASE_LABELS[phase]))  # l10n-dynamic: term.phase.*


## 등급 이름 0..4 (일반 · 고급 · 희귀 · 영웅 · 전설) — 특성 · 기벽이 함께 쓴다.
## 범위 밖은 양끝으로 자른다. 3단 등급(기벽 일반 · 희귀 · 영웅)은 부르는 쪽이 0 · 2 · 3 으로 옮긴다.
const RARITY_LABELS: Array = [  # l10n-keys: term.rarity.*
	L.TERM_RARITY_COMMON, L.TERM_RARITY_UNCOMMON, L.TERM_RARITY_RARE,
	L.TERM_RARITY_EPIC, L.TERM_RARITY_LEGENDARY,
]


static func rarity_label(tier: int) -> String:
	return Loc.t(String(RARITY_LABELS[clampi(tier, 0, RARITY_LABELS.size() - 1)]))  # l10n-dynamic: term.rarity.*


# ─── 성향 태그 (`pilot_skills.keyword` · `mech_passives.keyword`) ─────────────
# CSV 값은 `|` 로 이은 ascii id(`engage|strategy`). 표시만 한다 — 규칙이 읽지 않는다.
const TAG_LABELS: Dictionary = {  # l10n-keys: term.tag.*
	"engage": L.TERM_TAG_ENGAGE, "strategy": L.TERM_TAG_STRATEGY, "roam": L.TERM_TAG_ROAM,
	"growth": L.TERM_TAG_GROWTH, "objective": L.TERM_TAG_OBJECTIVE, "combat": L.TERM_TAG_COMBAT,
	"support": L.TERM_TAG_SUPPORT, "kill_assist": L.TERM_TAG_KILL_ASSIST,
	"turret_kill": L.TERM_TAG_TURRET_KILL, "vulnerable": L.TERM_TAG_VULNERABLE,
}


## 태그 id 하나 → 이름. 모르는 id 는 그대로.
static func tag_label(tag_id: String) -> String:
	if not TAG_LABELS.has(tag_id):
		return tag_id
	return Loc.t(String(TAG_LABELS[tag_id]))  # l10n-dynamic: term.tag.*


## `keyword` 셀(`engage|strategy`) → "교전, 전략 점수". 빈 셀은 "".
static func tags_text(raw: String) -> String:
	var names: PackedStringArray = []
	for t in raw.split("|", false):
		var tag_id: String = String(t).strip_edges()
		if not tag_id.is_empty():
			names.append(tag_label(tag_id))
	return Loc.t(L.UI_LIST_SEPARATOR).join(names)


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
