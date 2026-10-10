@tool
class_name BaseMapRoads
extends Node2D

# ── Road network of a base map (길) ──────────────────────────────────────────────
#   BaseMap_<Name>
#   └ Roads (this, hidden at runtime) ─ Line2D × N  (draw the roads; any number of points)
# The lines become one graph (`build`): points closer than `SNAP` merge, a line end that
# stops on another line joins it (T junction), and two lines that cross join where they
# cross. Pilots walk this graph (`route`: A*); a spot's pilots aim at the road point
# nearest the spot marker (`snap`).
# The editor marks the graph's nodes: green = joined (junction), red = a dead end, so
# a gap that should be a junction shows at a glance.

const SNAP: float = 12.0
const _EDITOR_JOIN: Color = Color(0.1, 0.85, 0.3, 0.95)
const _EDITOR_END: Color = Color(0.95, 0.2, 0.2, 0.95)
const _EDITOR_REFRESH: float = 0.4

var _pts: PackedVector2Array = PackedVector2Array()
var _adj: Array = []         # node id → Array[int]
var _astar: AStar2D = AStar2D.new()
var _editor_wait: float = 0.0


func _ready() -> void:
	build()
	if not Engine.is_editor_hint():
		visible = false
		set_process(false)


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_editor_wait -= delta
	if _editor_wait <= 0.0:
		_editor_wait = _EDITOR_REFRESH
		build()
		queue_redraw()


func is_empty() -> bool:
	return _pts.is_empty()


# ── Graph ────────────────────────────────────────────────────────────────────
## Rebuilds the graph from the Line2D children (their points in this node's space).
func build() -> void:
	_pts = PackedVector2Array()
	_adj = []
	var edges: Array = []   # [a, b]
	for c in get_children():
		var line: Line2D = c as Line2D
		if line == null or line.points.size() < 2:
			continue
		var prev: int = -1
		var first: int = -1
		for p in line.points:
			var id: int = _node_at(line.transform * p)
			if first < 0:
				first = id
			if prev >= 0 and prev != id:
				edges.append([prev, id])
			prev = id
		if line.closed and prev != first:
			edges.append([prev, first])
	edges = _join_t(edges)
	edges = _join_crossings(edges)
	_adj.resize(_pts.size())
	for i in _adj.size():
		_adj[i] = []
	for e in edges:
		_link(int(e[0]), int(e[1]))
	_astar.clear()
	for i in _pts.size():
		_astar.add_point(i, _pts[i])
	for i in _adj.size():
		for j in (_adj[i] as Array):
			if not _astar.are_points_connected(i, int(j)):
				_astar.connect_points(i, int(j))


func _node_at(p: Vector2) -> int:
	for i in _pts.size():
		if _pts[i].distance_to(p) <= SNAP:
			return i
	_pts.append(p)
	return _pts.size() - 1


func _link(a: int, b: int) -> void:
	if a == b or (_adj[a] as Array).has(b):
		return
	(_adj[a] as Array).append(b)
	(_adj[b] as Array).append(a)


## A node lying on another edge (closer than SNAP, not at its ends) splits that edge.
func _join_t(edges: Array) -> Array:
	for id in _pts.size():
		var i: int = 0
		while i < edges.size():
			var a: int = edges[i][0]
			var b: int = edges[i][1]
			if a != id and b != id:
				var q: Vector2 = Geometry2D.get_closest_point_to_segment(_pts[id], _pts[a], _pts[b])
				if q.distance_to(_pts[id]) <= SNAP:
					edges[i] = [a, id]
					edges.append([id, b])
			i += 1
	return edges


## Two edges that cross (not at a shared node) are split at the crossing.
func _join_crossings(edges: Array) -> Array:
	var i: int = 0
	while i < edges.size():
		var j: int = i + 1
		while j < edges.size():
			var a: int = edges[i][0]
			var b: int = edges[i][1]
			var c: int = edges[j][0]
			var d: int = edges[j][1]
			if a != c and a != d and b != c and b != d:
				var hit: Variant = Geometry2D.segment_intersects_segment(_pts[a], _pts[b], _pts[c], _pts[d])
				if hit != null:
					var id: int = _node_at(hit as Vector2)
					if id != a and id != b and id != c and id != d:
						edges[i] = [a, id]
						edges[j] = [c, id]
						edges.append([id, b])
						edges.append([id, d])
			j += 1
		i += 1
	return edges


## Nearest road point to `p`: `{point: Vector2, a: int, b: int}` (on edge a–b), or `{}`
## when there are no roads.
func closest(p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for a in _adj.size():
		for b_raw in (_adj[a] as Array):
			var b: int = int(b_raw)
			if b < a:
				continue
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, _pts[a], _pts[b])
			var d: float = q.distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = {"point": q, "a": a, "b": b}
	return best


## Road point nearest to `p` (`p` itself without roads).
func snap(p: Vector2) -> Vector2:
	var c: Dictionary = closest(p)
	return p if c.is_empty() else c["point"]


## Path along the roads from `from` to `to` (both snapped first), as screen points
## from start to end. Straight `[from, to]` without roads or without a connection.
func route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var cf: Dictionary = closest(from)
	var ct: Dictionary = closest(to)
	if cf.is_empty() or ct.is_empty():
		return PackedVector2Array([from, to])
	var pf: Vector2 = cf["point"]
	var pt: Vector2 = ct["point"]
	var same_edge: bool = (int(cf["a"]) == int(ct["a"]) and int(cf["b"]) == int(ct["b"]))
	var best := PackedVector2Array([pf, pt]) if same_edge else PackedVector2Array()
	var best_len: float = pf.distance_to(pt) if same_edge else INF
	for s in [int(cf["a"]), int(cf["b"])]:
		for e in [int(ct["a"]), int(ct["b"])]:
			var ids: PackedInt64Array = _astar.get_id_path(s, e)
			if ids.is_empty():
				continue
			var path := PackedVector2Array([pf])
			for id in ids:
				path.append(_pts[id])
			path.append(pt)
			var length: float = path_length(path)
			if length < best_len:
				best_len = length
				best = path
	if best.is_empty():
		return PackedVector2Array([from, to])
	return _dedupe(best)


static func _dedupe(path: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in path:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.5:
			out.append(p)
	if out.size() == 1:
		out.append(out[0])
	return out


static func path_length(path: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


## Point `dist` pixels along `path` (clamped to its ends).
static func point_along(path: PackedVector2Array, dist: float) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	var left: float = maxf(0.0, dist)
	for i in range(1, path.size()):
		var seg: float = path[i - 1].distance_to(path[i])
		if left <= seg and seg > 0.0:
			return path[i - 1].lerp(path[i], left / seg)
		left -= seg
	return path[path.size() - 1]


# ── Editor preview ───────────────────────────────────────────────────────────
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	for i in _pts.size():
		var deg: int = (_adj[i] as Array).size() if i < _adj.size() else 0
		if deg >= 3:
			draw_circle(_pts[i], 7.0, _EDITOR_JOIN)
		elif deg <= 1:
			draw_circle(_pts[i], 6.0, _EDITOR_END)
