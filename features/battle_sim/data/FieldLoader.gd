extends Node

## Reads field geometry from TileMapLayer nodes.
## Replaces DataLoader's field-geometry loading (waypoints, turrets, HQ, NZ, disabled cells).
##
## Call load_field() before _populate_from_data_loader() in BattleSim._ready().

# ── Output (empty until load_field() succeeds) ────────────────────────────────
var hqs:                Array = []          # [{team, col, row}, ...]
var turret_pos:         Dictionary = {}     # [lane_id][team][tier] → Vector2i
var waypoints:          Array = [[], []]    # [team][lane] → Array[Vector2i]
var neutral_zone_cells: Array = []          # [zone_id] → Array[Vector2i]
var disabled_cells:     Array = []          # [{col, row}, ...]
var min_cell:           Vector2i = Vector2i.ZERO       # actual tilemap min bounds
var max_cell:           Vector2i = Vector2i(8, 10)     # actual tilemap max bounds


func load_field(
		tiles_layer: TileMapLayer,
		building_layer: Node2D,
		waypoints_layer: Node2D) -> bool:
	_read_disabled(tiles_layer)
	_read_nz_cells(tiles_layer)
	_read_objects_from_buildings(building_layer)
	_read_waypoints(waypoints_layer)
	return true


# ── Private helpers ───────────────────────────────────────────────────────────

func _read_disabled(tiles_layer: TileMapLayer) -> void:
	disabled_cells.clear()
	var used: Array = tiles_layer.get_used_cells()
	var used_set: Dictionary = {}
	for cell in used:
		used_set[cell] = true

	if used.is_empty():
		return

	# Derive the actual cell bounds from painted tiles (may use negative coords).
	var min_c: int = (used[0] as Vector2i).x
	var max_c: int = min_c
	var min_r: int = (used[0] as Vector2i).y
	var max_r: int = min_r
	for cell: Vector2i in used:
		if cell.x < min_c: min_c = cell.x
		if cell.x > max_c: max_c = cell.x
		if cell.y < min_r: min_r = cell.y
		if cell.y > max_r: max_r = cell.y
	min_cell = Vector2i(min_c, min_r)
	max_cell = Vector2i(max_c, max_r)

	# Mark any cell within the bounding box that wasn't painted as disabled.
	for col in range(min_c, max_c + 1):
		for row in range(min_r, max_r + 1):
			var v := Vector2i(col, row)
			if not used_set.has(v):
				disabled_cells.append({"col": col, "row": row})


func _read_nz_cells(tiles_layer: TileMapLayer) -> void:
	neutral_zone_cells.clear()
	for _i in range(4):
		neutral_zone_cells.append([])

	# Collect cells marked as neutral zone via owner_id custom data
	var nz_set: Dictionary = {}
	for cell in tiles_layer.get_used_cells():
		var td := tiles_layer.get_cell_tile_data(cell)
		if td == null:
			continue
		var raw = td.get_custom_data("owner_id")
		if raw == null:
			continue
		if int(str(raw)) != 3:
			continue
		nz_set[cell] = true

	if nz_set.is_empty():
		return

	# Group into connected components (8-directional adjacency)
	var visited: Dictionary = {}
	var groups: Array = []
	for cell in nz_set.keys():
		if visited.has(cell):
			continue
		var group: Array = []
		var queue: Array = [cell]
		visited[cell] = true
		while queue.size() > 0:
			var c: Vector2i = queue.pop_front()
			group.append(c)
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var nb := Vector2i(c.x + dx, c.y + dy)
					if nz_set.has(nb) and not visited.has(nb):
						visited[nb] = true
						queue.append(nb)
		groups.append(group)

	# Sort groups: row descending (player-side first), then col ascending (left before right)
	groups.sort_custom(func(a: Array, b: Array) -> bool:
		var ar: float = 0.0
		for c: Vector2i in a: ar += c.y
		ar /= a.size()
		var br: float = 0.0
		for c: Vector2i in b: br += c.y
		br /= b.size()
		if abs(ar - br) > 0.5:
			return ar > br
		var ac: float = 0.0
		for c: Vector2i in a: ac += c.x
		ac /= a.size()
		var bc: float = 0.0
		for c: Vector2i in b: bc += c.x
		bc /= b.size()
		return ac < bc
	)

	for i in range(mini(groups.size(), 4)):
		neutral_zone_cells[i] = groups[i]


func _read_objects_from_buildings(building_layer: Node2D) -> void:
	hqs.clear()
	turret_pos.clear()
	if building_layer == null:
		return
	for child in building_layer.get_children():
		if not child is Building:
			continue
		var b := child as Building
		# Building.team: 1 = Ally (player = team 0), 2 = Enemy (team 1)
		var gd_team: int = b.team - 1
		var cell: Vector2i = b.tile_coords
		match b.tower_level:
			GameEnums.TowerLevel.HQ:
				hqs.append({"team": gd_team, "col": cell.x, "row": cell.y})
			GameEnums.TowerLevel.LEVEL_2:
				var lane_id: int = int(b.lane)
				if lane_id < 0:
					continue
				if not turret_pos.has(lane_id):
					turret_pos[lane_id] = {}
				if not turret_pos[lane_id].has(gd_team):
					turret_pos[lane_id][gd_team] = {}
				turret_pos[lane_id][gd_team][2] = cell
			GameEnums.TowerLevel.LEVEL_1:
				var lane_id: int = int(b.lane)
				if lane_id < 0:
					continue
				if not turret_pos.has(lane_id):
					turret_pos[lane_id] = {}
				if not turret_pos[lane_id].has(gd_team):
					turret_pos[lane_id][gd_team] = {}
				turret_pos[lane_id][gd_team][1] = cell


func _read_waypoints(waypoints_layer: Node2D) -> void:
	waypoints = [[], []]
	for _i in range(3):
		waypoints[0].append([])
		waypoints[1].append([])

	# Gather HQ positions from hqs (already loaded)
	var player_hq := Vector2i(-1, -1)
	var enemy_hq  := Vector2i(-1, -1)
	for hq in hqs:
		if hq["team"] == 0:
			player_hq = Vector2i(hq["col"], hq["row"])
		else:
			enemy_hq = Vector2i(hq["col"], hq["row"])

	# Collect (lane_id, step, pos) from Waypoint child nodes
	var lane_steps: Array = [{}, {}, {}]  # lane_id → {waypoint_id → Vector2i}
	for child in waypoints_layer.get_children():
		if not child is Waypoint:
			continue
		var wp := child as Waypoint
		var lane_id: int = int(wp.lane)
		var wp_step: int = wp.waypoint_id
		if lane_id >= 0 and lane_id < 3:
			(lane_steps[lane_id] as Dictionary)[wp_step] = wp.tile_coords

	# Build full team-0 path: [player_hq, step0..N sorted, enemy_hq]
	for lane_id in range(3):
		var steps: Dictionary = lane_steps[lane_id] as Dictionary
		var sorted_steps: Array = steps.keys()
		sorted_steps.sort()
		var path: Array = []
		if player_hq != Vector2i(-1, -1):
			path.append(player_hq)
		for s in sorted_steps:
			path.append(steps[s] as Vector2i)
		if enemy_hq != Vector2i(-1, -1):
			path.append(enemy_hq)
		waypoints[0][lane_id] = path
		waypoints[1][lane_id] = path.duplicate()
		(waypoints[1][lane_id] as Array).reverse()
