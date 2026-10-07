class_name ManagerTypeOption
extends PanelContainer

# One selectable card of `ManagerTypePopup`: name (+ "현재" chip) and description on top,
# the six manager stats (`StaffSystem.STATS` order) as a row of sunk cells below.
#
# **Layout lives in `UI_Comp_ManagerTypeOption.tscn`** — the popup instantiates one per type into
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
	if UiPreview.is_standalone(self):
		_fill_preview()


## `row` = one `StaffSystem.manager_types()` entry; `is_current` shows the "현재" chip.
func fill(row: Dictionary, is_current: bool) -> void:
	%Name.text = Loc.t(String(row.get("name_key", "")))  # l10n-dynamic: manager.type.*.name
	%Desc.text = Loc.t(String(row.get("desc_key", "")))  # l10n-dynamic: manager.type.*.desc
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


## F6 단독 실행 미리보기 — 고른 상태의 "현재" 카드, 손으로 적은 스탯 (`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(tapped)
	var stats: Dictionary = {}
	var vals: Array = [5, 6, 5, 7, 6, 7]
	for i in StaffSystem.STATS.size():
		stats[String(StaffSystem.STATS[i])] = int(vals[i % vals.size()])
	fill({"name_key": "tx_J99WKD5PN8", "desc_key": "tx_T2Z72WAY5Q", "stats": stats}, true)
	set_selected(true)
	_preview_fit.call_deferred()


## 미리보기 전용 — 첫 배치 전에 0 폭으로 잰 설명(자동 줄바꿈)이 루트를 키워 둔 높이를
## 실제 최소 크기로 되돌리고 다시 가운데에 놓는다(컨테이너 안에서는 컨테이너가 맞춘다).
func _preview_fit() -> void:
	reset_size()
	UiPreview.stage(self)
