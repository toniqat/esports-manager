class_name SimulationCore
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim

# ─── Hardcoded jungle layout ─────────────────────────────────────────────────
# The map starts with both jungles already captured by their respective teams,
# leaving only two neutral cells (the side-by-side neutral camps) up for grabs.
# Coordinates use the BattleField TileMap's negative-coord system.
const JUNGLE_TEAM0_LEFT  := [Vector2i(-2,  0), Vector2i(-2, -1), Vector2i(-3,  0)]
const JUNGLE_TEAM0_RIGHT := [Vector2i( 0,  0), Vector2i( 0, -1), Vector2i( 1,  0)]
const JUNGLE_TEAM1_LEFT  := [Vector2i(-2, -3), Vector2i(-2, -2), Vector2i(-3, -2)]
const JUNGLE_TEAM1_RIGHT := [Vector2i( 0, -3), Vector2i( 0, -2), Vector2i( 1, -2)]
const NEUTRAL_LEFT  := Vector2i(-3, -1)
const NEUTRAL_RIGHT := Vector2i( 1, -1)

# 취약지점 (vulnerable points) per team per lane. Defined as the jungle cell(s)
# in a team's own territory that sit closest to enemy territory along that lane.
# When the team's same-lane T1 falls, these are what the enemy normally claims
# (subject to the side-neutral and restoration overrides in `_on_t1_destroyed`).
# Side lanes have a single cell; mid has the two flanking cells.
const VULN_TEAM0_LEFT   := [Vector2i(-3,  0)]
const VULN_TEAM0_CENTER := [Vector2i(-2, -1), Vector2i( 0, -1)]
const VULN_TEAM0_RIGHT  := [Vector2i( 1,  0)]
const VULN_TEAM1_LEFT   := [Vector2i(-3, -2)]
const VULN_TEAM1_CENTER := [Vector2i(-2, -2), Vector2i( 0, -2)]
const VULN_TEAM1_RIGHT  := [Vector2i( 1, -2)]


# ─── Main turn (== 1 minute) loop ─────────────────────────────────────────────
func simulate_turn() -> void:
	if _bs.game_over or _bs.game_phase != GameEnums.BattlePhase.BATTLE:
		return
	_bs.turn_count += 1
	process_respawns()

	# Apply pending ATK buffs from card plays this turn (kept from old design).
	var buff_p  := _bs.pending_atk_buff_p
	var buff_ai := _bs.pending_atk_buff_ai
	var buffed_pilots: Array = []
	if buff_p > 0 or buff_ai > 0:
		for raw_p in _bs.pilots:
			var bp := raw_p as PilotData
			if not bp.alive: continue
			if bp.team == 0 and buff_p > 0:
				bp.atk += buff_p; buffed_pilots.append(bp)
			elif bp.team == 1 and buff_ai > 0:
				bp.atk += buff_ai; buffed_pilots.append(bp)

	var log_lines: Array = []
	# 1. Recall (instant teleport) for any pilot under HP threshold.
	_bs.recall_sys.process_recalls(log_lines)

	# 2. Per-cell engagement resolution. Engaged pilots fight; non-engaged are
	#    free to move in step 3.
	var damage_map: Dictionary = {}    # PilotData → int
	var turret_dmg: Dictionary = {}    # TurretData → int
	var advance_set: Dictionary = {}   # PilotData → true
	var retreat_set: Dictionary = {}   # PilotData → true
	var engaged: Dictionary = {}       # PilotData → true (cannot move this turn)

	var by_cell: Dictionary = _group_pilots_by_cell()
	for pos in by_cell.keys():
		var bucket: Dictionary = by_cell[pos] as Dictionary
		var t0: Array = (bucket.get("t0", []) as Array).duplicate()
		var t1: Array = (bucket.get("t1", []) as Array).duplicate()
		_resolve_cell(pos as Vector2i, t0, t1,
				damage_map, turret_dmg, advance_set, retreat_set, engaged, log_lines)

	# 3. Movement for non-engaged, alive pilots. Pilots in the middle of an
	#    advance/retreat from combat will move via step 5 below instead.
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive: continue
		if engaged.has(p): continue
		if advance_set.has(p) or retreat_set.has(p): continue
		_move_pilot(p)

	# 4. Apply combat damage (pilots first, then turrets).
	# 보호막 sits on top of HP — battlefield hits bleed it down before HP, same
	# rule the 공격 card uses. 본진 복귀 (RecallSystem) zeroes the shield.
	for k in damage_map.keys():
		var p := k as PilotData
		var dmg: int = damage_map[k]
		if dmg > 0 and p.shield > 0:
			var absorbed: int = min(p.shield, dmg)
			p.shield -= absorbed
			dmg -= absorbed
		p.hp -= dmg
		if p.hp <= 0:
			p.hp = 0; p.alive = false; p.respawn_timer = _bs.RESPAWN_TURNS
			log_lines.append("%s died" % _bs.pilot_label(p))
		elif damage_map[k] > 0:
			_bs.anim_pilot_shake(p)

	for k in turret_dmg.keys():
		var td := k as TurretData
		var was_alive := td.alive
		td.hp -= turret_dmg[k]
		if td.hp <= 0:
			td.hp = 0; td.alive = false
			log_lines.append("T%d %s turret destroyed!" % [td.tier, _bs.LANE_NAMES[td.lane]])
			if was_alive:
				var b: Building = _bs.building_registry.get_at(td.grid_pos)
				if b != null:
					_bs.building_registry.unregister(b)
					b.queue_free()
			if was_alive and td.tier == 1:
				_on_t1_destroyed(td, log_lines)

	# 5. Resolve push movements (advance / retreat). Skip dead pilots.
	for k in advance_set.keys():
		var p := k as PilotData
		if p.alive: _push_advance(p)
	for k in retreat_set.keys():
		var p := k as PilotData
		if p.alive: _push_retreat(p)

	# 6. HQ damage: any pilot sitting on enemy HQ once any T2 is down.
	var hq_damage_p := 0
	var hq_damage_e := 0
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive: continue
		var defending_team := 1 if p.team == 0 else 0
		var ehq := _bs.ENEMY_HQ_POS if p.team == 0 else _bs.PLAYER_HQ_POS
		if p.grid_pos == ehq and any_t2_destroyed(defending_team):
			if p.team == 0: hq_damage_e += p.atk
			else:           hq_damage_p += p.atk
			log_lines.append("%s→HQ:%d" % [_bs.pilot_label(p), p.atk])
	_bs.enemy_hq_hp  = max(0, _bs.enemy_hq_hp  - hq_damage_e)
	_bs.player_hq_hp = max(0, _bs.player_hq_hp - hq_damage_p)

	# Reset ATK buffs applied this turn
	for raw_p in buffed_pilots:
		var bp := raw_p as PilotData
		if bp.team == 0:    bp.atk -= buff_p
		elif bp.team == 1:  bp.atk -= buff_ai
	_bs.pending_atk_buff_p  = 0
	_bs.pending_atk_buff_ai = 0

	process_neutral_zone_captures()
	process_temp_zone_expiries()
	if not log_lines.is_empty(): _bs.last_log = log_lines[0]
	check_win_condition()
	_bs.renderer.queue_redraw()
	_bs.hud.update_hud()


# ─── Engagement helpers ───────────────────────────────────────────────────────

func _group_pilots_by_cell() -> Dictionary:
	# Returns pos → {"t0": [...], "t1": [...]} for cells with at least one alive pilot.
	var by_cell: Dictionary = {}
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive: continue
		if not by_cell.has(p.grid_pos):
			by_cell[p.grid_pos] = {"t0": [], "t1": []}
		var key := "t0" if p.team == 0 else "t1"
		(by_cell[p.grid_pos][key] as Array).append(p)
	return by_cell


# Resolves combat at a single cell. Mutates the damage/push/engagement maps.
# Lane-scope combat (pilot vs pilot, pilot vs turret) only involves lane pilots
# (non-junglers). Junglers are split off and resolved in their own jungler-vs-
# jungler bracket — they neither attack/defend turrets nor engage lane pilots.
func _resolve_cell(pos: Vector2i, t0: Array, t1: Array,
		damage_map: Dictionary, turret_dmg: Dictionary,
		advance_set: Dictionary, retreat_set: Dictionary,
		engaged: Dictionary, log_lines: Array) -> void:
	var t0_lane: Array = []
	var t0_jung: Array = []
	for raw in t0:
		var p := raw as PilotData
		if p.is_guerrilla: t0_jung.append(p)
		else: t0_lane.append(p)
	var t1_lane: Array = []
	var t1_jung: Array = []
	for raw in t1:
		var p := raw as PilotData
		if p.is_guerrilla: t1_jung.append(p)
		else: t1_lane.append(p)

	var enemy_turret_for_t0: TurretData = _enemy_turret_at(pos, 0)
	var enemy_turret_for_t1: TurretData = _enemy_turret_at(pos, 1)

	# Case A: team-0 lane attackers on team-1 turret cell.
	if enemy_turret_for_t0 != null:
		_resolve_lane_at_turret(t0_lane, t1_lane, enemy_turret_for_t0,
				damage_map, turret_dmg, advance_set, retreat_set, engaged, log_lines)
	# Case B: team-1 lane attackers on team-0 turret cell.
	elif enemy_turret_for_t1 != null:
		_resolve_lane_at_turret(t1_lane, t0_lane, enemy_turret_for_t1,
				damage_map, turret_dmg, advance_set, retreat_set, engaged, log_lines)
	# Case C: pure lane pilot vs lane pilot combat.
	elif not t0_lane.is_empty() and not t1_lane.is_empty():
		_resolve_pilot_combat(t0_lane, t1_lane, damage_map,
				advance_set, retreat_set, engaged, log_lines)

	# Jungler vs jungler runs in parallel with lane-scope combat. Junglers do
	# not engage lane pilots — they only fight other junglers contesting the
	# same cell (typically a neutral camp).
	if not t0_jung.is_empty() and not t1_jung.is_empty():
		_resolve_pilot_combat(t0_jung, t1_jung, damage_map,
				advance_set, retreat_set, engaged, log_lines)


# Splits attackers/defenders by lane match against the turret. Same-lane pilots
# engage in turret combat (only same-lane attackers damage the turret, only
# same-lane defenders defend). Off-lane pilots in the same cell don't interact
# with the turret, but if both teams have off-lane pilots present they still
# fight each other as pilot-vs-pilot (e.g. card-displaced encounters).
func _resolve_lane_at_turret(attackers_lane: Array, defenders_lane: Array, td: TurretData,
		damage_map: Dictionary, turret_dmg: Dictionary,
		advance_set: Dictionary, retreat_set: Dictionary,
		engaged: Dictionary, log_lines: Array) -> void:
	var same_attackers: Array = []
	var off_attackers: Array = []
	for raw in attackers_lane:
		var p := raw as PilotData
		if p.lane == td.lane: same_attackers.append(p)
		else: off_attackers.append(p)
	var same_defenders: Array = []
	var off_defenders: Array = []
	for raw in defenders_lane:
		var p := raw as PilotData
		if p.lane == td.lane: same_defenders.append(p)
		else: off_defenders.append(p)
	if not same_attackers.is_empty():
		_resolve_turret_combat(same_attackers, same_defenders, td,
				damage_map, turret_dmg, retreat_set, engaged, log_lines)
	if not off_attackers.is_empty() and not off_defenders.is_empty():
		_resolve_pilot_combat(off_attackers, off_defenders, damage_map,
				advance_set, retreat_set, engaged, log_lines)


func _resolve_pilot_combat(t0: Array, t1: Array,
		damage_map: Dictionary, advance_set: Dictionary,
		retreat_set: Dictionary, engaged: Dictionary, log_lines: Array) -> void:
	# Sort by HP ascending; pair index-by-index for damage rolls. Leftover
	# pilots beyond the matched count don't take damage this turn.
	# Push, however, is decided at the *team level* across the whole bracket:
	# whichever side lands more unilateral hits sweeps — every pilot of that
	# side in the cell advances, every opponent retreats (including unpaired
	# pilots). Tie or 0-0 → no push.
	t0.sort_custom(func(a: PilotData, b: PilotData) -> bool: return a.hp < b.hp)
	t1.sort_custom(func(a: PilotData, b: PilotData) -> bool: return a.hp < b.hp)
	var pairs := mini(t0.size(), t1.size())
	var t0_uni_wins := 0
	var t1_uni_wins := 0
	for i in pairs:
		var a := t0[i] as PilotData
		var b := t1[i] as PilotData
		engaged[a] = true; engaged[b] = true
		var hit_a := _hit_roll(a, b)
		var hit_b := _hit_roll(b, a)
		if hit_a:
			damage_map[b] = damage_map.get(b, 0) + a.atk
			log_lines.append("%s→%s:%d" % [_bs.pilot_label(a), _bs.pilot_label(b), a.atk])
		if hit_b:
			damage_map[a] = damage_map.get(a, 0) + b.atk
			log_lines.append("%s→%s:%d" % [_bs.pilot_label(b), _bs.pilot_label(a), b.atk])
		if hit_a and not hit_b:
			t0_uni_wins += 1
		elif hit_b and not hit_a:
			t1_uni_wins += 1
	if t0_uni_wins > t1_uni_wins:
		for raw in t0: advance_set[raw as PilotData] = true
		for raw in t1: retreat_set[raw as PilotData] = true
	elif t1_uni_wins > t0_uni_wins:
		for raw in t1: advance_set[raw as PilotData] = true
		for raw in t0: retreat_set[raw as PilotData] = true


func _resolve_turret_combat(attackers: Array, defenders: Array, td: TurretData,
		damage_map: Dictionary, turret_dmg: Dictionary,
		retreat_set: Dictionary, engaged: Dictionary, log_lines: Array) -> void:
	# T2 invulnerable while T1 in same lane is alive.
	var turret_attackable: bool = not (td.tier == 2 and t1_alive_in_lane(td.team, td.lane))

	# Mark all attackers and defenders as engaged (no free movement this turn).
	for raw in attackers: engaged[raw as PilotData] = true
	for raw in defenders: engaged[raw as PilotData] = true

	# Each attacker hits the turret (100% hit) when attackable.
	if turret_attackable:
		for raw in attackers:
			var a := raw as PilotData
			turret_dmg[td] = turret_dmg.get(td, 0) + a.atk
			log_lines.append("%s→T%d[%s]:%d" % [
					_bs.pilot_label(a), td.tier, _bs.LANE_NAMES[td.lane], a.atk])

	# Defenders roll on attackers (lowest-HP pairing). Damage stays per-pair,
	# but retreat is team-wide: ANY successful defender hit forces every
	# attacker in the cell (paired or not) to retreat together.
	if defenders.is_empty():
		return
	var atk_sorted := attackers.duplicate()
	atk_sorted.sort_custom(func(a: PilotData, b: PilotData) -> bool: return a.hp < b.hp)
	var def_sorted := defenders.duplicate()
	def_sorted.sort_custom(func(a: PilotData, b: PilotData) -> bool: return a.hp < b.hp)
	var pairs := mini(atk_sorted.size(), def_sorted.size())
	var any_def_hit := false
	for i in pairs:
		var a := atk_sorted[i] as PilotData
		var d := def_sorted[i] as PilotData
		if _hit_roll(d, a):
			damage_map[a] = damage_map.get(a, 0) + d.atk
			any_def_hit = true
			log_lines.append("%s→%s:%d (defender)" % [
					_bs.pilot_label(d), _bs.pilot_label(a), d.atk])
	if any_def_hit:
		for raw in attackers:
			retreat_set[raw as PilotData] = true


# Hit chance = attacker.hit / (attacker.hit + defender.evasion). Pure roll.
func _hit_roll(attacker: PilotData, defender: PilotData) -> bool:
	var num := float(attacker.hit)
	var den := float(attacker.hit + defender.evasion)
	if den <= 0.0: return false
	return randf() < (num / den)


func _enemy_turret_at(pos: Vector2i, friendly_team: int) -> TurretData:
	for t in _bs.turrets:
		var td := t as TurretData
		if td.alive and td.team != friendly_team and td.grid_pos == pos:
			return td
	return null


# ─── Movement (non-engaged & push) ───────────────────────────────────────────

func _move_pilot(p: PilotData) -> void:
	var orig := p.grid_pos
	var steps: int = maxi(1, p.move_range)
	for _i in steps:
		# Stop further stepping once an *engaging* enemy occupies our current
		# cell — combat resolves next turn via same-cell engagement. Junglers
		# and lane pilots ignore each other (they never engage), so a jungler
		# crossing through a lane cell will not freeze on a lane enemy.
		if _has_engaging_enemy_at(p.grid_pos, p):
			break
		# Lane pilots cannot move past an alive enemy turret cell — they must
		# destroy it first. Junglers don't interact with turrets so they pass
		# freely.
		if not p.is_guerrilla and _enemy_turret_at(p.grid_pos, p.team) != null:
			break
		var prev := p.grid_pos
		_step_pilot_once(p)
		if p.grid_pos == prev:
			break
	if p.grid_pos != orig:
		_bs.anim_pilot_move(p, orig)


# True only if the cell contains an enemy that would actually engage `p`.
# Junglers and lane pilots ignore each other (matches `_resolve_cell` rules).
func _has_engaging_enemy_at(cell: Vector2i, p: PilotData) -> bool:
	for raw in _bs.pilots:
		var o := raw as PilotData
		if not o.alive: continue
		if o.team == p.team: continue
		if o.grid_pos != cell: continue
		if o.is_guerrilla != p.is_guerrilla: continue
		return true
	return false


func _step_pilot_once(p: PilotData) -> void:
	var goal: Vector2i
	if p.is_guerrilla:
		goal = _jungle_goal_for(p)
		if goal == Vector2i(-1, -1):
			return
	elif p.role == GameEnums.Role.SUPPORT and _supporter_should_fall_back(p):
		# Same-lane sniper is dead or has recalled to HQ → hug own forward turret.
		var hug: Vector2i = _own_forward_turret_cell(p)
		goal = hug if hug != Vector2i(-1, -1) else current_waypoint(p)
	else:
		goal = current_waypoint(p)
	var fbd: Dictionary = _movement_forbidden_for(p)
	var next: Vector2i = _bs.pathfinder.bfs_next_step(p.grid_pos, goal, fbd)
	if next != p.grid_pos:
		p.grid_pos = next


# Goal selection for jungler: nearest uncaptured neutral, else a random
# own-captured tile to roam.
func _jungle_goal_for(p: PilotData) -> Vector2i:
	var nearest_neutral := _nearest_uncaptured_neutral(p)
	if nearest_neutral != Vector2i(-1, -1):
		return nearest_neutral
	# Roam: pick the captured tile with the largest distance from current pos
	# so the jungler doesn't sit still.
	var captured := _own_captured_jungle_cells(p.team)
	if captured.is_empty():
		return _bs.PLAYER_HQ_POS if p.team == 0 else _bs.ENEMY_HQ_POS
	var best := captured[0] as Vector2i
	var best_d := _bs.hex_grid.hex_distance(p.grid_pos, best)
	for c in captured:
		var d: int = _bs.hex_grid.hex_distance(p.grid_pos, c as Vector2i)
		if d > best_d:
			best_d = d; best = c
	return best


func _push_advance(p: PilotData) -> void:
	var orig := p.grid_pos
	var fbd: Dictionary = _movement_forbidden_for(p)
	if p.is_guerrilla:
		var jg_goal := _jungle_goal_for(p)
		if jg_goal == Vector2i(-1, -1): return
		var jg_next: Vector2i = _bs.pathfinder.bfs_next_step(p.grid_pos, jg_goal, fbd)
		if jg_next != p.grid_pos: p.grid_pos = jg_next
		if p.grid_pos != orig:
			_bs.anim_pilot_move(p, orig)
		return
	# Lane pilots cannot push past an alive enemy turret cell.
	if _enemy_turret_at(p.grid_pos, p.team) != null:
		return
	var goal := current_waypoint(p)
	var next: Vector2i = _bs.pathfinder.bfs_next_step(p.grid_pos, goal, fbd)
	if next != p.grid_pos:
		p.grid_pos = next
	if p.grid_pos != orig:
		_bs.anim_pilot_move(p, orig)


func _push_retreat(p: PilotData) -> void:
	var orig := p.grid_pos
	var fbd: Dictionary = _movement_forbidden_for(p)
	if p.is_guerrilla:
		# Retreat toward nearest own-captured jungle cell.
		var captured := _own_captured_jungle_cells(p.team)
		var dest := Vector2i(-1, -1)
		var best_d := 999999
		for c in captured:
			if c == p.grid_pos: continue
			var d: int = _bs.hex_grid.hex_distance(p.grid_pos, c as Vector2i)
			if d < best_d:
				best_d = d; dest = c
		if dest == Vector2i(-1, -1):
			dest = _bs.PLAYER_HQ_POS if p.team == 0 else _bs.ENEMY_HQ_POS
		var jg_nxt: Vector2i = _bs.pathfinder.bfs_next_step(p.grid_pos, dest, fbd)
		if jg_nxt != p.grid_pos: p.grid_pos = jg_nxt
		if p.grid_pos != orig:
			_bs.anim_pilot_move(p, orig)
		return
	# Lane pilots retreat one step along their lane toward own HQ.
	var home := _bs.PLAYER_HQ_POS if p.team == 0 else _bs.ENEMY_HQ_POS
	var nxt: Vector2i = _bs.pathfinder.bfs_next_step(p.grid_pos, home, fbd)
	if nxt != p.grid_pos:
		p.grid_pos = nxt
	# Roll the waypoint index back if the retreat crossed an earlier waypoint.
	var path: Array = _bs.LANE_PATHS_TEAM0[p.lane] if p.team == 0 else _bs.LANE_PATHS_TEAM1[p.lane]
	while p.waypoint_idx > 0:
		var wp := path[p.waypoint_idx] as Vector2i
		if _bs.hex_grid.hex_distance(p.grid_pos, wp) > _bs.hex_grid.hex_distance(p.grid_pos, path[p.waypoint_idx - 1] as Vector2i):
			p.waypoint_idx -= 1
		else:
			break
	if p.grid_pos != orig:
		_bs.anim_pilot_move(p, orig)


# ─── Card-driven single-pilot lane push (전진) ───────────────────────────────
# Triggered by the 전진 (advance:N) card. Runs `steps` mini-ticks for `caster`
# only — at each step, resolves combat at the caster's current cell using the
# normal lane push rules (pilot vs pilot, same-lane turret attack/defend),
# applies damage, then either pushes the caster (if their team won/lost the
# cell) or steps them one cell along their lane (if uncontested). Other pilots
# in the same cell take damage from the engagement but do not move — only the
# caster's position is advanced/retreated, since the card is a single-pilot
# action rather than a full battle tick.
func advance_pilot(caster: PilotData, steps: int, log_lines: Array) -> void:
	if caster == null or steps <= 0:
		return
	for _i in steps:
		if not caster.alive:
			break
		var damage_map: Dictionary = {}
		var turret_dmg: Dictionary = {}
		var advance_set: Dictionary = {}
		var retreat_set: Dictionary = {}
		var engaged: Dictionary = {}
		var by_cell: Dictionary = _group_pilots_by_cell()
		var bucket: Dictionary = by_cell.get(caster.grid_pos, {"t0": [], "t1": []})
		var t0: Array = (bucket.get("t0", []) as Array).duplicate()
		var t1: Array = (bucket.get("t1", []) as Array).duplicate()
		_resolve_cell(caster.grid_pos, t0, t1,
				damage_map, turret_dmg, advance_set, retreat_set, engaged, log_lines)
		# Apply pilot damage (보호막 first, then HP). Mirrors simulate_turn.
		for k in damage_map.keys():
			var dp := k as PilotData
			var dmg: int = damage_map[k]
			if dmg > 0 and dp.shield > 0:
				var absorbed: int = min(dp.shield, dmg)
				dp.shield -= absorbed
				dmg -= absorbed
			dp.hp -= dmg
			if dp.hp <= 0:
				dp.hp = 0; dp.alive = false; dp.respawn_timer = _bs.RESPAWN_TURNS
				log_lines.append("%s died" % _bs.pilot_label(dp))
			elif damage_map[k] > 0:
				_bs.anim_pilot_shake(dp)
		# Apply turret damage; on T1 destruction, fire jungle capture.
		for k in turret_dmg.keys():
			var td := k as TurretData
			var was_alive := td.alive
			td.hp -= turret_dmg[k]
			if td.hp <= 0:
				td.hp = 0; td.alive = false
				log_lines.append("T%d %s turret destroyed!" % [td.tier, _bs.LANE_NAMES[td.lane]])
				if was_alive:
					var b: Building = _bs.building_registry.get_at(td.grid_pos)
					if b != null:
						_bs.building_registry.unregister(b)
						b.queue_free()
				if was_alive and td.tier == 1:
					_on_t1_destroyed(td, log_lines)
		if not caster.alive:
			break
		# Move only the caster — push results from the cell apply to them, but
		# teammates / opposing pilots in the cell stay put (the card moves one
		# pilot, not the whole bracket).
		if advance_set.has(caster):
			_push_advance(caster)
		elif retreat_set.has(caster):
			_push_retreat(caster)
		elif not engaged.has(caster):
			var orig := caster.grid_pos
			_step_pilot_once(caster)
			if caster.grid_pos != orig:
				_bs.anim_pilot_move(caster, orig)
	check_win_condition()
	_bs.renderer.queue_redraw()
	_bs.hud.update_hud()


# ─── Targeting / waypoint helpers (used by movement) ─────────────────────────

func current_waypoint(pilot: PilotData) -> Vector2i:
	var path: Array = _bs.LANE_PATHS_TEAM0[pilot.lane] if pilot.team == 0 \
			else _bs.LANE_PATHS_TEAM1[pilot.lane]
	while pilot.waypoint_idx < path.size() - 1:
		var wp: Vector2i = path[pilot.waypoint_idx] as Vector2i
		if pilot.grid_pos == wp:
			pilot.waypoint_idx += 1
		else:
			break
	return path[min(pilot.waypoint_idx, path.size() - 1)] as Vector2i


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


func has_enemy_turret_at(pos: Vector2i, pilot_team: int) -> bool:
	return _enemy_turret_at(pos, pilot_team) != null


# ─── Respawn ─────────────────────────────────────────────────────────────────

func process_respawns() -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive:
			p.respawn_timer -= 1
			if p.respawn_timer <= 0:
				p.grid_pos     = _bs.PLAYER_HQ_POS if p.team == 0 else _bs.ENEMY_HQ_POS
				p.hp           = p.max_hp
				p.shield       = 0   # 본진 복귀 = 보호막 제거
				p.alive        = true
				p.waypoint_idx = 0
				_bs.anim_pilot_respawn(p)


# ─── Neutral zones / jungle ──────────────────────────────────────────────────

# Builds neutral_zone_cells with the user-defined initial state:
#  - Both teams' jungles already captured for their team.
#  - Two side neutral cells uncaptured.
func init_neutral_zones() -> void:
	_bs.neutral_zone_cells.clear()
	for c in JUNGLE_TEAM0_LEFT:  _set_zone_cell(c as Vector2i, 0)
	for c in JUNGLE_TEAM0_RIGHT: _set_zone_cell(c as Vector2i, 0)
	for c in JUNGLE_TEAM1_LEFT:  _set_zone_cell(c as Vector2i, 1)
	for c in JUNGLE_TEAM1_RIGHT: _set_zone_cell(c as Vector2i, 1)
	_set_zone_cell(NEUTRAL_LEFT,  -1)
	_set_zone_cell(NEUTRAL_RIGHT, -1)


func _set_zone_cell(cell: Vector2i, owner_id: int) -> void:
	_bs.neutral_zone_cells[cell] = owner_id
	# atlas (3,0) = neutral-gray, (1,0) = team-0 colour, (2,0) = team-1 colour
	var atlas: Vector2i
	if owner_id == 0:    atlas = Vector2i(1, 0)
	elif owner_id == 1:  atlas = Vector2i(2, 0)
	else:                atlas = Vector2i(3, 0)
	_bs.tiles_layer.set_cell(cell, 0, atlas, 0)


# Public wrapper for outside callers (e.g. CardPhaseManager._effect_capture_jungle).
func set_zone_cell(cell: Vector2i, owner_id: int) -> void:
	_set_zone_cell(cell, owner_id)


# Restore expired 약탈 captures. Called from simulate_turn after the
# capture-by-jungler step so naturally-captured cells aren't immediately
# overwritten by an expiring temp.
func process_temp_zone_expiries() -> void:
	if _bs.temp_zone_overrides.is_empty():
		return
	var keep: Array = []
	for raw in _bs.temp_zone_overrides:
		var entry: Dictionary = raw as Dictionary
		if _bs.turn_count >= int(entry["expires_turn"]):
			_set_zone_cell(entry["cell"] as Vector2i, int(entry["prev_owner"]))
		else:
			keep.append(entry)
	_bs.temp_zone_overrides = keep


func process_neutral_zone_captures() -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive or not p.is_guerrilla:
			continue
		# Only capture neutral cells (uncaptured) — jungle owned by an enemy
		# team can be retaken only via T1 destruction, not by stepping on it.
		var zone_owner: int = _bs.neutral_zone_cells.get(p.grid_pos, -2)
		if zone_owner != -1:
			continue
		# Block capture if any enemy is on the same cell.
		var enemy_present := false
		for other_raw in _bs.pilots:
			var o := other_raw as PilotData
			if o.alive and o.team != p.team and o.grid_pos == p.grid_pos:
				enemy_present = true; break
		if enemy_present: continue
		_set_zone_cell(p.grid_pos, p.team)


# Used by RecallSystem to decide if a card-displaced jungler is in enemy territory.
func _own_captured_jungle_cells(team: int) -> Array:
	var result: Array = []
	for k in _bs.neutral_zone_cells.keys():
		if int(_bs.neutral_zone_cells[k]) == team:
			result.append(k)
	return result


# Pathfinding "forbidden" set per pilot:
#  - Junglers move freely (no forbidden cells).
#  - Lane pilots are blocked from entering jungle/neutral cells AND alive enemy
#    turret cells in lanes other than their own. The same-lane enemy turret cell
#    is intentionally NOT forbidden so a lane pilot can engage their own turret;
#    the "cannot pass past alive enemy turret" rule in `_move_pilot` then keeps
#    them stationary on that cell until the turret falls. Off-lane enemy turrets
#    used to stop lane pilots dead (e.g. right-lane pilots routing toward enemy
#    HQ would freeze on the still-alive center T2 cell), so we route around them.
# A fresh dictionary is built — never mutate `_bs.neutral_zone_cells`.
func _movement_forbidden_for(p: PilotData) -> Dictionary:
	if p.is_guerrilla:
		return {}
	var fbd: Dictionary = _bs.neutral_zone_cells.duplicate()
	for t in _bs.turrets:
		var td := t as TurretData
		if not td.alive: continue
		if td.team == p.team: continue
		if td.lane == p.lane: continue
		fbd[td.grid_pos] = true
	return fbd


# Forward-most alive own-team turret cell in the pilot's lane. Tier-1 (closer to
# enemy) is preferred; falls back to tier-2; returns (-1,-1) when both are down.
func _own_forward_turret_cell(p: PilotData) -> Vector2i:
	var tier1: TurretData = null
	var tier2: TurretData = null
	for t in _bs.turrets:
		var td := t as TurretData
		if td.team != p.team: continue
		if td.lane != p.lane: continue
		if not td.alive: continue
		if td.tier == 1: tier1 = td
		elif td.tier == 2: tier2 = td
	if tier1 != null: return tier1.grid_pos
	if tier2 != null: return tier2.grid_pos
	return Vector2i(-1, -1)


# A SUPPORT pilot falls back defensively when their same-lane SNIPER teammate is
# either dead (respawning) or has recalled to own HQ. Without the harassment
# pressure of the sniper, the supporter retreats to their forward turret instead
# of pushing alone.
func _supporter_should_fall_back(p: PilotData) -> bool:
	if p.role != GameEnums.Role.SUPPORT:
		return false
	var sniper: PilotData = null
	for raw in _bs.pilots:
		var o := raw as PilotData
		if o == p: continue
		if o.team != p.team: continue
		if o.role != GameEnums.Role.SNIPER: continue
		if o.lane != p.lane: continue
		sniper = o; break
	if sniper == null:
		return false
	if not sniper.alive:
		return true
	var own_hq: Vector2i = _bs.PLAYER_HQ_POS if sniper.team == 0 else _bs.ENEMY_HQ_POS
	return sniper.grid_pos == own_hq


func _nearest_uncaptured_neutral(p: PilotData) -> Vector2i:
	var jungle_dir := p.jungle_start_pref
	var primary := Vector2i(-1, -1)
	var secondary := Vector2i(-1, -1)
	if jungle_dir == GameEnums.JungleStartDir.LEFT:
		primary  = NEUTRAL_LEFT
		secondary = NEUTRAL_RIGHT
	elif jungle_dir == GameEnums.JungleStartDir.RIGHT:
		primary  = NEUTRAL_RIGHT
		secondary = NEUTRAL_LEFT
	else:
		primary  = NEUTRAL_LEFT
		secondary = NEUTRAL_RIGHT
	if int(_bs.neutral_zone_cells.get(primary, 0)) == -1:
		return primary
	if int(_bs.neutral_zone_cells.get(secondary, 0)) == -1:
		return secondary
	return Vector2i(-1, -1)


# ─── T1 destruction → jungle capture ─────────────────────────────────────────

func _on_t1_destroyed(td: TurretData, log_lines: Array) -> void:
	# `td.team` = the destroyed turret's owner (the loser). `capturer` = the team
	# that took it down. Three branches in priority order:
	#   1. Restoration: if any of the capturer's own same-lane vuln cells are
	#      currently owned by the loser, restore those cells to the capturer
	#      INSTEAD of capturing the loser's vuln. (Applies to all lanes.)
	#   2. Side neutral override (LEFT/RIGHT only): if the same-side neutral is
	#      owned by the loser, the capturer takes the neutral instead of the
	#      loser's vuln cell.
	#   3. Default capture: the loser's same-lane vuln cell(s) flip to the
	#      capturer. Side lanes flip 1 cell, mid flips both flanking cells.
	var capturer := 1 - td.team
	var own_vulns: Array  = _vuln_cells_for(capturer, td.lane)
	var loser_vulns: Array = _vuln_cells_for(td.team, td.lane)

	var to_restore: Array = []
	for c in own_vulns:
		if int(_bs.neutral_zone_cells.get(c as Vector2i, -2)) == td.team:
			to_restore.append(c)
	if not to_restore.is_empty():
		for c in to_restore:
			_set_zone_cell(c as Vector2i, capturer)
		log_lines.append("%s vuln restored by team %d" % [_bs.LANE_NAMES[td.lane], capturer])
		return

	if td.lane == GameEnums.Lane.LEFT or td.lane == GameEnums.Lane.RIGHT:
		var side_neutral: Vector2i = NEUTRAL_LEFT if td.lane == GameEnums.Lane.LEFT else NEUTRAL_RIGHT
		if int(_bs.neutral_zone_cells.get(side_neutral, -2)) == td.team:
			_set_zone_cell(side_neutral, capturer)
			log_lines.append("%s side-neutral captured by team %d" % [_bs.LANE_NAMES[td.lane], capturer])
			return
		for c in loser_vulns:
			_set_zone_cell(c as Vector2i, capturer)
		log_lines.append("%s vuln captured by team %d" % [_bs.LANE_NAMES[td.lane], capturer])
	else:
		for c in loser_vulns:
			_set_zone_cell(c as Vector2i, capturer)
		log_lines.append("Center vulns captured by team %d" % capturer)


func _vuln_cells_for(team: int, lane: int) -> Array:
	if team == 0:
		match lane:
			GameEnums.Lane.LEFT:   return VULN_TEAM0_LEFT
			GameEnums.Lane.CENTER: return VULN_TEAM0_CENTER
			GameEnums.Lane.RIGHT:  return VULN_TEAM0_RIGHT
	else:
		match lane:
			GameEnums.Lane.LEFT:   return VULN_TEAM1_LEFT
			GameEnums.Lane.CENTER: return VULN_TEAM1_CENTER
			GameEnums.Lane.RIGHT:  return VULN_TEAM1_RIGHT
	return []


# ─── Spawning ────────────────────────────────────────────────────────────────

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
		var lid: int = _bs.gambit_lanes[i]
		var stats: Dictionary = _stats_for(ctx_active, p_roster, i, roles[i])
		var pilot := PilotData.new(roles[i], 0, _bs.PLAYER_HQ_POS, stats)
		pilot.pilot_id     = _pilot_id_from_roster(ctx_active, p_roster, i, i)
		pilot.lane         = lid
		pilot.is_guerrilla = (lid == GameEnums.LanePosition.GUERRILLA)
		pilot.waypoint_idx = 0
		if pilot.is_guerrilla:
			pilot.jungle_start_pref = jungle_dir
		_bs.pilots.append(pilot)

	var e_lanes: Array = GambitPhaseManager.ROLE_TO_LANE
	for i in range(5):
		var lid: int = e_lanes[i]
		var stats: Dictionary = _stats_for(ctx_active, e_roster, i, roles[i])
		var pilot := PilotData.new(roles[i], 1, _bs.ENEMY_HQ_POS, stats)
		pilot.pilot_id     = _pilot_id_from_roster(ctx_active, e_roster, i, 5 + i)
		pilot.lane         = lid
		pilot.is_guerrilla = (lid == GameEnums.LanePosition.GUERRILLA)
		pilot.waypoint_idx = 0
		if pilot.is_guerrilla:
			pilot.jungle_start_pref = randi() % 2
		_bs.pilots.append(pilot)


# Returns the id used for portrait lookup. When the roster carries a regular
# PlayerData (id 0..39) we use it directly. Otherwise (standalone runs with
# no roster, or INTL pilots whose ids are 100+ and have no image assets),
# we fall back to a deterministic per-slot id so PilotImages can still
# resolve a sprite — keeping pilot art visible across every entry path.
func _pilot_id_from_roster(ctx_active: bool, roster: Array, idx: int,
		fallback_id: int) -> int:
	if ctx_active and idx < roster.size():
		var pd := roster[idx] as PlayerData
		if pd != null and pd.id >= 0 and pd.id < PilotImages.POOL_SIZE:
			return pd.id
	return fallback_id


# Returns a stats dict {hp, atk, hit, evasion, presence}.
# hp/atk/presence come from the assigned mech (or ROLE_STATS fallback).
# hit/evasion come from PlayerData (mechanics → hit, gamesense → evasion).
# presence drives 전투 개시(engage) attack order and target weighting only.
# Fallback presence: melee roles (TANK/FIGHTER/ASSASSIN) → 4, ranged
# (SUPPORT/SNIPER) → 2, matching the mech CSV convention.
func _stats_for(ctx_active: bool, roster: Array, idx: int, role_id: int) -> Dictionary:
	if ctx_active and idx < roster.size():
		var pd := roster[idx] as PlayerData
		var m: MechData = pd.assigned_mech
		if m != null:
			return {
				"hp": m.hp, "atk": m.atk,
				"hit": pd.mechanics, "evasion": pd.gamesense,
				"presence": m.presence,
			}
	var base: Dictionary = _bs.ROLE_STATS[role_id]
	var fallback_presence: int = 4 if role_id <= GameEnums.Role.ASSASSIN else 2
	return {
		"hp": base["hp"], "atk": base["atk"],
		"hit": 50, "evasion": 50,
		"presence": fallback_presence,
	}


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
					var cols := [1, 4, 7]
					var _rows_t1: Array = [6, 4]
					var row_t1: int = _rows_t1[team]
					var _rows_t2: Array = [8, 2]
					var row_t2: int = _rows_t2[team]
					pos = Vector2i(cols[lane_idx], row_t1 if tier == 1 else row_t2)
				_bs.turrets.append(TurretData.new(team, pos, tier, lane_idx, _bs.TURRET_HP, _bs.TURRET_ATK))


# ─── Win Condition ────────────────────────────────────────────────────────────

func check_win_condition() -> void:
	if _bs.enemy_hq_hp <= 0:
		_bs.game_over = true
		_bs.lbl_victory.text       = "Player Team Wins!"
		_bs.panel_victory.visible = true
		_record_season_winner(0)
	elif _bs.player_hq_hp <= 0:
		_bs.game_over = true
		_bs.lbl_victory.text       = "Opponent Team Wins!"
		_bs.panel_victory.visible = true
		_record_season_winner(1)


# When BattleSim was launched from a Season campaign, write the winning side
# back into season_state.pending_match so SeasonHub can pick it up after the
# scene change. Standalone runs (no pending_match) are a no-op.
func _record_season_winner(winner_side: int) -> void:
	var pm = _bs.gm.season_state.get("pending_match", null)
	if pm == null:
		return
	pm["winner_side"] = winner_side
