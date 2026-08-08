class_name RecallSystem
extends Node

# Simplified recall: when a pilot drops to <= RECALL_HP_THRESHOLD HP, they are
# instantly teleported to their HQ at full HP. During CARD_PHASE the recall
# check is held; it runs again when the phase ends.

@onready var _bs: BattleSim = get_parent() as BattleSim


# Called by SimulationCore each BATTLE turn.
func process_recalls(log_lines: Array) -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive:
			continue
		if float(p.hp) / float(p.max_hp) <= _bs.RECALL_HP_THRESHOLD:
			_teleport_home(p, log_lines, "low HP")


# Called by CardPhaseManager.end_card_phase() before returning to BATTLE.
# Recalls any pilot under the HP threshold, OR any non-jungler whose card-effect
# placement put them outside their lane path.
func process_phase_end_recalls(log_lines: Array) -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive:
			continue
		if float(p.hp) / float(p.max_hp) <= _bs.RECALL_HP_THRESHOLD:
			_teleport_home(p, log_lines, "low HP")
			continue
		if _is_out_of_position(p):
			_teleport_home(p, log_lines, "out of position")


# A pilot is "out of position" only when card effects clearly displaced them:
#  - jungler is sitting on an enemy-owned jungle cell, OR
#  - lane pilot is sitting on any jungle cell (own or enemy).
# Pilots in transit between lane waypoints aren't flagged — a strict path-cell
# check would constantly mis-trigger during normal advance.
func _is_out_of_position(p: PilotData) -> bool:
	var zone_owner: int = _bs.neutral_zone_cells.get(p.grid_pos, -2)
	if zone_owner == -2:
		return false
	if p.is_guerrilla:
		return zone_owner == 1 - p.team
	# Lane pilot on any jungle cell counts as displaced.
	return true


func _teleport_home(p: PilotData, log_lines: Array, reason: String) -> void:
	var orig_pos := p.grid_pos
	p.grid_pos      = _bs.PLAYER_HQ_POS if p.team == 0 else _bs.ENEMY_HQ_POS
	p.hp            = p.max_hp
	p.shield        = 0   # 보호막 is consumed on 본진 복귀
	p.waypoint_idx  = 0
	_bs.anim_pilot_recall(p, orig_pos)
	log_lines.append("%s recalled (%s)" % [_bs.pilot_label(p), reason])
