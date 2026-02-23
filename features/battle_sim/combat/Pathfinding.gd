class_name Pathfinding
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim


func bfs_next_step(from: Vector2i, to: Vector2i, mover: PilotData,
		constraint, stop_dist: int = 1, preferred_col: int = -1) -> Vector2i:
	var blocked: Dictionary = {}
	var queue: Array[Vector2i] = [from]
	var came_from: Dictionary  = { from: from }
	var found := Vector2i(-1, -1)

	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if manhattan(cur, to) <= stop_dist:
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
	var bd: int = chebyshev(from, to)
	for nb in neighbors(from, constraint, preferred_col):
		if not blocked.has(nb):
			var d: int = chebyshev(nb, to)
			if d < bd: best = nb; bd = d
	return best


func neighbors(pos: Vector2i, constraint, preferred_col: int = -1) -> Array[Vector2i]:
	# Vertical moves first, then lateral, then diagonal — ensures column preference
	var deltas: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
	]
	var pref: Array[Vector2i] = []
	var rest: Array[Vector2i] = []
	for d in deltas:
		var n := Vector2i(pos.x + d.x, pos.y + d.y)
		if n.x >= 0 and n.x < _bs.GRID_COLS and n.y >= 0 and n.y < _bs.GRID_ROWS:
			if constraint == null or n.x in (constraint as Array):
				if preferred_col >= 0 and n.x == preferred_col:
					pref.append(n)
				else:
					rest.append(n)
	return pref + rest


func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))


func manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
