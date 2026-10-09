class_name TrainingResearchOwned
extends CanvasLayer

# Modal (dimmed) list of the run's owned training courses — the bottom bar action
# `보유 중인 훈련 코스` of a training facility body (`TrainingResearchBody.on_bottom_action`).
# One `TrainingCourseCard` (the training board's inventory look) per owned line at its owned
# level (`TrainingCourses.owned_tile_ids`, CSV order), cap = owned copies (`×n`, `∞` for the
# basic line). Tap a course = its info popover (`TrainingCoursePopover`; any tap closes it).
# Close button or a tap on the dim closes the modal. Read-only — nothing changes state.
#
# **Layout lives in `UI_View_TrainingResearchOwned.tscn`.** This script fills the grid (sample
# cards cleared in `_ready`), caps the scroll height to the safe area and places the popover.

signal closed

const SCENE_PATH: String = "res://features/season/facility/research/UI_View_TrainingResearchOwned.tscn"
## Vertical room kept for the title, sub line, gaps and the close button when capping the scroll.
const CHROME_H: float = 380.0

var _state: Dictionary = {}
var _scroller: DragScroll = null


static func create() -> TrainingResearchOwned:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TrainingResearchOwned


## Opens the modal under `host` for the run `state` and returns it.
static func open(host: Node, state: Dictionary) -> TrainingResearchOwned:
	var p := create()
	host.add_child(p)
	p.bind(state)
	return p


func _ready() -> void:
	var grid: GridContainer = %Grid
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	(%Dim as Button).pressed.connect(close)
	(%Close as Button).pressed.connect(close)
	(%InfoCatcher as Control).gui_input.connect(_on_info_input)
	(%TrainingCoursePopover_Info as Control).gui_input.connect(_on_info_input)
	_scroller = DragScroll.attach(%Scroll)
	_fit_safe_area()
	if UiPreview.is_standalone(self):
		_fill_preview()


func bind(state: Dictionary) -> void:
	_state = state
	_fill()


func close() -> void:
	if is_queued_for_deletion():
		return
	visible = false
	closed.emit()
	queue_free()


func _fill() -> void:
	var ids: Array = TrainingCourses.owned_tile_ids(_state)
	var grid: GridContainer = %Grid
	while grid.get_child_count() < ids.size():
		var card := TrainingCourseCard.create()
		grid.add_child(card)
		card.gui_input.connect(_on_card_input.bind(card))
	for i in grid.get_child_count():
		var card: TrainingCourseCard = grid.get_child(i)
		card.visible = i < ids.size()
		if not card.visible:
			continue
		var tile_id: String = String(ids[i])
		var def: Dictionary = (Engine.get_main_loop() as SceneTree).root.get_node("/root/GameManager") \
				.training_tile_def(tile_id)
		card.fill(TrainingTile.from_def(def), TrainingResearchBody.cap_of(_state, tile_id), false)
	_fit_scroll(ids.size())


# The grid scrolls only past what fits between the chrome and the safe area.
func _fit_scroll(n: int) -> void:
	var grid: GridContainer = %Grid
	var rows: int = maxi(1, ceili(float(n) / float(maxi(1, grid.columns))))
	var cell_h: float = 236.0
	if grid.get_child_count() > 0:
		cell_h = (grid.get_child(0) as Control).custom_minimum_size.y
	var gap: float = float(grid.get_theme_constant(&"v_separation"))
	var need: float = rows * cell_h + maxf(0.0, rows - 1) * gap
	var cap: float = ScreenMetrics.safe_h() - CHROME_H
	(%Scroll as Control).custom_minimum_size.y = clampf(need, cell_h, maxf(cell_h, cap))


func _fit_safe_area() -> void:
	var safe: Control = %SafeArea
	safe.offset_top = ScreenMetrics.top_y()
	safe.offset_bottom = ScreenMetrics.bottom_y() - ScreenMetrics.viewport_size().y


# A release on a course without scrolling = show its info.
func _on_card_input(event: InputEvent, card: TrainingCourseCard) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or mb.pressed:
		return
	if _scroller != null and _scroller.moved:
		return
	_show_info(card)


func _show_info(card: TrainingCourseCard) -> void:
	if card.tile == null:
		return
	var pop: TrainingCoursePopover = %TrainingCoursePopover_Info
	pop.fill(card.tile, (card.get_node("%Cap") as Label).text)
	TrainingResearchBody.place_popover(pop, card.get_global_rect(), (%Root as Control).get_global_rect())
	pop.visible = true
	(%InfoCatcher as Control).visible = true


func _close_info() -> void:
	(%TrainingCoursePopover_Info as Control).visible = false
	(%InfoCatcher as Control).visible = false


func _on_info_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		_close_info()
		get_viewport().set_input_as_handled()


## F6 preview — the in-memory run with every course owned.
func _fill_preview() -> void:
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	TrainingCourses.grant_all(gm.season_state, 2)
	bind(gm.season_state)
