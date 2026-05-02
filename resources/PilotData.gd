class_name PilotData
extends RefCounted

var role: int
var hp: int
var max_hp: int
var atk: int
var team: int
var grid_pos: Vector2i
var alive: bool           = true
var respawn_timer: int    = 0
var heal_amount: int      = 0
var lane: int             = GameEnums.LanePosition.GUERRILLA
var is_guerrilla: bool    = false
var recall_state: int     = GameEnums.RecallState.NONE
var channel_timer: int    = 0
var recall_safe_pos: Vector2i = Vector2i(-1, -1)
var waypoint_idx: int     = 0
var move_range: int       = 1                # cells advanced per turn
var jungle_start_pref: int = -1              # GameEnums.JungleStartDir or -1 (none)

func _init(p_role: int, p_team: int, p_pos: Vector2i, stats: Dictionary) -> void:
	role     = p_role
	team     = p_team
	grid_pos = p_pos
	hp       = stats["hp"]
	max_hp   = stats["hp"]
	atk      = stats["atk"]
	if stats.has("heal"):
		heal_amount = stats["heal"]
	if stats.has("move_range"):
		move_range = max(1, int(stats["move_range"]))
