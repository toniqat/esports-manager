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
@export var presence: int = 4
# 속도(40~100) — 교전 아레나의 ATB 게이지 충전 속도. 높을수록 자기 차례가 자주
# 돌아오고, 느린 메크가 한 번 행동할 때 두 번 행동하기도 한다. 전장(턴제)은
# 이 값을 읽지 않는다 — 전장 이동은 PilotData.move_range 소관.
@export var speed: int = 70


func _init(p_id: int = 0, p_name: String = "",
		p_hp: int = 100, p_atk: int = 10, p_presence: int = 4,
		p_speed: int = 70) -> void:
	id = p_id
	name = p_name
	hp = p_hp
	atk = p_atk
	presence = p_presence
	speed = p_speed
