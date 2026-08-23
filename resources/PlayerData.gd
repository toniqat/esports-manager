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

# ─── 파일럿 스킬 ─────────────────────────────────────────────────────────────
# 이 선수의 고유 파일럿 스킬 id(`pilot_skills.id`), -1 = 없음. 스킬은 라인에
# 묶여 있어 같은 역할의 스킬만 붙는다(players.csv 가 그 짝을 들고 있다).
@export var skill_id: int = -1

# Set during the assign phase: which mech this player is piloting this match.
var assigned_mech: MechData = null


func _init(p_id: int = 0, p_name: String = "", p_role: int = 0, p_team_id: int = 0,
		p_laning: int = 50, p_mechanics: int = 50, p_gamesense: int = 50,
		p_teamfight: int = 50, p_mental: int = 50,
		p_skill_id: int = -1) -> void:
	id = p_id
	name = p_name
	role = p_role
	team_id = p_team_id
	laning = p_laning
	mechanics = p_mechanics
	gamesense = p_gamesense
	teamfight = p_teamfight
	mental = p_mental
	skill_id = p_skill_id
