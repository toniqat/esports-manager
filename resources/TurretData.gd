class_name TurretData
extends RefCounted

var team: int
var grid_pos: Vector2i
var hp: int
var max_hp: int
var atk: int
var tier: int
var lane: int
var alive: bool = true

func _init(p_team: int, p_pos: Vector2i, p_tier: int, p_lane: int,
		p_hp: int, p_atk: int) -> void:
	team     = p_team
	grid_pos = p_pos
	tier     = p_tier
	lane     = p_lane
	hp       = p_hp
	max_hp   = p_hp
	atk      = p_atk
