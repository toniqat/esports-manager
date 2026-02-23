class_name CardData
extends Resource

@export var card_name: String = ""
@export var cost: int = 1
@export var description: String = ""
@export var effect_type: String = ""   # "damage" | "focus_damage" | "heal" | "buff_atk" | "minions"
@export var effect_value: int = 0

func _init(p_name: String = "", p_cost: int = 1, p_desc: String = "") -> void:
	card_name = p_name
	cost = p_cost
	description = p_desc
