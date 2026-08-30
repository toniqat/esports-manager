class_name PlayerData
extends Resource

@export var id: int = 0
@export var name: String = ""
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
# 명중 넷은 **비율**로 읽힌다 — `hit/(hit+eva)` 를 80~100% 구간에 리맵하므로
# (`PilotData.hit_chance`) 절대값이 아니라 상대 파일럿과의 비가 확률을 정한다.
# 성장 계수 둘은 `GROWTH_STAT_BASE`(50)를 1.0 으로 보는 **배율**이다 — 100 이면
# 성장이 두 배, 25 면 절반.
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
const STAT_LABELS: Array = [
	"전장 명중", "전장 회피", "교전 명중", "교전 회피", "공격 성장", "체력 성장",
]
const STAT_SHORT: Array = ["전명", "전회", "교명", "교회", "공성", "체성"]
## 한 줄 설명. 숫자만으로는 "그래서 무엇을 가르는 값인가"가 안 나오는 자리
## (파일럿 상세 패널 · 훈련 결과 · 드래프트 팝업)가 함께 읽는다.
const STAT_NOTES: Array = [
	"전장 교전과 공격 카드의 명중 판정에 쓰인다. 상대 전장 회피와의 비가 확률을 정한다.",
	"전장에서 맞을 확률을 낮춘다. 상대 전장 명중과의 비가 확률을 정한다.",
	"교전 무대에서만 읽는 명중. 전장 명중과 따로 산다.",
	"교전 무대에서만 읽는 회피. 전장 회피와 따로 산다.",
	"성장치가 공격력으로 바뀌는 기울기. 50 이 기준(×1.0)이고 상한이 없다.",
	"성장치가 최대 체력으로 바뀌는 기울기. 50 이 기준(×1.0)이고 상한이 없다.",
]

## 성장 계수 배율의 기준점 — 이 값에서 배율이 정확히 1.0 이 되고, 그 1.0 이
## 지금의 밸런스(`BattleSim.GROWTH_ATK_PER_SCORE` 그대로)다.
##
## **50 이 아니라 80 인 것은 실측에서 나온 값이다** — `players.csv` 40명의
## 성장 계수 평균이 78.2 / 75.5 이고 네임드만 보면 85 다(스탯 1~100 의 한가운데가
## 아니라 위쪽에 몰려 있는 표다). 기준을 50 으로 두면 개시부터 전원이 ×1.56 으로
## 자라 "성장 계수를 도입했더니 아무도 안 건드린 밸런스가 56% 밀렸다"가 된다.
## 80 이면 평균이 ×0.98, 모브가 ×0.83, 최상위가 ×1.13 이라 계수가 **차이를
## 만들되 기준선을 옮기지는 않는다**. 훈련으로 100 을 넘기면 그때부터 ×1.25 이상.
const GROWTH_STAT_BASE: float = 80.0

## 스탯 하한. 상한은 **없다** — 훈련으로 100 을 넘겨 계속 자란다.
const STAT_MIN: int = 1

# ─── 파일럿 스킬 / 모브 ───────────────────────────────────────────────────────
# 이 선수의 고유 파일럿 스킬 id(`pilot_skills.id`), -1 = 없음. 스킬은 라인에
# 묶여 있어 같은 역할의 스킬만 붙는다(players.csv 가 그 짝을 들고 있다).
@export var skill_id: int = -1
# 모브 파일럿 — 스킬이 없고 스탯이 네임드보다 낮으며 초상화가 실루엣으로
# 나온다. 스탯 하향은 CSV 값에 이미 반영돼 있으므로 런타임 분기가 없다.
@export var is_mob: bool = false

# Set during the assign phase: which mech this player is piloting this match.
var assigned_mech: MechData = null


func _init(p_id: int = 0, p_name: String = "", p_role: int = 0, p_team_id: int = 0,
		p_field_hit: int = 50, p_field_eva: int = 50,
		p_engage_hit: int = 50, p_engage_eva: int = 50,
		p_atk_growth: int = 50, p_hp_growth: int = 50,
		p_skill_id: int = -1, p_is_mob: bool = false) -> void:
	id = p_id
	name = p_name
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


## 성장 계수 하나를 배율로. 50 → 1.0, 100 → 2.0, 25 → 0.5.
static func growth_mult(stat_value: int) -> float:
	return maxf(0.0, float(stat_value) / GROWTH_STAT_BASE)
