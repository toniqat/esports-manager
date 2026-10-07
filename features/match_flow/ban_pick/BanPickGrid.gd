@tool
class_name BanPickGrid
extends Container

# The mech grid's container (`%Grid` in `UI_View_BanPickView.tscn`): `columns` cells per row, each at its
# own minimum size, `h_gap` / `v_gap` apart, left-to-right then top-to-bottom. Hidden cells are
# skipped, so the role filter only toggles `visible` and the grid reflows.
#
# Why not `GridContainer`: it lays out in whole pixels, and the cell width is fractional
# (content 998 / 5 columns with 10 gaps = 191.6) — rows drifted 0.6px each. This one keeps the
# float positions. `@tool` so the editor previews the layout.

@export var columns: int = 5:
	set(v):
		columns = maxi(1, v)
		queue_sort()
		update_minimum_size()
@export var h_gap: float = 10.0:
	set(v):
		h_gap = v
		queue_sort()
		update_minimum_size()
@export var v_gap: float = 10.0:
	set(v):
		v_gap = v
		queue_sort()
		update_minimum_size()


func _cells() -> Array:
	var out: Array = []
	for c in get_children():
		var ctl := c as Control
		if ctl != null and ctl.visible and not ctl.top_level:
			out.append(ctl)
	return out


func _cell_size(cells: Array) -> Vector2:
	var s := Vector2.ZERO
	for c in cells:
		s = s.max((c as Control).get_combined_minimum_size())
	return s


func _get_minimum_size() -> Vector2:
	var cells: Array = _cells()
	if cells.is_empty():
		return Vector2.ZERO
	var cs: Vector2 = _cell_size(cells)
	var cols: int = mini(columns, cells.size())
	var rows: int = int(ceil(float(cells.size()) / float(columns)))
	return Vector2(float(cols) * cs.x + float(cols - 1) * h_gap,
			float(rows) * cs.y + float(rows - 1) * v_gap)


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	var cells: Array = _cells()
	var cs: Vector2 = _cell_size(cells)
	for i in range(cells.size()):
		var col: int = i % columns
		var row: int = floori(float(i) / float(columns))
		fit_child_in_rect(cells[i] as Control,
				Rect2(Vector2(float(col) * (cs.x + h_gap), float(row) * (cs.y + v_gap)), cs))
