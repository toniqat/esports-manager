class_name ManagerTypeOption
extends PanelContainer

# One selectable card of `ManagerTypePopup`: name (+ "현재" chip) and description on top,
# the six manager stats (`StaffSystem.STATS` order) as a row of sunk cells below.
#
# **Layout lives in `ManagerTypeOption.tscn`** — the popup instantiates one per type into
# its `%Options` box. This script only fills text, toggles the chip and picks the
# selection look: the card switches between the theme variations `SelectableCard` /
# `SelectableCardOn` (both padding 0 — the scene's `Margin` pads, so the content never
# shifts with the border). The "현재" chip's `SURFACE_SUNK` pill has no variation and stays
# in code (`OutgameTheme.flat_style`).

## Released left click on the card (children are mouse-ignore, so the whole card is the target).
signal tapped

const CHIP_RADIUS: int = 18     # pill = half the chip height (36), like `OutgameTheme.add_chip`


func _ready() -> void:
	var chip := OutgameTheme.flat_style(OutgameTheme.SURFACE_SUNK, CHIP_RADIUS)
	chip.set_content_margin_all(0.0)    # the label fills the pill and centres itself
	(%Chip as PanelContainer).add_theme_stylebox_override("panel", chip)
	set_selected(false)
	gui_input.connect(_on_gui_input)


## `row` = one `StaffSystem.manager_types()` entry; `is_current` shows the "현재" chip.
func fill(row: Dictionary, is_current: bool) -> void:
	%Name.text = String(row.get("name", ""))
	%Desc.text = String(row.get("desc", ""))
	%Chip.visible = is_current
	var stats: Dictionary = row.get("stats", {})
	var cells: Array = %Stats.get_children()
	for i in mini(cells.size(), StaffSystem.STATS.size()):
		var key: String = String(StaffSystem.STATS[i])
		var cell: Node = cells[i]
		(cell.get_node("VBox/Key") as Label).text = String(StaffSystem.STAT_LABELS.get(key, key))
		(cell.get_node("VBox/Value") as Label).text = str(int(stats.get(key, StaffSystem.STAT_MIN)))


func set_selected(on: bool) -> void:
	theme_type_variation = &"SelectableCardOn" if on else &"SelectableCard"


func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	tapped.emit()
