class_name GambitPhaseManager
extends Node

# Stripped from the old in-battle lane-assignment UI. Lane assignment is now
# fixed by role and lane direction is decided in MatchFlow's JungleStart phase.
#
# Role → Lane mapping (constant):
#   TANK     → LEFT
#   FIGHTER  → CENTER
#   ASSASSIN → GUERRILLA
#   SUPPORT  → RIGHT
#   SNIPER   → RIGHT

@onready var _bs: BattleSim = get_parent() as BattleSim


# Indexed by role (0..4). Returns LanePosition.
const ROLE_TO_LANE: Array = [
	GameEnums.LanePosition.LEFT,        # 0 TANK
	GameEnums.LanePosition.CENTER,      # 1 FIGHTER
	GameEnums.LanePosition.GUERRILLA,   # 2 ASSASSIN
	GameEnums.LanePosition.RIGHT,       # 3 SUPPORT
	GameEnums.LanePosition.RIGHT,       # 4 SNIPER
]


func auto_assign_lanes() -> void:
	# Fills _bs._gambit_lanes for the player team in role order (0..4).
	for i in range(5):
		_bs._gambit_lanes[i] = ROLE_TO_LANE[i]


# Runs the same flow that the old "Launch Battle" button performed.
func launch_battle() -> void:
	_bs._minions = []
	_bs.sim_core.spawn_pilots_with_lanes()
	_bs.sim_core.spawn_turrets()
	_bs.sim_core.init_neutral_zones()
	_bs.game_phase = GameEnums.BattlePhase.BATTLE
	_bs._renderer.queue_redraw()
	_bs._hud.update_hud()
