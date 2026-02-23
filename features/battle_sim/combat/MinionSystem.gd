class_name MinionSystem
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim


func spawn_minions() -> void:
	if _bs.turn_count % _bs.MINION_SPAWN_INTERVAL != 0:
		return
	for lane in range(3):
		for team in range(2):
			var m          := MinionData.new()
			m.team         = team
			m.lane         = lane
			m.count        = _bs.MINION_SPAWN_COUNT
			m.grid_pos     = _bs.PLAYER_HQ_POS if team == 0 else _bs.ENEMY_HQ_POS
			m.waypoint_idx = 0
			m.alive        = true
			_bs._minions.append(m)


func move_minions(_log_lines: Array) -> void:
	for raw in _bs._minions:
		var m := raw as MinionData
		if not m.alive:
			continue
		# Stop if any enemy turret, pilot, or opposing minion is in current cell
		var blocked := false
		for t in _bs.turrets:
			var td := t as TurretData
			if td.alive and td.team != m.team and td.grid_pos == m.grid_pos:
				blocked = true; break
		if not blocked:
			for raw_p in _bs.pilots:
				var p := raw_p as PilotData
				if p.alive and p.team != m.team and p.grid_pos == m.grid_pos:
					blocked = true; break
		if not blocked:
			for raw2 in _bs._minions:
				var m2 := raw2 as MinionData
				if m2.alive and m2.team != m.team and m2.grid_pos == m.grid_pos:
					blocked = true; break
		if blocked:
			continue

		var path: Array = _bs.LANE_PATHS_TEAM0[m.lane] if m.team == 0 \
				else _bs.LANE_PATHS_TEAM1[m.lane]
		var max_wp := path.size() - 2  # never enter enemy HQ (last element)
		while m.waypoint_idx < max_wp:
			if m.grid_pos == (path[m.waypoint_idx] as Vector2i):
				m.waypoint_idx += 1
			else:
				break
		var goal: Vector2i = path[mini(m.waypoint_idx, max_wp)] as Vector2i
		if m.grid_pos == goal:
			continue
		var next := _bs._pathfinder.bfs_next_step(m.grid_pos, goal, null, null, 0, -1)
		if next != m.grid_pos:
			m.grid_pos = next


func merge_minions() -> void:
	var groups: Dictionary = {}
	for raw in _bs._minions:
		var m := raw as MinionData
		if not m.alive:
			continue
		var key := str(m.team) + "_" + str(m.grid_pos)
		if not groups.has(key):
			groups[key] = m
		else:
			var first := groups[key] as MinionData
			first.count += m.count
			m.alive = false


func process_minion_combat(minion_dmg: Dictionary, log_lines: Array) -> void:
	var cell_m0: Dictionary = {}
	var cell_m1: Dictionary = {}
	for raw in _bs._minions:
		var m := raw as MinionData
		if not m.alive:
			continue
		if m.team == 0:
			cell_m0[m.grid_pos] = m
		else:
			cell_m1[m.grid_pos] = m
	for pos in cell_m0.keys():
		if not cell_m1.has(pos):
			continue
		var m0 := cell_m0[pos] as MinionData
		var m1 := cell_m1[pos] as MinionData
		var dmg_to_m0 := m1.count / 2
		var dmg_to_m1 := m0.count / 2
		minion_dmg[m0] = minion_dmg.get(m0, 0) + dmg_to_m0
		minion_dmg[m1] = minion_dmg.get(m1, 0) + dmg_to_m1
		log_lines.append("Minion clash: A%d↔E%d" % [m0.count, m1.count])


func get_friendly_minions_at(pos: Vector2i, team: int) -> bool:
	for raw in _bs._minions:
		var m := raw as MinionData
		if m.alive and m.team == team and m.grid_pos == pos:
			return true
	return false


func get_minions_at_cell(pos: Vector2i, team: int):
	for raw in _bs._minions:
		var m := raw as MinionData
		if m.alive and m.team == team and m.grid_pos == pos:
			return m
	return null


func furthest_minion_in_lane(lane: int, team: int):
	var best    = null
	var best_wp := -1
	for raw in _bs._minions:
		var m := raw as MinionData
		if m.alive and m.team == team and m.lane == lane:
			if m.waypoint_idx > best_wp:
				best_wp = m.waypoint_idx
				best    = m
	return best
