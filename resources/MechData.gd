class_name MechData
extends Resource

# 메크는 **역할군을 갖는다**(GameEnums.Role, -1 = 없음). 예전 주석은 "메크에는
# 역할이 없다 — 어느 슬롯에도 앉힐 수 있다" 였는데, 메크마다 고유 패시브와 고유
# 카드 셋이 붙으면서 그 카드들이 역할을 전제하게 됐다(탱커 메크의 반응 장갑,
# 원딜 메크의 사거리 지정 공격 …). 다만 **배정 자체는 여전히 자유다** — 이
# 값은 밴픽 화면의 분류와 데이터 검증에 쓰이고, ASSIGN 이 어느 슬롯에 어느
# 메크를 앉힐지는 막지 않는다.
@export var id: int = 0
@export var name: String = ""
@export var role: int = -1

# Combat stats — drive PilotData hp/atk when this mech is piloted.
@export var hp: int = 100
@export var atk: int = 10
# 존재감 — 전투 개시(engage)에서만 사용. 근접 메크 4, 원거리 메크 2.
# 피격 확률 가중치(높을수록 자주 표적이 됨).
#
# **속도(speed) 스탯은 삭제됐다.** 교전이 ATB 실시간에서 라운드 기반 턴제로
# 돌아가면서 "차례가 얼마나 자주 오는가"라는 개념 자체가 사라졌다 — 이제
# 라운드마다 전원이 정확히 한 번씩 행동한다. 되살리지 말 것.
@export var presence: int = 4


func _init(p_id: int = 0, p_name: String = "",
		p_hp: int = 100, p_atk: int = 10, p_presence: int = 4) -> void:
	id = p_id
	name = p_name
	hp = p_hp
	atk = p_atk
	presence = p_presence
