class_name MechData
extends Resource

# Mechs have NO position role — any mech can be assigned to any player slot.
@export var id: int = 0
@export var name: String = ""

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
