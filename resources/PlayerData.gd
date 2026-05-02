class_name PlayerData
extends Resource

@export var id: int = 0
@export var name: String = ""
@export var role: int = 0          # GameEnums.Role
@export var team_id: int = 0       # 0 = player, 1 = enemy

# Stats (1~100). Position weighting comes later.
@export var laning: int = 50
@export var mechanics: int = 50
@export var gamesense: int = 50
@export var teamfight: int = 50
@export var mental: int = 50

# Set during the assign phase: which mech this player is piloting this match.
var assigned_mech: MechData = null


func _init(p_id: int = 0, p_name: String = "", p_role: int = 0, p_team_id: int = 0,
		p_laning: int = 50, p_mechanics: int = 50, p_gamesense: int = 50,
		p_teamfight: int = 50, p_mental: int = 50) -> void:
	id = p_id
	name = p_name
	role = p_role
	team_id = p_team_id
	laning = p_laning
	mechanics = p_mechanics
	gamesense = p_gamesense
	teamfight = p_teamfight
	mental = p_mental
