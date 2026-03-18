class_name Pathfinding
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim


func bfs_next_step(from: Vector2i, to: Vector2i, _mover: PilotData,
		constraint, stop_dist: int = 1, preferred_col: int = -1) -> Vector2i:
	var blocked: Dictionary = {}
	var queue: Array[Vector2i] = [from]
	var came_from: Dictionary  = { from: from }
	var found := Vector2i(-1, -1)

	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if _bs._hex_grid.hex_distance(cur, to) <= stop_dist:
			found = cur; break
		for nb in neighbors(cur, constraint, preferred_col):
			if not came_from.has(nb) and not blocked.has(nb):
				came_from[nb] = cur
				queue.append(nb)

	if found == Vector2i(-1, -1):
		return greedy(from, to, blocked, constraint, preferred_col)

	var path: Array[Vector2i] = [found]
	while path[-1] != from:
		path.append(came_from[path[-1]])
	path.reverse()
	return path[1] if path.size() >= 2 else from


func greedy(from: Vector2i, to: Vector2i, blocked: Dictionary,
		constraint, preferred_col: int = -1) -> Vector2i:
	var best := from
	var bd: int = _bs._hex_grid.hex_distance(from, to)
	for nb in neighbors(from, constraint, preferred_col):
		if not blocked.has(nb):
			var d: int = _bs._hex_grid.hex_distance(nb, to)
			if d < bd: best = nb; bd = d
	return best


func neighbors(pos: Vector2i, constraint, preferred_col: int = -1) -> Array[Vector2i]:
	var raw: Array[Vector2i] = _bs._hex_grid.get_neighbors(pos.x, pos.y)
	var pref: Array[Vector2i] = []
	var rest: Array[Vector2i] = []
	for n in raw:
		if constraint == null or n.x in (constraint as Array):
			if preferred_col >= 0 and n.x == preferred_col:
				pref.append(n)
			else:
				rest.append(n)
	return pref + rest


# Kept for backward-compat with SimulationCore call sites; delegates to hex_distance.
func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return _bs._hex_grid.hex_distance(a, b)


func manhattan(a: Vector2i, b: Vector2i) -> int:
	return _bs._hex_grid.hex_distance(a, b)
