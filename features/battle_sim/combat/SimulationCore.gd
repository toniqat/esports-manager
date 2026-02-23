class_name SimulationCore
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim


# ─── Main turn loop ───────────────────────────────────────────────────────────
func simulate_turn() -> void:
	if _bs.game_over or _bs.game_phase != GameEnums.BattlePhase.BATTLE:
		return
	_bs.turn_count += 1
	process_respawns()

	# Apply pending ATK buffs from card plays this turn
	var buff_p  := _bs._pending_atk_buff_p
	var buff_ai := _bs._pending_atk_buff_ai
	var buffed_pilots: Array = []
	if buff_p > 0 or buff_ai > 0:
		for raw_p in _bs.pilots:
			var bp := raw_p as PilotData
			if not bp.alive: continue
			if bp.team == 0 and buff_p > 0:
				bp.atk += buff_p
				buffed_pilots.append(bp)
			elif bp.team == 1 and buff_ai > 0:
				bp.atk += buff_ai
				buffed_pilots.append(bp)

	var log_lines: Array = []
	_bs._recall_sys.check_danger_state(log_lines)
	_bs._recall_sys.process_channeling(log_lines)
	_bs._minion_sys.spawn_minions()
	_bs._minion_sys.move_minions(log_lines)
	_bs._minion_sys.merge_minions()

	var damage_map:    Dictionary = {}  # PilotData  → int
	var turret_dmg:    Dictionary = {}  # TurretData → int
	var minion_dmg:    Dictionary = {}  # MinionData → int
	var turret_minion_atk_applied: Dictionary = {}  # TurretData → bool
	var hq_damage_p:   int        = 0
	var hq_damage_e:   int        = 0

	_bs._minion_sys.process_minion_combat(minion_dmg, log_lines)

	for raw_pilot in _bs.pilots:
		var pilot := raw_pilot as PilotData
		if not pilot.alive:
			continue

		# RETREATING: move toward safe pos, no combat
		if pilot.recall_state == GameEnums.RecallState.RETREATING:
			var next := _bs._pathfinder.bfs_next_step(pilot.grid_pos, pilot.recall_safe_pos,
					pilot, null, 0, -1)
			if next != pilot.grid_pos:
				pilot.grid_pos = next
			if pilot.grid_pos == pilot.recall_safe_pos:
				pilot.recall_state  = GameEnums.RecallState.CHANNELING
				pilot.channel_timer = _bs.RECALL_CHANNEL_TURNS
				log_lines.append("%s begins channeling" % _bs.pilot_label(pilot))
			continue

		# CHANNELING: handled in process_channeling(), skip all actions
		if pilot.recall_state == GameEnums.RecallState.CHANNELING:
			continue

		var enemies: Array = get_enemies_in_range(pilot)
		var etrs:    Array = get_turrets_in_range(pilot)

		# Find lowest-tier attackable turret (requires friendly minion shield)
		var attackable_turret = null
		if not etrs.is_empty():
			var td := etrs[0] as TurretData
			for te in etrs:
				if (te as TurretData).tier < td.tier:
					td = te as TurretData
			if _bs._minion_sys.get_friendly_minions_at(td.grid_pos, pilot.team):
				attackable_turret = td

		if not enemies.is_empty():
			var t = pick_target(pilot, enemies)
			if not damage_map.has(t): damage_map[t] = 0
			damage_map[t] += pilot.atk
			log_lines.append("%s→%s:%d" % [_bs.pilot_label(pilot),
					_bs.pilot_label(t as PilotData), pilot.atk])

		elif attackable_turret != null:
			var td := attackable_turret as TurretData
			if not turret_dmg.has(td): turret_dmg[td] = 0
			turret_dmg[td] += pilot.atk
			if not turret_minion_atk_applied.has(td):
				var shield: MinionData = _bs._minion_sys.get_minions_at_cell(td.grid_pos, pilot.team)
				if shield != null:
					turret_dmg[td] += int(ceil(float((shield as MinionData).count) / float(_bs.MINION_SIEGE_ATK_DIVISOR)))
					turret_minion_atk_applied[td] = true
			log_lines.append("%s→T%d[%s]:%d" % [_bs.pilot_label(pilot), td.tier,
					_bs.LANE_NAMES[td.lane], pilot.atk])

		elif pilot.role == GameEnums.Role.SUPPORT:
			var allies: Array = get_allies_in_range(pilot)
			var w = find_weakest_ally(allies)
			if w != null:
				var wp := w as PilotData
				wp.hp = min(wp.hp + pilot.heal_amount, wp.max_hp)
				log_lines.append("Su heals %s+%d" % [_bs.pilot_label(wp), pilot.heal_amount])
			else:
				var defending_team := 1 if pilot.team == 0 else 0
				var ehq := _bs.ENEMY_HQ_POS if pilot.team == 0 else _bs.PLAYER_HQ_POS
				if _bs._pathfinder.manhattan(pilot.grid_pos, ehq) <= 1 and any_t2_destroyed(defending_team):
					if pilot.team == 0: hq_damage_e += pilot.atk
					else:               hq_damage_p += pilot.atk
					log_lines.append("%s→HQ:%d" % [_bs.pilot_label(pilot), pilot.atk])
				elif _bs._pathfinder.manhattan(pilot.grid_pos, ehq) > 1:
					move_pilot(pilot)
		else:
			var defending_team := 1 if pilot.team == 0 else 0
			var ehq := _bs.ENEMY_HQ_POS if pilot.team == 0 else _bs.PLAYER_HQ_POS
			if _bs._pathfinder.manhattan(pilot.grid_pos, ehq) <= 1 and any_t2_destroyed(defending_team):
				if pilot.team == 0: hq_damage_e += pilot.atk
				else:               hq_damage_p += pilot.atk
				log_lines.append("%s→HQ:%d" % [_bs.pilot_label(pilot), pilot.atk])
			elif _bs._pathfinder.manhattan(pilot.grid_pos, ehq) > 1:
				move_pilot(pilot)

	# Turrets retaliate — minions absorb all damage; pilots immune while minions present
	for t in _bs.turrets:
		var td := t as TurretData
		if not td.alive:
			continue
		var shield: MinionData = _bs._minion_sys.get_minions_at_cell(td.grid_pos, 1 - td.team)
		if shield != null:
			minion_dmg[shield] = minion_dmg.get(shield, 0) + td.atk
		else:
			for raw in _bs.pilots:
				var p := raw as PilotData
				if p.alive and p.team != td.team and p.grid_pos == td.grid_pos:
					if not damage_map.has(p): damage_map[p] = 0
					damage_map[p] += td.atk

	# Apply pilot damage
	for t in damage_map.keys():
		var p := t as PilotData
		p.hp -= damage_map[t]
		if p.hp <= 0:
			p.hp = 0; p.alive = false; p.respawn_timer = _bs.RESPAWN_TURNS
			log_lines.append("%s died" % _bs.pilot_label(p))

	# Apply turret damage
	for t in turret_dmg.keys():
		var td := t as TurretData
		td.hp -= turret_dmg[t]
		if td.hp <= 0:
			td.hp = 0; td.alive = false
			log_lines.append("T%d %s turret destroyed!" % [td.tier, _bs.LANE_NAMES[td.lane]])

	# Apply minion damage
	for key in minion_dmg.keys():
		var m := key as MinionData
		m.count -= minion_dmg[key]
		if m.count <= 0:
			m.alive = false

	_bs.enemy_hq_hp  = max(0, _bs.enemy_hq_hp  - hq_damage_e)
	_bs.player_hq_hp = max(0, _bs.player_hq_hp - hq_damage_p)

	# Reset ATK buffs applied this turn
	for raw_p in buffed_pilots:
		var bp := raw_p as PilotData
		if bp.team == 0:
			bp.atk -= buff_p
		elif bp.team == 1:
			bp.atk -= buff_ai
	_bs._pending_atk_buff_p  = 0
	_bs._pending_atk_buff_ai = 0

	process_neutral_zone_captures()
	if not log_lines.is_empty(): _bs.last_log = log_lines[0]
	check_win_condition()
	_bs._renderer.queue_redraw()
	_bs._hud.update_hud()


# ─── Targeting ────────────────────────────────────────────────────────────────
func get_enemies_in_range(pilot: PilotData) -> Array:
	var result: Array = []
	for raw in _bs.pilots:
		var o := raw as PilotData
		if o.alive and o.team != pilot.team and o.grid_pos == pilot.grid_pos:
			result.append(o)
	return result


func get_turrets_in_range(pilot: PilotData) -> Array:
	var result: Array = []
	for t in _bs.turrets:
		var td := t as TurretData
		if td.alive and td.team != pilot.team and td.grid_pos == pilot.grid_pos:
			if td.tier == 2 and t1_alive_in_lane(td.team, td.lane):
				continue
			result.append(td)
	return result


func get_allies_in_range(pilot: PilotData) -> Array:
	var result: Array = []
	for raw in _bs.pilots:
		var o := raw as PilotData
		if o.alive and o.team == pilot.team and o != pilot \
				and _bs._pathfinder.manhattan(pilot.grid_pos, o.grid_pos) == 1:
			result.append(o)
	return result


func find_weakest_ally(allies: Array):
	var weakest = null
	for raw in allies:
		var a := raw as PilotData
		if float(a.hp) / float(a.max_hp) < 1.0:
			if weakest == null or a.hp < (weakest as PilotData).hp:
				weakest = a
	return weakest


func pick_target(attacker: PilotData, candidates: Array):
	var best = candidates[0]
	match attacker.role:
		GameEnums.Role.ASSASSIN:
			for c in candidates:
				if (c as PilotData).hp < (best as PilotData).hp: best = c
		GameEnums.Role.SNIPER:
			for c in candidates:
				if (c as PilotData).hp > (best as PilotData).hp: best = c
		_:
			var bd: int = _bs._pathfinder.chebyshev(attacker.grid_pos, (best as PilotData).grid_pos)
			for c in candidates:
				var d: int = _bs._pathfinder.chebyshev(attacker.grid_pos, (c as PilotData).grid_pos)
				if d < bd: best = c; bd = d
	return best


# ─── Movement ─────────────────────────────────────────────────────────────────
func move_pilot(pilot: PilotData) -> void:
	var goal:     Vector2i
	var stop_dist := 0

	if pilot.is_guerrilla:
		var capture_target := nearest_uncaptured_zone(pilot)
		if capture_target != Vector2i(-1, -1):
			goal      = capture_target
			stop_dist = 0
		else:
			var t = lowest_hp_enemy(pilot)
			if t != null:
				goal      = (t as PilotData).grid_pos
				stop_dist = 0
			else:
				goal      = _bs.ENEMY_HQ_POS if pilot.team == 0 else _bs.PLAYER_HQ_POS
				stop_dist = 1
	elif pilot.role == GameEnums.Role.SUPPORT:
		var w = weak_ally_target(pilot)
		if w != null:
			goal      = (w as PilotData).grid_pos
			stop_dist = 1
		else:
			goal      = current_waypoint(pilot)
			var ehq   := _bs.ENEMY_HQ_POS if pilot.team == 0 else _bs.PLAYER_HQ_POS
			stop_dist = 1 if goal == ehq else 0
	else:
		goal      = current_waypoint(pilot)
		var ehq   := _bs.ENEMY_HQ_POS if pilot.team == 0 else _bs.PLAYER_HQ_POS
		stop_dist = 1 if goal == ehq else 0

	var next := _bs._pathfinder.bfs_next_step(pilot.grid_pos, goal, pilot, null, stop_dist, -1)
	if next != pilot.grid_pos:
		pilot.grid_pos = next


func get_lane_turret(lane: int, team: int, tier: int):
	for t in _bs.turrets:
		var td := t as TurretData
		if td.team == team and td.lane == lane and td.tier == tier:
			return td
	return null


func current_waypoint(pilot: PilotData) -> Vector2i:
	var path: Array = _bs.LANE_PATHS_TEAM0[pilot.lane] if pilot.team == 0 \
			else _bs.LANE_PATHS_TEAM1[pilot.lane]
	while pilot.waypoint_idx < path.size() - 1:
		var wp: Vector2i = path[pilot.waypoint_idx] as Vector2i
		if pilot.grid_pos == wp and not enemy_turret_blocking_at(wp, pilot.team):
			pilot.waypoint_idx += 1
		else:
			break
	return path[min(pilot.waypoint_idx, path.size() - 1)] as Vector2i


func enemy_turret_blocking_at(pos: Vector2i, friendly_team: int) -> bool:
	for t in _bs.turrets:
		var td := t as TurretData
		if td.alive and td.team != friendly_team and td.grid_pos == pos:
			if td.tier == 2 and t1_alive_in_lane(td.team, td.lane):
				continue
			return true
	return false


func nearest_uncaptured_zone(pilot: PilotData) -> Vector2i:
	var own_zones: Array = _bs.NEUTRAL_ZONE_FRIENDLY_LEFT + _bs.NEUTRAL_ZONE_FRIENDLY_RIGHT \
			if pilot.team == 0 \
			else _bs.NEUTRAL_ZONE_ENEMY_LEFT + _bs.NEUTRAL_ZONE_ENEMY_RIGHT
	var best      := Vector2i(-1, -1)
	var best_dist := 999999
	for raw_cell in own_zones:
		var cv := raw_cell as Vector2i
		if _bs._neutral_zone_cells.get(cv, -1) != pilot.team:
			var d := _bs._pathfinder.manhattan(pilot.grid_pos, cv)
			if d < best_dist:
				best_dist = d
				best      = cv
	return best


func lowest_hp_enemy(pilot: PilotData):
	var best = null
	for raw in _bs.pilots:
		var o := raw as PilotData
		if o.alive and o.team != pilot.team:
			if best == null or o.hp < (best as PilotData).hp: best = o
	return best


func weak_ally_target(pilot: PilotData):
	var weakest = null
	for raw in _bs.pilots:
		var o := raw as PilotData
		if o.alive and o.team == pilot.team and o != pilot:
			if float(o.hp) / float(o.max_hp) < 0.5:
				if weakest == null or o.hp < (weakest as PilotData).hp: weakest = o
	return weakest


func has_enemy_turret_at(pos: Vector2i, pilot_team: int) -> bool:
	for t in _bs.turrets:
		var td := t as TurretData
		if td.alive and td.team != pilot_team and td.grid_pos == pos:
			return true
	return false


func t1_alive_in_lane(team: int, lane: int) -> bool:
	for t in _bs.turrets:
		var td := t as TurretData
		if td.team == team and td.lane == lane and td.tier == 1 and td.alive:
			return true
	return false


func any_t2_destroyed(defending_team: int) -> bool:
	for t in _bs.turrets:
		var td := t as TurretData
		if td.team == defending_team and td.tier == 2 and not td.alive:
			return true
	return false


# ─── Respawn ─────────────────────────────────────────────────────────────────
func process_respawns() -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive:
			p.respawn_timer -= 1
			if p.respawn_timer <= 0:
				p.grid_pos     = _bs.PLAYER_HQ_POS if p.team == 0 else _bs.ENEMY_HQ_POS
				p.hp           = p.max_hp
				p.alive        = true
				p.recall_state = GameEnums.RecallState.NONE
				p.channel_timer = 0
				p.waypoint_idx  = 0


# ─── Ownership & Spawn ───────────────────────────────────────────────────────
func init_ownership_map() -> void:
	_bs.ownership_map.resize(_bs.GRID_COLS * _bs.GRID_ROWS)
	_bs.ownership_map.fill(-1)
	_bs.ownership_map[_bs.PLAYER_HQ_POS.x + _bs.PLAYER_HQ_POS.y * _bs.GRID_COLS] = 0
	_bs.ownership_map[_bs.ENEMY_HQ_POS.x  + _bs.ENEMY_HQ_POS.y  * _bs.GRID_COLS] = 1


func init_neutral_zones() -> void:
	_bs._neutral_zone_cells.clear()
	for cell in _bs.NEUTRAL_ZONE_FRIENDLY_LEFT:
		_bs._neutral_zone_cells[cell as Vector2i] = -1
	for cell in _bs.NEUTRAL_ZONE_FRIENDLY_RIGHT:
		_bs._neutral_zone_cells[cell as Vector2i] = -1
	for cell in _bs.NEUTRAL_ZONE_ENEMY_LEFT:
		_bs._neutral_zone_cells[cell as Vector2i] = -1
	for cell in _bs.NEUTRAL_ZONE_ENEMY_RIGHT:
		_bs._neutral_zone_cells[cell as Vector2i] = -1


func process_neutral_zone_captures() -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive or not p.is_guerrilla:
			continue
		if _bs._neutral_zone_cells.has(p.grid_pos):
			_bs._neutral_zone_cells[p.grid_pos] = p.team


func capture_tile(pos: Vector2i, team: int) -> void:
	if pos == _bs.PLAYER_HQ_POS or pos == _bs.ENEMY_HQ_POS:
		return
	_bs.ownership_map[pos.x + pos.y * _bs.GRID_COLS] = team


func update_ownership() -> void:
	var cell_teams: Dictionary = {}
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive: continue
		if not cell_teams.has(p.grid_pos):
			cell_teams[p.grid_pos] = {}
		(cell_teams[p.grid_pos] as Dictionary)[p.team] = true

	for cell in cell_teams.keys():
		var cv: Vector2i = cell as Vector2i
		if cv == _bs.PLAYER_HQ_POS or cv == _bs.ENEMY_HQ_POS: continue
		var teams: Dictionary = cell_teams[cell] as Dictionary
		if teams.size() == 1:
			var team: int = teams.keys()[0] as int
			_bs.ownership_map[cv.x + cv.y * _bs.GRID_COLS] = team


func spawn_pilots_with_lanes() -> void:
	_bs.pilots.clear()
	init_ownership_map()
	var roles: Array[int] = [
		GameEnums.Role.TANK, GameEnums.Role.FIGHTER, GameEnums.Role.ASSASSIN,
		GameEnums.Role.SUPPORT, GameEnums.Role.SNIPER,
	]

	for i in range(5):
		var lid: int = _bs._gambit_lanes[i]
		var pilot := PilotData.new(roles[i], 0, _bs.PLAYER_HQ_POS, _bs.ROLE_STATS[roles[i]])
		pilot.lane         = lid
		pilot.is_guerrilla = (lid == GameEnums.Lane.GUERRILLA)
		pilot.waypoint_idx = 0
		_bs.pilots.append(pilot)

	var base_lanes: Array = [GameEnums.Lane.LEFT, GameEnums.Lane.CENTER, GameEnums.Lane.RIGHT]
	var extra: int = base_lanes[randi() % 3]
	var e_assign: Array = [
		GameEnums.Lane.LEFT, GameEnums.Lane.CENTER, GameEnums.Lane.RIGHT,
		extra, GameEnums.Lane.GUERRILLA,
	]
	e_assign.shuffle()
	var e_roles: Array = roles.duplicate()
	e_roles.shuffle()

	for i in range(5):
		var lid: int = e_assign[i]
		var pilot := PilotData.new(e_roles[i], 1, _bs.ENEMY_HQ_POS, _bs.ROLE_STATS[e_roles[i]])
		pilot.lane         = lid
		pilot.is_guerrilla = (lid == GameEnums.Lane.GUERRILLA)
		pilot.waypoint_idx = 0
		_bs.pilots.append(pilot)


func spawn_turrets() -> void:
	_bs.turrets.clear()
	var e_t1 := [
		Vector2i(_bs.TURRET_COLS_T1[0], _bs.TURRET_ROW_T1_TEAM1),
		Vector2i(_bs.TURRET_COLS_T1[1], _bs.TURRET_ROW_T1_TEAM1),
		Vector2i(_bs.TURRET_COLS_T1[2], _bs.TURRET_ROW_T1_TEAM1),
	]
	var e_t2 := [
		Vector2i(_bs.TURRET_COLS_T2[0], _bs.TURRET_ROW_T2_TEAM1),
		Vector2i(_bs.TURRET_COLS_T2[1], _bs.TURRET_ROW_T2_TEAM1),
		Vector2i(_bs.TURRET_COLS_T2[2], _bs.TURRET_ROW_T2_TEAM1),
	]
	var p_t1 := [
		Vector2i(_bs.TURRET_COLS_T1[0], _bs.TURRET_ROW_T1_TEAM0),
		Vector2i(_bs.TURRET_COLS_T1[1], _bs.TURRET_ROW_T1_TEAM0),
		Vector2i(_bs.TURRET_COLS_T1[2], _bs.TURRET_ROW_T1_TEAM0),
	]
	var p_t2 := [
		Vector2i(_bs.TURRET_COLS_T2[0], _bs.TURRET_ROW_T2_TEAM0),
		Vector2i(_bs.TURRET_COLS_T2[1], _bs.TURRET_ROW_T2_TEAM0),
		Vector2i(_bs.TURRET_COLS_T2[2], _bs.TURRET_ROW_T2_TEAM0),
	]
	for lane_idx in range(3):
		_bs.turrets.append(TurretData.new(1, e_t1[lane_idx] as Vector2i, 1, lane_idx, _bs.TURRET_HP, _bs.TURRET_ATK))
		_bs.turrets.append(TurretData.new(1, e_t2[lane_idx] as Vector2i, 2, lane_idx, _bs.TURRET_HP, _bs.TURRET_ATK))
		_bs.turrets.append(TurretData.new(0, p_t1[lane_idx] as Vector2i, 1, lane_idx, _bs.TURRET_HP, _bs.TURRET_ATK))
		_bs.turrets.append(TurretData.new(0, p_t2[lane_idx] as Vector2i, 2, lane_idx, _bs.TURRET_HP, _bs.TURRET_ATK))


# ─── Win Condition ────────────────────────────────────────────────────────────
func check_win_condition() -> void:
	if _bs.enemy_hq_hp <= 0:
		_bs.game_over = true
		_bs._lbl_victory.text  = "Player Team Wins!"
		_bs._panel_victory.visible = true
	elif _bs.player_hq_hp <= 0:
		_bs.game_over = true
		_bs._lbl_victory.text  = "Opponent Team Wins!"
		_bs._panel_victory.visible = true
