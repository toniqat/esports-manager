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
	_bs.recall_sys.check_danger_state(log_lines)
	_bs.recall_sys.process_channeling(log_lines)
	_bs.minion_sys.spawn_minions()
	_bs.minion_sys.move_minions(log_lines)
	_bs.minion_sys.merge_minions()

	var damage_map:    Dictionary = {}  # PilotData  → int
	var turret_dmg:    Dictionary = {}  # TurretData → int
	var minion_dmg:    Dictionary = {}  # MinionData → int
	var turret_minion_atk_applied: Dictionary = {}  # TurretData → bool
	var hq_damage_p:   int        = 0
	var hq_damage_e:   int        = 0

	_bs.minion_sys.process_minion_combat(minion_dmg, log_lines)

	for raw_pilot in _bs.pilots:
		var pilot := raw_pilot as PilotData
		if not pilot.alive:
			continue

		# RETREATING: move toward safe pos, no combat
		if pilot.recall_state == GameEnums.RecallState.RETREATING:
			var next: Vector2i = _bs.pathfinder.bfs_next_step(pilot.grid_pos, pilot.recall_safe_pos,
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
			if _bs.minion_sys.get_friendly_minions_at(td.grid_pos, pilot.team):
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
				var shield: MinionData = _bs.minion_sys.get_minions_at_cell(td.grid_pos, pilot.team)
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
				if pilot.grid_pos == ehq and any_t2_destroyed(defending_team):
					if pilot.team == 0: hq_damage_e += pilot.atk
					else:               hq_damage_p += pilot.atk
					log_lines.append("%s→HQ:%d" % [_bs.pilot_label(pilot), pilot.atk])
				elif pilot.grid_pos != ehq:
					move_pilot(pilot)
		else:
			var defending_team := 1 if pilot.team == 0 else 0
			var ehq := _bs.ENEMY_HQ_POS if pilot.team == 0 else _bs.PLAYER_HQ_POS
			if pilot.grid_pos == ehq and any_t2_destroyed(defending_team):
				if pilot.team == 0: hq_damage_e += pilot.atk
				else:               hq_damage_p += pilot.atk
				log_lines.append("%s→HQ:%d" % [_bs.pilot_label(pilot), pilot.atk])
			elif pilot.grid_pos != ehq:
				move_pilot(pilot)

	# Turrets retaliate — minions absorb all damage; pilots immune while minions present
	for t in _bs.turrets:
		var td := t as TurretData
		if not td.alive:
			continue
		var shield: MinionData = _bs.minion_sys.get_minions_at_cell(td.grid_pos, 1 - td.team)
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
				and _bs.pathfinder.manhattan(pilot.grid_pos, o.grid_pos) == 1:
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
			var bd: int = _bs.pathfinder.chebyshev(attacker.grid_pos, (best as PilotData).grid_pos)
			for c in candidates:
				var d: int = _bs.pathfinder.chebyshev(attacker.grid_pos, (c as PilotData).grid_pos)
				if d < bd: best = c; bd = d
	return best


# ─── Movement ─────────────────────────────────────────────────────────────────
func move_pilot(pilot: PilotData) -> void:
	var steps: int = max(1, pilot.move_range)
	for _i in range(steps):
		var prev := pilot.grid_pos
		_step_pilot_once(pilot)
		if pilot.grid_pos == prev:
			return  # blocked or at goal


func _step_pilot_once(pilot: PilotData) -> void:
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
				stop_dist = 0
	elif pilot.role == GameEnums.Role.SUPPORT:
		var w = weak_ally_target(pilot)
		if w != null:
			goal      = (w as PilotData).grid_pos
			stop_dist = 1
		else:
			goal      = current_waypoint(pilot)
			stop_dist = 0
	else:
		goal      = current_waypoint(pilot)
		stop_dist = 0

	# Gate all pilots at any blocking enemy turret that lies between them and goal
	var gate := lane_turret_gate(pilot, goal)
	if gate != Vector2i(-1, -1):
		goal      = gate
		stop_dist = 0

	var next: Vector2i = _bs.pathfinder.bfs_next_step(pilot.grid_pos, goal, pilot, null, stop_dist, -1)
	if next != pilot.grid_pos:
		pilot.grid_pos = next


# Returns the position of the nearest live enemy turret in the pilot's lane that
# lies between the pilot and goal (closer to goal than pilot is), or (-1,-1) if none.
func lane_turret_gate(pilot: PilotData, goal: Vector2i) -> Vector2i:
	var pilot_to_goal := _bs._hex_grid.hex_distance(pilot.grid_pos, goal)
	if pilot_to_goal == 0:
		return Vector2i(-1, -1)
	var best_pos  := Vector2i(-1, -1)
	var best_dist := pilot_to_goal + 1
	for t in _bs.turrets:
		var td := t as TurretData
		if not td.alive or td.team == pilot.team:
			continue
		if td.tier == 2 and t1_alive_in_lane(td.team, td.lane):
			continue
		# Lane pilots: only turrets in their lane; guerrilla: any enemy turret
		if not pilot.is_guerrilla and td.lane != pilot.lane:
			continue
		var turret_to_goal  := _bs._hex_grid.hex_distance(td.grid_pos, goal)
		var pilot_to_turret := _bs._hex_grid.hex_distance(pilot.grid_pos, td.grid_pos)
		# Turret is "between" pilot and goal, or pilot is already on the turret's cell
		if turret_to_goal <= pilot_to_goal and pilot_to_turret < best_dist:
			best_dist = pilot_to_turret
			best_pos  = td.grid_pos
	return best_pos


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
	# Jungle start preference biases the assassin toward one zone first.
	# Team 0 own zones: NZ index 0 (left) and 1 (right).
	# Team 1 own zones: NZ index 2 (left) and 3 (right).
	var pref_idx := -1
	var alt_idx  := -1
	if pilot.team == 0:
		if pilot.jungle_start_pref == GameEnums.JungleStartDir.LEFT:
			pref_idx = 0; alt_idx = 1
		elif pilot.jungle_start_pref == GameEnums.JungleStartDir.RIGHT:
			pref_idx = 1; alt_idx = 0
	else:
		if pilot.jungle_start_pref == GameEnums.JungleStartDir.LEFT:
			pref_idx = 2; alt_idx = 3
		elif pilot.jungle_start_pref == GameEnums.JungleStartDir.RIGHT:
			pref_idx = 3; alt_idx = 2

	if pref_idx != -1:
		var best := _nearest_in_cells(pilot, _bs.NEUTRAL_ZONES[pref_idx])
		if best != Vector2i(-1, -1):
			return best
		if alt_idx != -1:
			return _nearest_in_cells(pilot, _bs.NEUTRAL_ZONES[alt_idx])
		return Vector2i(-1, -1)

	# No preference — fall back to combined own zones (existing behavior).
	var own_zones: Array = _bs.NEUTRAL_ZONES[0] + _bs.NEUTRAL_ZONES[1] \
			if pilot.team == 0 \
			else _bs.NEUTRAL_ZONES[2] + _bs.NEUTRAL_ZONES[3]
	return _nearest_in_cells(pilot, own_zones)


func _nearest_in_cells(pilot: PilotData, cells: Array) -> Vector2i:
	var best      := Vector2i(-1, -1)
	var best_dist := 999999
	for raw_cell in cells:
		var cv := raw_cell as Vector2i
		if _bs.neutral_zone_cells.get(cv, -1) != pilot.team:
			var d: int = _bs.pathfinder.manhattan(pilot.grid_pos, cv)
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


# ─── Neutral Zones & Spawn ───────────────────────────────────────────────────
func init_neutral_zones() -> void:
	_bs.neutral_zone_cells.clear()
	for zone in _bs.NEUTRAL_ZONES:
		for cell in zone:
			var cv := cell as Vector2i
			_bs.neutral_zone_cells[cv] = -1
			# Reset TileMapLayer tile to NZ atlas tile (source=0, atlas=(3,0), alt=0)
			_bs._tiles_layer.set_cell(cv, 0, Vector2i(3, 0), 0)


func process_neutral_zone_captures() -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive or not p.is_guerrilla:
			continue
		if not _bs.neutral_zone_cells.has(p.grid_pos):
			continue
		# Block capture if any enemy pilot is on the same cell
		var enemy_present := false
		for other_raw in _bs.pilots:
			var o := other_raw as PilotData
			if o.alive and o.team != p.team and o.grid_pos == p.grid_pos:
				enemy_present = true
				break
		if enemy_present:
			continue
		# Skip if already owned by this team
		if _bs.neutral_zone_cells[p.grid_pos] == p.team:
			continue
		_bs.neutral_zone_cells[p.grid_pos] = p.team
		# atlas (1,0) = player-team color (owner_id=1), atlas (2,0) = enemy-team color (owner_id=2)
		var atlas_x := 1 if p.team == 0 else 2
		_bs._tiles_layer.set_cell(p.grid_pos, 0, Vector2i(atlas_x, 0), 0)


func spawn_pilots_with_lanes() -> void:
	_bs.pilots.clear()
	var roles: Array[int] = [
		GameEnums.Role.TANK, GameEnums.Role.FIGHTER, GameEnums.Role.ASSASSIN,
		GameEnums.Role.SUPPORT, GameEnums.Role.SNIPER,
	]
	var ctx: Dictionary = _bs.gm.match_ctx
	var ctx_active: bool   = bool(ctx.get("active", false))
	var p_roster: Array    = ctx.get("player_roster", [])
	var e_roster: Array    = ctx.get("enemy_roster", [])
	var jungle_dir: int    = int(ctx.get("jungle_start_dir", GameEnums.JungleStartDir.LEFT))

	for i in range(5):
		var lid: int = _bs._gambit_lanes[i]
		var stats: Dictionary = _stats_for(ctx_active, p_roster, i, roles[i])
		var pilot := PilotData.new(roles[i], 0, _bs.PLAYER_HQ_POS, stats)
		pilot.lane         = lid
		pilot.is_guerrilla = (lid == GameEnums.LanePosition.GUERRILLA)
		pilot.waypoint_idx = 0
		if pilot.is_guerrilla:
			pilot.jungle_start_pref = jungle_dir
		_bs.pilots.append(pilot)

	# Enemy team uses the same role→lane mapping (no random scramble).
	var e_lanes: Array = GambitPhaseManager.ROLE_TO_LANE
	for i in range(5):
		var lid: int = e_lanes[i]
		var stats: Dictionary = _stats_for(ctx_active, e_roster, i, roles[i])
		var pilot := PilotData.new(roles[i], 1, _bs.ENEMY_HQ_POS, stats)
		pilot.lane         = lid
		pilot.is_guerrilla = (lid == GameEnums.LanePosition.GUERRILLA)
		pilot.waypoint_idx = 0
		if pilot.is_guerrilla:
			# Enemy jungle pref is random for now (no AI lane pre-game choice).
			pilot.jungle_start_pref = randi() % 2
		_bs.pilots.append(pilot)


# Returns a stats dict {hp, atk, heal, move_range} from the assigned mech if
# match_ctx is active, otherwise falls back to the role baseline (move_range=1).
func _stats_for(ctx_active: bool, roster: Array, idx: int, role_id: int) -> Dictionary:
	if ctx_active and idx < roster.size():
		var pd := roster[idx] as PlayerData
		var m: MechData = pd.assigned_mech
		if m != null:
			return {"hp": m.hp, "atk": m.atk, "heal": m.heal, "move_range": m.move_range}
	var base: Dictionary = _bs.ROLE_STATS[role_id]
	return {"hp": base["hp"], "atk": base["atk"], "heal": base.get("heal", 0), "move_range": 1}


func spawn_turrets() -> void:
	_bs.turrets.clear()
	var tp: Dictionary = _bs.TURRET_POSITIONS
	for lane_idx in range(3):
		for team in range(2):
			for tier in [1, 2]:
				var pos: Vector2i
				if not tp.is_empty() and tp.has(lane_idx) and \
						tp[lane_idx].has(team) and tp[lane_idx][team].has(tier):
					pos = tp[lane_idx][team][tier] as Vector2i
				else:
					# Fallback for hex grid: T1=outer, T2=inner
					var cols := [1, 4, 7]
					var _rows_t1: Array = [6, 4]   # team0 T1 outer=row6, team1 T1 outer=row4
					var row_t1: int = _rows_t1[team]
					var _rows_t2: Array = [8, 2]   # team0 T2 inner=row8, team1 T2 inner=row2
					var row_t2: int = _rows_t2[team]
					pos = Vector2i(cols[lane_idx], row_t1 if tier == 1 else row_t2)
				_bs.turrets.append(TurretData.new(team, pos, tier, lane_idx, _bs.TURRET_HP, _bs.TURRET_ATK))


# ─── Win Condition ────────────────────────────────────────────────────────────
func check_win_condition() -> void:
	if _bs.enemy_hq_hp <= 0:
		_bs.game_over = true
		_bs.lbl_victory.text  = "Player Team Wins!"
		_bs._panel_victory.visible = true
	elif _bs.player_hq_hp <= 0:
		_bs.game_over = true
		_bs.lbl_victory.text  = "Opponent Team Wins!"
		_bs._panel_victory.visible = true
