class_name BattleRenderer
extends Node2D

@onready var _bs: BattleSim = get_parent() as BattleSim


func _draw() -> void:
	if _bs.game_phase == GameEnums.BattlePhase.GAMBIT:
		return
	_draw_lane_lines()
	_draw_hq_hp_bars()
	_draw_turret_hp_bars()
	_draw_minions()

	# Build per-cell occupancy split by team
	var cell_team0: Dictionary = {}
	var cell_team1: Dictionary = {}
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive:
			continue
		if p.team == 0:
			if not cell_team0.has(p.grid_pos):
				cell_team0[p.grid_pos] = []
			(cell_team0[p.grid_pos] as Array).append(p)
		else:
			if not cell_team1.has(p.grid_pos):
				cell_team1[p.grid_pos] = []
			(cell_team1[p.grid_pos] as Array).append(p)

	var all_cells: Dictionary = {}
	for pos in cell_team0.keys(): all_cells[pos] = true
	for pos in cell_team1.keys(): all_cells[pos] = true

	for pos in all_cells.keys():
		var pv := pos as Vector2i
		var t0: Array = cell_team0.get(pv, []) as Array
		var t1: Array = cell_team1.get(pv, []) as Array
		var has_combat := not t0.is_empty() and not t1.is_empty()
		var siege_t0   := not has_combat and not t0.is_empty() and _bs.sim_core.has_enemy_turret_at(pv, 0)
		var siege_t1   := not has_combat and not t1.is_empty() and _bs.sim_core.has_enemy_turret_at(pv, 1)
		for i in range(t1.size()):
			_draw_pilot_zoned(t1[i] as PilotData, i, t1.size(), has_combat, true, siege_t1)
		for i in range(t0.size()):
			_draw_pilot_zoned(t0[i] as PilotData, i, t0.size(), has_combat, false, siege_t0)
		var total := t0.size() + t1.size()
		if total > 1:
			_draw_cell_badge_new(pv, t0.size(), t1.size())


func _draw_lane_lines() -> void:
	var bg_col := Color(1.0, 1.0, 1.0, 0.12)
	for lane in range(3):
		var path: Array = _bs.LANE_PATHS_TEAM0[lane]
		if path.size() < 2:
			continue
		var pts := PackedVector2Array()
		for wp in path:
			pts.append(_bs.cell_center(wp as Vector2i))
		draw_polyline(pts, bg_col, 2.0)

	var ally_col  := Color(0.2, 0.5, 0.9,  1.0)
	var enemy_col := Color(0.9, 0.25, 0.25, 1.0)
	for lane in range(3):
		for team in range(2):
			var best = _bs.minion_sys.furthest_minion_in_lane(lane, team)
			if best == null:
				continue
			var m := best as MinionData
			if m.waypoint_idx == 0:
				continue
			var path: Array = _bs.LANE_PATHS_TEAM0[lane] if team == 0 else _bs.LANE_PATHS_TEAM1[lane]
			var pts := PackedVector2Array()
			for wi in range(m.waypoint_idx):
				pts.append(_bs.cell_center(path[wi] as Vector2i))
			pts.append(_bs.cell_center(m.grid_pos))
			if pts.size() >= 2:
				draw_polyline(pts, ally_col if team == 0 else enemy_col, 6.0)


func _draw_hq_hp_bars() -> void:
	var enemy_locked  := not _bs.sim_core.any_t2_destroyed(1)
	var player_locked := not _bs.sim_core.any_t2_destroyed(0)
	if not player_locked:
		_draw_hq_hp_bar(_bs.PLAYER_HQ_POS, _bs.player_hq_hp)
	if not enemy_locked:
		_draw_hq_hp_bar(_bs.ENEMY_HQ_POS, _bs.enemy_hq_hp)


func _draw_hq_hp_bar(pos: Vector2i, hp: int) -> void:
	var center := _bs.cell_center(pos)
	var bw := 60.0; var bh := 8.0
	var bx := center.x - bw * 0.5; var by_ := center.y + 16.0
	draw_rect(Rect2(bx, by_, bw, bh), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(bx, by_, bw * float(hp) / float(_bs.HQ_MAX_HP), bh), Color(0.2, 0.9, 0.2))


func _draw_turret_hp_bars() -> void:
	for t in _bs.turrets:
		_draw_turret_hp_bar(t as TurretData)


func _draw_turret_hp_bar(td: TurretData) -> void:
	if not td.alive:
		return
	if td.tier == 2 and _bs.sim_core.t1_alive_in_lane(td.team, td.lane):
		return
	var center := _bs.cell_center(td.grid_pos)
	var hg: HexGrid = _bs._hex_grid
	var bw: float = hg.hex_size * 1.1; var bh := 6.0
	var bx: float = center.x - bw * 0.5; var by_: float = center.y - hg.hex_height * 0.38
	draw_rect(Rect2(bx, by_, bw, bh), Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(bx, by_, bw * float(td.hp) / float(td.max_hp), bh),
			Color(0.92, 0.68, 0.1))


func _draw_minions() -> void:
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
	var all_m_cells: Dictionary = {}
	for pos in cell_m0.keys(): all_m_cells[pos] = true
	for pos in cell_m1.keys(): all_m_cells[pos] = true
	for pos in all_m_cells.keys():
		var pv    := pos as Vector2i
		var has_m0 := cell_m0.has(pv)
		var has_m1 := cell_m1.has(pv)
		if has_m0 and has_m1:
			_draw_minion_combat(pv, (cell_m0[pv] as MinionData).count, (cell_m1[pv] as MinionData).count)
		elif has_m0:
			_draw_minion_solo(cell_m0[pv] as MinionData)
		else:
			_draw_minion_solo(cell_m1[pv] as MinionData)


func _draw_minion_solo(m: MinionData) -> void:
	var center := _bs.cell_center(m.grid_pos)
	var txt    := str(m.count)
	var font   := ThemeDB.fallback_font
	var tsz    := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	var bg_w   := tsz.x + 8.0
	var bg_h   := 18.0
	var bg_col := Color(0.1, 0.72, 0.35, 0.75) if m.team == 0 else Color(0.88, 0.52, 0.1, 0.75)
	var bg_pos := center - Vector2(bg_w * 0.5, bg_h * 0.5)
	draw_rect(Rect2(bg_pos, Vector2(bg_w, bg_h)), bg_col)
	draw_string(font, bg_pos + Vector2(4.0, 14.0), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)


func _draw_minion_combat(pos: Vector2i, count0: int, count1: int) -> void:
	var center    := _bs.cell_center(pos)
	var ally_pos  := Vector2(center.x - 44.0, center.y - 9.0)
	draw_rect(Rect2(ally_pos, Vector2(28.0, 18.0)), Color(0.1, 0.72, 0.35, 0.92))
	draw_string(ThemeDB.fallback_font, ally_pos + Vector2(2.0, 14.0), str(count0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
	var enemy_pos := Vector2(center.x + 16.0, center.y - 9.0)
	draw_rect(Rect2(enemy_pos, Vector2(28.0, 18.0)), Color(0.88, 0.52, 0.1, 0.92))
	draw_string(ThemeDB.fallback_font, enemy_pos + Vector2(2.0, 14.0), str(count1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
	var mbg := Vector2(center.x - 10.0, center.y - 9.0)
	draw_rect(Rect2(mbg, Vector2(20.0, 18.0)), Color(0.7, 0.1, 0.7, 0.9))
	draw_string(ThemeDB.fallback_font, mbg + Vector2(2.0, 14.0), "M",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)


func _zone_x_positions(count: int, cx: float) -> Array:
	match count:
		1: return [cx]
		2: return [cx - 24.0, cx + 24.0]
		_: return [cx - 28.0, cx, cx + 28.0]


func _draw_pilot_zoned(pilot: PilotData, team_idx: int, team_total: int,
		has_combat: bool, is_top: bool, is_siege: bool) -> void:
	var center_cell := _bs.cell_center(pilot.grid_pos)
	var cell_cx     := center_cell.x
	var center:  Vector2
	var radius:  float
	var fsize:   int
	var show_hp: bool = false

	if has_combat or is_siege:
		if team_idx >= 3:
			return
		var zone_y: float = center_cell.y + (-20.0 if is_top else 20.0)
		radius = 16.0 if has_combat else 14.0
		fsize  = 11
		var vis := mini(team_total, 3)
		var xs: Array = _zone_x_positions(vis, cell_cx)
		var xi: int   = mini(team_idx, vis - 1)
		center = Vector2(float(xs[xi]), zone_y)
		if team_total > 3 and team_idx == 2:
			var overflow  := team_total - 2
			var txt       := "+%d" % overflow
			var color_ov  := Color(0.2, 0.5, 0.9) if pilot.team == 0 else Color(0.9, 0.2, 0.2)
			draw_circle(center, radius, color_ov.darkened(0.3))
			draw_arc(center, radius, 0.0, TAU, 20, color_ov.lightened(0.3), 1.5)
			var tsz_ov := ThemeDB.fallback_font.get_string_size(txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
			draw_string(ThemeDB.fallback_font, center - tsz_ov * 0.5 + Vector2(0.0, 5.0),
					txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
			return
	else:
		var base := center_cell
		radius  = 35.0
		fsize   = 18
		show_hp = team_total == 1
		if team_total > 1:
			radius = 22.0 if team_total <= 2 else 16.0
			fsize  = 14   if team_total <= 2 else 11
			var cols: int = mini(team_total, 3)
			var rows: int = int(ceil(float(team_total) / float(cols)))
			var ci:   int = team_idx % cols
			@warning_ignore("integer_division")
			var ri:   int = team_idx / cols
			var margin := 46.0 - radius
			var spc_x  := margin * 2.0 / float(cols - 1) if cols > 1 else 0.0
			var spc_y  := margin * 2.0 / float(rows - 1) if rows > 1 else 0.0
			center = base + Vector2(
					(float(ci) - float(cols - 1) * 0.5) * spc_x,
					(float(ri) - float(rows - 1) * 0.5) * spc_y)
		else:
			center = base

	var color := Color(0.2, 0.5, 0.9) if pilot.team == 0 else Color(0.9, 0.2, 0.2)
	draw_circle(center, radius, color)
	draw_arc(center, radius, 0.0, TAU, 32, color.lightened(0.4), 2.0)
	var ring_r: float = radius + (6.0 if (has_combat or is_siege) else 9.0)
	if pilot.is_guerrilla:
		for i in range(10):
			var a0: float = float(i) / 10.0 * TAU
			draw_arc(center, ring_r, a0, a0 + TAU * 0.055, 5, color.lightened(0.55), 2.5)
	if pilot.recall_state != GameEnums.RecallState.NONE:
		var pulse_alpha: float = 0.55 + 0.35 * absf(sin(_bs._recall_pulse_t * PI * 2.0))
		var amber := Color(1.0, 0.62, 0.0, pulse_alpha)
		draw_arc(center, ring_r, 0.0, TAU, 32, amber, 2.5)
		if pilot.recall_state == GameEnums.RecallState.CHANNELING:
			var ctxt := str(pilot.channel_timer)
			var csz  := ThemeDB.fallback_font.get_string_size(ctxt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
			draw_string(ThemeDB.fallback_font,
					center - csz * 0.5 + Vector2(0.0, float(14) * 0.35),
					ctxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.0))
	var font := ThemeDB.fallback_font
	var rs:  String = _bs.ROLE_NAMES[pilot.role]
	var tsz  := font.get_string_size(rs, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
	draw_string(font, center - tsz * 0.5 + Vector2(0.0, float(fsize) * 0.35), rs,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color.WHITE)
	if show_hp:
		var bw  := 60.0; var bh := 8.0
		var bx  := center.x - bw * 0.5; var by_ := center.y + 38.0
		draw_rect(Rect2(bx, by_, bw, bh), Color(0.2, 0.2, 0.2))
		draw_rect(Rect2(bx, by_, bw * float(pilot.hp) / float(pilot.max_hp), bh),
				Color(0.2, 0.85, 0.2))


func _draw_cell_badge_new(cell: Vector2i, c0: int, c1: int) -> void:
	var text:   String
	var bg_col: Color
	if c0 > 0 and c1 > 0:
		text   = "%dv%d" % [c0, c1]
		bg_col = Color(0.72, 0.1, 0.1, 0.92)
	elif c0 > 1:
		text   = "x%d" % c0
		bg_col = Color(0.1, 0.22, 0.65, 0.88)
	else:
		text   = "x%d" % c1
		bg_col = Color(0.55, 0.1, 0.1, 0.88)
	var center := _bs.cell_center(cell)
	var bpos   := center + Vector2(12.0, -22.0)
	draw_rect(Rect2(bpos, Vector2(32.0, 18.0)), bg_col)
	draw_string(ThemeDB.fallback_font, bpos + Vector2(2.0, 14.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
