class_name HexGrid
extends Node

# ─── Grid constants ───────────────────────────────────────────────────────────
const COLS := 9
const ROWS := 11

# Multiplier applied to the BattleField sprite render and to hex geometry. All
# pilot/HUD draw sizes that should track tile size derive from `hex_size`, so
# changing this value scales the whole battlefield display in lockstep.
#
# 1.35 = 예전 값 1.5 의 **90%**. 전장 픽셀 박스가 990×1092 → 891×983 으로
# 줄면서, 화면 중앙(y 860)에 정렬된 전장의 상단이 314 → 369, 하단이
# 1406 → 1351 로 각각 55px 안쪽으로 들어온다. 핸드 행(`BattleSim.BS_HAND_CENTER`)
# 은 그 하단이 올라간 만큼 함께 위로 올려 카드와 전장 사이의 간격을 유지한다.
const DISPLAY_SCALE := 1.35

# ─── Layout vars (computed in _ready) ────────────────────────────────────────
var hex_size:      float  # circumradius of each flat-top hex
var hex_height:    float  # sqrt(3) * hex_size  (distance between parallel flat edges)
var grid_origin_x: float  # screen x of left edge of col-0 hexes
var grid_top:      float  # screen y of the center of row-0 cells (even col, unshifted)

# ─── Invalid-cell lookup (built from FieldLoader via set_disabled_cells) ─────
var _invalid_set: Dictionary = {}

# ─── Grid bounds (set from FieldLoader after tilemap is read) ─────────────────
var _grid_min: Vector2i = Vector2i.ZERO
var _grid_max: Vector2i = Vector2i(8, 10)


func _ready() -> void:
	# Geometry is populated by init_from_tilemap() called from BattleSim._ready().
	# These defaults match tile_size (120, 104) and ensure the grid is usable if
	# init_from_tilemap() is never called.
	const SCREEN_W   := 1080.0
	const TOP_MARGIN := 160.0
	const AVAIL_H    := 1760.0
	hex_size      = 60.0   # tile_size.x / 2 = 120 / 2
	hex_height    = 104.0  # tile_size.y
	grid_origin_x = (SCREEN_W - 14.0 * hex_size) / 2.0  # (1080 - 840) / 2 = 120
	var grid_h    := 11.5 * hex_height                   # 598 px
	var top_edge  := TOP_MARGIN + (AVAIL_H - grid_h) / 2.0
	grid_top      = top_edge + hex_height / 2.0
	# _invalid_set starts empty; populated later via set_disabled_cells()


## Derives hex geometry from the TileMapLayer's actual map_to_local() output,
## applies DISPLAY_SCALE to the BattleField parent so tiles/buildings/waypoints
## render at the chosen scale, computes the pixel bounding box of all used
## tiles, and centres that bounding box on screen. Returns the position
## BattleField must be set to.
## Call this from BattleSim._ready() after load_field(), passing the current viewport size.
func init_from_tilemap(tm: TileMapLayer, vp_size: Vector2) -> Vector2:
	# 0. Apply DISPLAY_SCALE to the BattleField parent so tile sprites,
	#    buildings, and waypoints all render at the same enlarged size. The
	#    hex geometry below is computed against this scale so pilot positions
	#    (drawn outside BattleField by BattleRenderer) line up with tile centres.
	var bf := tm.get_parent() as Node2D
	if bf != null:
		bf.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)

	# 1. Sample hex geometry from TileMap output.
	#    Use two even-col cells 2 apart for a clean x-delta, and adjacent rows for y-delta.
	var p00 := tm.map_to_local(Vector2i(0, 0))
	var p20 := tm.map_to_local(Vector2i(2, 0))
	var p01 := tm.map_to_local(Vector2i(0, 1))
	# Multiply by DISPLAY_SCALE because tm.map_to_local() returns unscaled
	# tilemap-local positions; the world distances are scaled by the parent.
	hex_size   = (p20.x - p00.x) / 3.0 * DISPLAY_SCALE  # circumradius; col pitch = hex_size * 1.5
	hex_height = (p01.y - p00.y) * DISPLAY_SCALE        # row pitch = tile height

	# 2. Compute the pixel bounding box of all placed tile centres (TileMapLayer local space).
	var min_local := Vector2(INF, INF)
	var max_local := Vector2(-INF, -INF)
	for cell: Vector2i in tm.get_used_cells():
		var lp: Vector2 = tm.map_to_local(cell)
		if lp.x < min_local.x: min_local.x = lp.x
		if lp.y < min_local.y: min_local.y = lp.y
		if lp.x > max_local.x: max_local.x = lp.x
		if lp.y > max_local.y: max_local.y = lp.y
	# Expand cell centres by half-tile to reach the true pixel edges.
	# `hex_size` / `hex_height` are already scaled, so undo that here for
	# the unscaled local-space bounds.
	min_local -= Vector2(hex_size, hex_height * 0.5) / DISPLAY_SCALE
	max_local += Vector2(hex_size, hex_height * 0.5) / DISPLAY_SCALE

	# 3. Centre the SCALED tile bounding box on screen.
	#    World pos of a local point p = bf_pos + (tm.position + p) * DISPLAY_SCALE.
	var grid_center_local := (min_local + max_local) * 0.5
	var bf_pos := vp_size * 0.5 - (tm.position + grid_center_local) * DISPLAY_SCALE

	# 4. Derive grid_origin_x / grid_top so hex_to_screen() aligns with the SCALED TileMap.
	#    Anchoring on cell (0,0): hex_to_screen(0,0) = bf_pos + (tm.position + p00) * DISPLAY_SCALE.
	var screen_00 := bf_pos + (tm.position + p00) * DISPLAY_SCALE
	grid_origin_x = screen_00.x - hex_size
	grid_top      = screen_00.y - hex_height * 0.5

	return bf_pos


# ─── Public API ───────────────────────────────────────────────────────────────

func is_valid_cell(col: int, row: int) -> bool:
	if col < _grid_min.x or col > _grid_max.x or row < _grid_min.y or row > _grid_max.y:
		return false
	return not _invalid_set.has(Vector2i(col, row))


func set_disabled_cells(cells: Array) -> void:
	_invalid_set.clear()
	for c in cells:
		_invalid_set[Vector2i(c["col"], c["row"])] = true


func set_grid_bounds(min_c: Vector2i, max_c: Vector2i) -> void:
	_grid_min = min_c
	_grid_max = max_c


## Flat-top hex, STACKED layout, even columns shifted DOWN, row-0 at TOP.
## x increases right, y increases down (screen coords).
func hex_to_screen(col: int, row: int) -> Vector2:
	var x := grid_origin_x + float(col) * hex_size * 1.5 + hex_size
	var y := grid_top + (float(row) + (0.5 if col % 2 == 0 else 0.0)) * hex_height
	return Vector2(x, y)


## Returns the valid neighbors of (col, row).
## Offsets for flat-top STACKED even-cols-DOWN, row-0 at top:
##   Even col: N=(0,-1) S=(0,+1) NE=(+1,0) SE=(+1,+1) NW=(-1,0) SW=(-1,+1)
##   Odd  col: N=(0,-1) S=(0,+1) NE=(+1,-1) SE=(+1,0) NW=(-1,-1) SW=(-1,0)
func get_neighbors(col: int, row: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var offsets: Array[Vector2i]
	if col % 2 == 0:
		offsets = [
			Vector2i( 0, -1),  # N
			Vector2i( 0,  1),  # S
			Vector2i( 1,  0),  # NE
			Vector2i( 1,  1),  # SE
			Vector2i(-1,  0),  # NW
			Vector2i(-1,  1),  # SW
		]
	else:
		offsets = [
			Vector2i( 0, -1),  # N
			Vector2i( 0,  1),  # S
			Vector2i( 1, -1),  # NE
			Vector2i( 1,  0),  # SE
			Vector2i(-1, -1),  # NW
			Vector2i(-1,  0),  # SW
		]
	for d in offsets:
		var n := Vector2i(col + d.x, row + d.y)
		if is_valid_cell(n.x, n.y):
			result.append(n)
	return result


## Returns the 6 corner vertices of the flat-top hex centered at `center`.
## Angles: 0°, 60°, 120°, 180°, 240°, 300° (first vertex points right/east).
func hex_corners(center: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(6):
		var angle_rad := deg_to_rad(60.0 * float(i))
		pts.append(center + Vector2(hex_size * cos(angle_rad), hex_size * sin(angle_rad)))
	return pts


## Convert offset (col, row) to cube coordinates.
## Flat-top even-q DOWN stagger (even columns shifted south by half hex_height).
## Formula: z = row - (col + (col & 1)) / 2, y = -x - z.
## Using (col + (col & 1)) / 2 with GDScript truncation gives floor(col/2)
## for both positive and negative columns, unlike plain col/2 which truncates
## toward zero (wrong for negative odd columns).
func offset_to_cube(col: int, row: int) -> Vector3i:
	var x := col
	@warning_ignore("integer_division")
	var z := row - (col + (col & 1)) / 2
	var y := -x - z
	return Vector3i(x, y, z)


## Hex distance (minimum number of hex steps) between two offset cells.
func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var ca := offset_to_cube(a.x, a.y)
	var cb := offset_to_cube(b.x, b.y)
	@warning_ignore("integer_division")
	return (abs(ca.x - cb.x) + abs(ca.y - cb.y) + abs(ca.z - cb.z)) / 2
