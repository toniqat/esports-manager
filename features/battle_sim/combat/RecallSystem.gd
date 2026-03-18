class_name RecallSystem
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim


func compute_recall_safe_pos(pilot: PilotData) -> Vector2i:
	var friendly_turrets: Array = []
	for t in _bs.turrets:
		var td := t as TurretData
		if td.alive and td.team == pilot.team:
			friendly_turrets.append(td)

	var best_turret = null
	var best_dist   := 999999

	# Prefer same-lane turret for non-guerrilla pilots
	if not pilot.is_guerrilla and pilot.lane != GameEnums.LanePosition.GUERRILLA:
		for t in friendly_turrets:
			var td := t as TurretData
			if td.lane == pilot.lane:
				var d := _bs.pathfinder.manhattan(pilot.grid_pos, td.grid_pos)
				if d < best_dist:
					best_dist   = d
					best_turret = td

	# Guerrilla or no same-lane turret: search all friendly turrets
	if best_turret == null:
		for t in friendly_turrets:
			var td := t as TurretData
			var d := _bs.pathfinder.manhattan(pilot.grid_pos, td.grid_pos)
			if d < best_dist:
				best_dist   = d
				best_turret = td

	var offset := Vector2i(0, 1) if pilot.team == 0 else Vector2i(0, -1)
	if best_turret != null:
		var td := best_turret as TurretData
		var sp := td.grid_pos + offset
		sp.x = clampi(sp.x, 0, _bs.GRID_COLS - 1)
		sp.y = clampi(sp.y, 0, _bs.GRID_ROWS - 1)
		return sp

	# No alive friendly turrets — 1 step in front of own HQ
	if pilot.team == 0:
		return _bs.PLAYER_HQ_POS + Vector2i(0, -1)
	else:
		return _bs.ENEMY_HQ_POS + Vector2i(0, 1)


func check_danger_state(log_lines: Array) -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.alive and p.recall_state == GameEnums.RecallState.NONE:
			if float(p.hp) / float(p.max_hp) <= _bs.RECALL_HP_THRESHOLD:
				p.recall_state    = GameEnums.RecallState.RETREATING
				p.recall_safe_pos = compute_recall_safe_pos(p)
				log_lines.append("%s enters Danger State!" % _bs.pilot_label(p))


func process_channeling(log_lines: Array) -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive or p.recall_state != GameEnums.RecallState.CHANNELING:
			continue
		var interrupted := false
		for raw2 in _bs.pilots:
			var o := raw2 as PilotData
			if o.alive and o.team != p.team and o.grid_pos == p.grid_pos:
				interrupted = true
				break
		if interrupted:
			p.recall_state    = GameEnums.RecallState.RETREATING
			p.recall_safe_pos = compute_recall_safe_pos(p)
			log_lines.append("%s channel interrupted!" % _bs.pilot_label(p))
		else:
			p.channel_timer -= 1
			if p.channel_timer <= 0:
				p.grid_pos     = _bs.PLAYER_HQ_POS if p.team == 0 else _bs.ENEMY_HQ_POS
				p.hp           = p.max_hp
				p.recall_state = GameEnums.RecallState.NONE
				p.waypoint_idx = 0
				log_lines.append("%s recalled to HQ at full HP!" % _bs.pilot_label(p))
