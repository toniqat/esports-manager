class_name Pathfinding
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim


# `forbidden_cells` filters cells the caller wants the pathfinder to refuse to
# enter (e.g. jungle cells for lane pilots). The starting cell is always allowed
# even if it is in `forbidden_cells`, so a displaced pilot can still escape.
func bfs_next_step(from: Vector2i, to: Vector2i,
		forbidden_cells: Dictionary = {}) -> Vector2i:
	var queue: Array[Vector2i] = [from]
	var came_from: Dictionary  = { from: from }
	var found := Vector2i(-1, -1)

	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == to:
			found = cur; break
		for nb in neighbors(cur, forbidden_cells):
			if not came_from.has(nb):
				came_from[nb] = cur
				queue.append(nb)

	if found == Vector2i(-1, -1):
		return greedy(from, to, forbidden_cells)

	var path: Array[Vector2i] = [found]
	while path[-1] != from:
		path.append(came_from[path[-1]])
	path.reverse()
	return path[1] if path.size() >= 2 else from


func greedy(from: Vector2i, to: Vector2i,
		forbidden_cells: Dictionary = {}) -> Vector2i:
	var best := from
	var bd: int = _bs.hex_grid.hex_distance(from, to)
	for nb in neighbors(from, forbidden_cells):
		var d: int = _bs.hex_grid.hex_distance(nb, to)
		if d < bd: best = nb; bd = d
	return best


func neighbors(pos: Vector2i,
		forbidden_cells: Dictionary = {}) -> Array[Vector2i]:
	var raw: Array[Vector2i] = _bs.hex_grid.get_neighbors(pos.x, pos.y)
	var result: Array[Vector2i] = []
	for n in raw:
		if forbidden_cells.has(n): continue
		result.append(n)
	return result
