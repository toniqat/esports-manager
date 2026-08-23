class_name CardData
extends Resource

# 시전자 제약 값 (cards.csv `scope` 컬럼).
const SCOPE_ANY    := "any"      # 누구나 가질 수 있음
const SCOPE_LANE   := "lane"     # 레인 파일럿 전용 (전진 등)
const SCOPE_JUNGLE := "jungle"   # 정글러 전용 (약탈 등)

# 키워드 (cards.csv `keyword` 컬럼). **`|` 로 여러 개를 붙일 수 있다** —
# 전령 제압은 `exhaust|preserve` 로 "한 번 쓰면 소멸하되 그때까지는 절대
# 버려지지 않는다"를 함께 단다. 판정은 언제나 `has_keyword()` 를 지나야 한다:
# `keyword == "exhaust"` 로 문자열을 통째로 비교하면 두 번째 키워드가 붙는
# 순간 첫 번째가 조용히 꺼진다.
const KW_EXHAUST  := "exhaust"    # 사용 후 소멸 (덱으로도 discard 로도 안 감)
## 보존 — **버려지지 않는다.** 손패 상한 초과 자동 버리기도, 버리기 계열 카드
## (재고 / 완벽한 마무리 / 과감한 정리 / 솔로 퍼포먼스 / 버리기:N)도 이 카드를
## 건너뛴다. 오브젝트 보상처럼 "쓸 때를 골라야 하는" 한정 카드를 위한 것이라
## 작전 단계 한 번짜리인 계획 중시(`preserve:N` 효과)와는 수명이 다르다 —
## 그쪽은 `BattleSim.preserved_cards_*` 목록, 이쪽은 카드 자신의 키워드다.
const KW_PRESERVE := "preserve"
## 휘발성 — **버려질 때 버린 더미로 가지 않고 그 자리에서 사라진다.** 파일럿
## 스킬이 손패에 직접 만들어 주는 카드들이 단다(배회의 [이동], 복귀 명령의
## [복귀], 격전의 [전투 개시], 약탈자의 [약탈], 공격적인 전진의 [전진]).
## `KW_EXHAUST` 와 짝이지 같은 것이 아니다 — 소멸은 **쓰면** 사라지는 것이고
## 휘발성은 **안 쓰고 버려지면** 사라지는 것이라, 스킬이 준 카드는 어느 쪽으로도
## 덱을 불리지 않는다. 판정은 `CardPhaseManager.send_to_discard` 한 곳을 지난다.
const KW_VOLATILE := "volatile"

# 카드 종류 (cards.csv `card_type` 컬럼). 덱은 파일럿마다 메크 카드
# `MECH_CARDS_PER_PILOT` 장 + 파일럿 카드 `PILOT_CARDS_PER_PILOT` 장으로 돌아간다.
const TYPE_MECH  := "mech"    # 메크에 붙는 카드 (공격 / 전진 / 전투 개시 …)
const TYPE_PILOT := "pilot"   # 파일럿에 붙는 카드 (라인전 / 드로우 / 정글)

# 파일럿 카드의 하위 분류 (cards.csv `card_cat` 컬럼) — **덱 구성 슬롯**을 정한다.
# 시전자 제약을 정하는 `scope` 와는 역할이 다르다.
const CAT_NONE   := "-"        # 메크 카드
const CAT_LANE   := "lane"     # 라인전 슬롯
const CAT_DRAW   := "draw"     # 드로우 슬롯
const CAT_JUNGLE := "jungle"   # 정글 슬롯
# 라인전 슬롯과 정글 슬롯 **양쪽** 후보에 들어가는 카드. 복귀(id 21) 하나뿐이다 —
# 라인전 카드로 분류하면서도 정글러가 자기 슬롯으로 뽑을 수 있어야 하기 때문.
const CAT_COMMON := "common"

@export var card_name: String = ""
@export var cost: int = 1
@export var uses: int = 1                 # cards.csv 컬럼. 소멸 판정에는 쓰이지 않는다 (keyword == "exhaust" 만 소멸)
@export var cast_method: String = "instant"  # range / target / location / instant
@export var target: String = "hand"       # caster / enemy / ally / pilot / hand / location
@export var cast_range: int = 0           # tiles from caster (0 = self, 99 = unbounded)
@export var area: int = 0                 # AoE radius around target (0 = single)
@export var keyword: String = ""          # `|` 로 구분된 키워드 목록 — has_keyword() 로만 읽는다
@export var effect: String = ""           # semicolon list, e.g. "draw:2;discard:2"
@export var description: String = ""
# 시전자 제약. CardPhaseManager.build_starter_decks 가 파일럿별 미니덱을 돌릴
# 때 이 값으로 후보를 거른다 — 레인 카드가 정글러 손에, 정글 카드가 레이너
# 손에 들어가지 않게 막는 유일한 지점이다.
@export var scope: String = SCOPE_ANY
# 1 = 랜덤 카드풀 포함, 0 = 제외. 결투처럼 "존재하지만 아직 아무에게도
# 지급되지 않는" 메크 고유 카드가 0을 쓴다.
@export var pool: int = 1
# 메크 카드 / 파일럿 카드. CardPhaseManager._deal_team_deck 의 1차 슬롯 분류.
@export var card_type: String = TYPE_MECH
# 파일럿 카드의 하위 슬롯 분류. 메크 카드는 CAT_NONE.
@export var card_cat: String = CAT_NONE
# 상호 배타 그룹 (cards.csv `excl_group`). 비어 있으면 제약 없음. 값이 같은
# 카드끼리는 **한 파일럿이 하나만** 가질 수 있다 — 스타터 덱을 돌리는
# `CardPhaseManager._sample` 이 유일한 소비자다. 첫 사례인 안전한 파밍 ↔
# 공격적인 라인전은 같은 `lane_stat` 슬롯을 정반대 방향으로 밀어서, 한 사람이
# 둘 다 들면 나중에 낸 쪽이 앞의 것을 지운다(합산이 아니라 덮어쓰기다).
@export var excl_group: String = ""

# Runtime — set when this card is dealt to a pilot's mini-deck. Identifies the
# 시전자 (caster) for effect resolution and drives the owner badge on the UI.
# Not @export'd because PilotData is a transient match-only object.
var owner_pilot: PilotData = null


func _init(p_name: String = "", p_cost: int = 1, p_desc: String = "") -> void:
	card_name = p_name
	cost = p_cost
	description = p_desc


## 이 카드가 `kw` 키워드를 달고 있는가. `keyword` 컬럼은 `|` 로 구분된 목록이라
## 문자열 비교가 아니라 반드시 이 함수를 지나야 한다. 공백은 CSV 손질 실수를
## 흡수하려고 걷어 낸다.
func has_keyword(kw: String) -> bool:
	if keyword.is_empty():
		return false
	for raw in keyword.split("|", false):
		if (raw as String).strip_edges() == kw:
			return true
	return false


## 손패에서 강제로 버려지지 않는 카드인가 — `KW_PRESERVE` 주석 참조.
func is_preserved_by_keyword() -> bool:
	return has_keyword(KW_PRESERVE)


## 버려질 때 버린 더미로 가지 않고 사라지는 카드인가 — `KW_VOLATILE` 주석 참조.
func is_volatile() -> bool:
	return has_keyword(KW_VOLATILE)


## True when a pilot of the given kind may own this card. 정글러는 any + jungle,
## 레인 파일럿은 any + lane 만 받는다. 알 수 없는 scope 값은 제약 없음으로 읽어
## CSV 오타가 카드를 통째로 사라지게 만들지 않는다.
func allowed_for_guerrilla(is_guerrilla: bool) -> bool:
	if scope == SCOPE_LANE:
		return not is_guerrilla
	if scope == SCOPE_JUNGLE:
		return is_guerrilla
	return true


## True when this card is a candidate for the `cat` deck slot.
##
## `CAT_COMMON` sits in **both** the 라인전 and 정글 slot pools — that is the whole
## reason the value exists. 복귀 is a 라인전 card by design, but a 정글러 never
## draws from the 라인전 slot, and dropping the only HP-reset card from the
## jungler's deck was not the intent. Anything else matches its own category
## exactly.
func fits_category(cat: String) -> bool:
	if card_cat == cat:
		return true
	if card_cat != CAT_COMMON:
		return false
	return cat == CAT_LANE or cat == CAT_JUNGLE
