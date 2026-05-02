class_name MechData
extends Resource

# Mechs have NO position role — any mech can be assigned to any player slot.
@export var id: int = 0
@export var name: String = ""

# Combat stats — drive PilotData hp/atk/heal/move when this mech is piloted.
@export var hp: int = 100
@export var atk: int = 10
@export var heal: int = 0
@export var move_range: int = 1


func _init(p_id: int = 0, p_name: String = "",
		p_hp: int = 100, p_atk: int = 10, p_heal: int = 0, p_move: int = 1) -> void:
	id = p_id
	name = p_name
	hp = p_hp
	atk = p_atk
	heal = p_heal
	move_range = p_move
