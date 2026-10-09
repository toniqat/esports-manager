class_name PlayerData
extends Resource

@export var id: int = 0
## 이름 l10n key(`players.name_key` / `intl_players.name_key`). 세이브에도 이 key 만
## 들어간다(설계서 D7) — 표시는 아래 `name`.
@export var name_key: String = ""
## 표시 이름 — 현재 로케일로 그때그때 푼다. 읽기 전용.
var name: String:
	get:
		return Loc.t(name_key)  # l10n-dynamic: name.player.* name.intl_player.*
@export var role: int = 0          # GameEnums.Role
@export var team_id: int = 0       # 0 = player, 1 = enemy

# ─── 선수 스탯 6종 ────────────────────────────────────────────────────────────
# **하한 1, 상한 없음.** 예전 5종(laning / mechanics / gamesense / teamfight /
# mental)은 삭제됐다 — 그것들은 아웃게임 숫자였을 뿐 인게임에서 실제로 읽히는
# 것은 mechanics(→hit) 와 gamesense(→evasion) 둘뿐이었고, 나머지 셋은 전력
# 합산에만 쓰였다. 지금의 여섯은 **전부 전투 계산의 입력**이다.
#
# | 스탯 | 읽는 자리 |
# |---|---|
# | `field_hit`  전장 명중 | `SimulationCore.roll_hit` (→ `PilotData.hit`) |
# | `field_eva`  전장 회피 | `SimulationCore.roll_hit` (→ `PilotData.evasion`) |
# | `engage_hit` 교전 명중 | `TurnEngageSim._hit_chance` (→ `PilotData.engage_hit`) |
# | `engage_eva` 교전 회피 | `TurnEngageSim._hit_chance` (→ `PilotData.engage_eva`) |
# | `atk_growth` 공격력 성장 계수 | `BattleSim.refresh_growth_stats` |
# | `hp_growth`  체력 성장 계수   | `BattleSim.refresh_growth_stats` |
#
# 명중 넷은 **비율**로 읽힌다 — `hit/(hit+eva)` 를 [`PILOT_HIT_MIN`, `PILOT_HIT_MAX`] 구간에 리맵하므로
# (`PilotData.hit_chance`) 절대값이 아니라 상대 파일럿과의 비가 확률을 정한다.
# 성장 계수 둘은 `GROWTH_STAT_BASE` 를 1.0 으로 보는 **배율**이다 — 그 두 배면
# 성장이 두 배, 절반이면 절반.
@export var field_hit: int   = 50
@export var field_eva: int   = 50
@export var engage_hit: int  = 50
@export var engage_eva: int  = 50
@export var atk_growth: int  = 50
@export var hp_growth: int   = 50

## 스탯 여섯의 **유일한 표**. 화면마다 자기 배열을 들고 있으면 같은 선수가
## 화면마다 다른 순서로 읽히고, 스탯이 하나 늘 때 고쳐야 할 자리가 여섯 군데가
## 된다. 훈련 타일의 색도 이 순서를 그대로 쓴다(`TrainingTile.COLOR_STATS`).
const STAT_KEYS: Array = [
	"field_hit", "field_eva", "engage_hit", "engage_eva", "atk_growth", "hp_growth",
]
## 이름 · 한 줄 설명의 l10n key — `STAT_KEYS` 와 같은 순서. 화면은 표를 직접
## 읽지 않고 `stat_label(i)` · `stat_note(i)` 로 번역된 글자를 받는다. 약칭은 쓰지 않는다
## ("전명" 대신 "전장 명중") — 좁은 칸도 이름 전체를 적는다.
const STAT_LABELS: Array = [  # l10n-keys: term.stat.*.name
	L.TERM_STAT_FIELD_HIT_NAME, L.TERM_STAT_FIELD_EVA_NAME, L.TERM_STAT_ENGAGE_HIT_NAME,
	L.TERM_STAT_ENGAGE_EVA_NAME, L.TERM_STAT_ATK_GROWTH_NAME, L.TERM_STAT_HP_GROWTH_NAME,
]
## 한 줄 설명. 숫자만으로는 "그래서 무엇을 가르는 값인가"가 안 나오는 자리
## (파일럿 상세 패널 · 훈련 결과 · 드래프트 팝업)가 함께 읽는다.
const STAT_NOTES: Array = [  # l10n-keys: term.stat.*.note
	L.TERM_STAT_FIELD_HIT_NOTE, L.TERM_STAT_FIELD_EVA_NOTE, L.TERM_STAT_ENGAGE_HIT_NOTE,
	L.TERM_STAT_ENGAGE_EVA_NOTE, L.TERM_STAT_ATK_GROWTH_NOTE, L.TERM_STAT_HP_GROWTH_NOTE,
]


## 스탯 `i`(`STAT_KEYS` 순)의 이름 — 현재 로케일. 범위 밖은 "".
static func stat_label(i: int) -> String:
	if i < 0 or i >= STAT_LABELS.size():
		return ""
	return Loc.t(String(STAT_LABELS[i]))  # l10n-dynamic: term.stat.*.name


## 스탯 `i` 의 한 줄 설명 — 현재 로케일. 범위 밖은 "".
static func stat_note(i: int) -> String:
	if i < 0 or i >= STAT_NOTES.size():
		return ""
	return Loc.t(String(STAT_NOTES[i]))  # l10n-dynamic: term.stat.*.note

## 성장 계수 배율의 기준점 — 이 값에서 배율이 정확히 1.0 이 되고, 그 1.0 이
## 지금의 밸런스(`BattleSim.growth_curve` 그대로)다.
##
## **스탯 범위의 한가운데가 아니라 실측에서 나온 값이다** — `players.csv` 선수들의
## 성장 계수 평균에 맞췄다(표가 스탯 범위의 한가운데가 아니라 위쪽에 몰려 있다).
## 기준을 범위 중앙에 두면 개시부터 전원이 기준보다 빨리 자라 "성장 계수를
## 도입했더니 아무도 안 건드린 밸런스가 밀렸다"가 된다. 평균 근처에 두면 평균이
## 거의 ×1.0, 모브는 그 아래, 최상위는 그 위라 계수가 **차이를 만들되 기준선을
## 옮기지는 않는다**. 훈련으로 스탯을 더 올리면 그만큼 배율이 오른다.
## 값은 data/csv/const.csv — ConstTable 로 읽는다.
static var GROWTH_STAT_BASE: float = ConstTable.num("PLAYER_GROWTH_STAT_BASE")

## 스탯 하한. 상한은 **없다** — 훈련으로 계속 자란다.
static var STAT_MIN: int = ConstTable.int_of("PLAYER_STAT_MIN")

# ─── 파일럿 스킬 / 모브 ───────────────────────────────────────────────────────
# 이 선수의 고유 파일럿 스킬 id(`pilot_skills.id`), -1 = 없음. 스킬은 라인에
# 묶여 있어 같은 역할의 스킬만 붙는다(players.csv 가 그 짝을 들고 있다).
@export var skill_id: int = -1
# 모브 파일럿 — 스킬이 없고 스탯이 네임드보다 낮으며 초상화가 실루엣으로
# 나온다. 스탯 하향은 CSV 값에 이미 반영돼 있으므로 런타임 분기가 없다.
@export var is_mob: bool = false
# **고정 파일럿 카드 3장** — `cards.id` 목록(`players.pilot_cards`). 매 판 같은
# 3장이 이 선수의 파일럿 카드로 덱에 들어간다. 비어 있으면
# `GameManager.pilot_card_ids_for` 가 선수 id 를 씨앗 삼아 결정적으로 채운다.
@export var pilot_cards: Array = []

# ─── Run setup (salary cap · rank · level) ───────────────────────────────────
# `salary` = base salary (`players.salary`) plus the applied rank effects (`apply_rank`:
# `salary_down` rows, `RANK_SALARY_STEP`). The level bonus is added on read —
# `RunRules.salary_of(pd)`.
@export var salary: int = 0
# Stars ★1..★3 (`players.rarity`; mobs 0) — gacha tier and acquisition rank. Never changes.
@export var rarity: int = 0
# Level of this copy (0 .. 10 × rank). `RunRules.apply_level` has **already** added the level
# bonus to the stats before writing it — stat fields are always post-level values.
@export var level: int = 0
# 주력 메크 `mechs.id` 목록(`players.main_mechs`, M4). 런 시작 메크 숙련도가
# 이 메크들만 높게 시작한다(`MechMastery.init_run`).
@export var main_mechs: Array = []
# Rank 0..5 applied to this copy (`RunRules.apply_rank` already folded the rank rows'
# stat / salary / card effects into the fields above). 0 = CSV base (no rows applied).
@export var rank: int = 0
## @deprecated — old name of `rank` (kept so older readers / saves still work).
var breakthrough: int:
	get:
		return rank
	set(v):
		rank = v
# Extra training EXP % from `stat_growth` rank rows (TrainingBoard multiplies).
@export var train_bonus_pct: int = 0

# Set during the assign phase: which mech this player is piloting this match.
var assigned_mech: MechData = null


func _init(p_id: int = 0, p_name_key: String = "", p_role: int = 0, p_team_id: int = 0,
		p_field_hit: int = 50, p_field_eva: int = 50,
		p_engage_hit: int = 50, p_engage_eva: int = 50,
		p_atk_growth: int = 50, p_hp_growth: int = 50,
		p_skill_id: int = -1, p_is_mob: bool = false) -> void:
	id = p_id
	name_key = p_name_key
	role = p_role
	team_id = p_team_id
	field_hit   = p_field_hit
	field_eva   = p_field_eva
	engage_hit  = p_engage_hit
	engage_eva  = p_engage_eva
	atk_growth  = p_atk_growth
	hp_growth   = p_hp_growth
	skill_id = p_skill_id
	is_mob = p_is_mob


## 스탯 여섯의 합. 전력 비교(리그 AI 시뮬 · 드래프트 정렬 · 허브 로스터)가
## 전부 이 한 함수를 지난다 — 예전에는 다섯 필드를 손으로 더한 식이 여덟
## 군데에 흩어져 있어 스탯이 바뀔 때마다 여덟 곳을 고쳐야 했다.
func stat_total() -> int:
	return field_hit + field_eva + engage_hit + engage_eva + atk_growth + hp_growth


## 스탯 여섯의 평균. 리그 / 국제전 AI 가 팀 전력을 재는 단위.
func stat_avg() -> float:
	return float(stat_total()) / float(STAT_KEYS.size())


## 성장 계수 하나를 배율로. `GROWTH_STAT_BASE` → 1.0, 그 두 배 → 2.0.
static func growth_mult(stat_value: int) -> float:
	return maxf(0.0, float(stat_value) / GROWTH_STAT_BASE)
