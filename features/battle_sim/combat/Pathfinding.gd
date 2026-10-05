class_name Pathfinding
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim


## `bfs_next_step(..., greedy_fallback = false)` 가 길을 못 찾았을 때 돌려주는 값.
## 전장 좌표는 음수를 쓰므로 (-1,-1) 은 멀쩡한 칸이다 — 그래서 격자 밖의 값을 쓴다.
const UNREACHABLE := Vector2i(-99999, -99999)


# `forbidden_cells` filters cells the caller wants the pathfinder to refuse to
# enter (e.g. jungle cells for lane pilots). The starting cell is always allowed
# even if it is in `forbidden_cells`, so a displaced pilot can still escape.
# 길이 없으면 기본은 `greedy` 로 한 걸음이라도 다가가고, `greedy_fallback` 을
# 끄면 `UNREACHABLE` 을 돌려준다 — 부르는 쪽이 금지 집합을 풀고 다시 묻는 용도.
func bfs_next_step(from: Vector2i, to: Vector2i,
		forbidden_cells: Dictionary = {}, greedy_fallback: bool = true) -> Vector2i:
	var queue: Array[Vector2i] = [from]
	var came_from: Dictionary  = { from: from }
	# 도달 여부는 따로 든다 — 예전에는 `found == (-1,-1)` 을 "못 찾음"으로 읽었는데
	# (-1,-1) 은 미드 레인의 실제 칸이라, 그 칸이 목표면 찾고도 못 찾은 것으로 쳐서
	# greedy 로 떨어졌다.
	var reached: bool = false

	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == to:
			reached = true; break
		for nb in neighbors(cur, forbidden_cells):
			if not came_from.has(nb):
				came_from[nb] = cur
				queue.append(nb)

	if not reached:
		if not greedy_fallback:
			return UNREACHABLE
		return greedy(from, to, forbidden_cells)

	var path: Array[Vector2i] = [to]
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
