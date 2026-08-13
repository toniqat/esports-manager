class_name CardData
extends Resource

# 시전자 제약 값 (cards.csv `scope` 컬럼).
const SCOPE_ANY    := "any"      # 누구나 가질 수 있음
const SCOPE_LANE   := "lane"     # 레인 파일럿 전용 (전진 등)
const SCOPE_JUNGLE := "jungle"   # 정글러 전용 (약탈 등)

@export var card_name: String = ""
@export var cost: int = 1
@export var uses: int = 1                 # cards.csv 컬럼. 소멸 판정에는 쓰이지 않는다 (keyword == "exhaust" 만 소멸)
@export var cast_method: String = "instant"  # range / target / location / instant
@export var target: String = "hand"       # caster / enemy / ally / pilot / hand / location
@export var cast_range: int = 0           # tiles from caster (0 = self, 99 = unbounded)
@export var area: int = 0                 # AoE radius around target (0 = single)
@export var keyword: String = ""          # "" or "exhaust"
@export var effect: String = ""           # semicolon list, e.g. "draw:2;discard:2"
@export var description: String = ""
# 시전자 제약. CardPhaseManager.build_starter_decks 가 파일럿별 미니덱을 돌릴
# 때 이 값으로 후보를 거른다 — 레인 카드가 정글러 손에, 정글 카드가 레이너
# 손에 들어가지 않게 막는 유일한 지점이다.
@export var scope: String = SCOPE_ANY
# 1 = 랜덤 카드풀 포함, 0 = 제외. 결투처럼 "존재하지만 아직 아무에게도
# 지급되지 않는" 메크 고유 카드가 0을 쓴다.
@export var pool: int = 1

# Runtime — set when this card is dealt to a pilot's mini-deck. Identifies the
# 시전자 (caster) for effect resolution and drives the owner badge on the UI.
# Not @export'd because PilotData is a transient match-only object.
var owner_pilot: PilotData = null


func _init(p_name: String = "", p_cost: int = 1, p_desc: String = "") -> void:
	card_name = p_name
	cost = p_cost
	description = p_desc


## True when a pilot of the given kind may own this card. 정글러는 any + jungle,
## 레인 파일럿은 any + lane 만 받는다. 알 수 없는 scope 값은 제약 없음으로 읽어
## CSV 오타가 카드를 통째로 사라지게 만들지 않는다.
func allowed_for_guerrilla(is_guerrilla: bool) -> bool:
	if scope == SCOPE_LANE:
		return not is_guerrilla
	if scope == SCOPE_JUNGLE:
		return is_guerrilla
	return true
