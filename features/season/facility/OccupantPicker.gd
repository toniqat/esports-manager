class_name OccupantPicker
extends CanvasLayer

# Modal (dimmed) picker of a facility's occupant — opened by the occupant button of the
# facility screen (`FacilityView`). The manager and every run staff member as `StaffThumb`
# cards in a 3-column grid, each with their value of the facility's stat under it. Tapping a
# card seats that person (`FacilitySystem.assign`) and closes; `자리 비우기` empties the seat.
# Seating is offered only at HUB (`ResearchSystem.can_select`) — otherwise the cards are disabled.
#
# **Layout lives in `UI_View_OccupantPicker.tscn`** (card, grid, buttons). This script fills the
# grid (sample cells cleared in `_ready`), caps the scroll height to the safe area and emits
# `changed` after a seat changed (the caller refreshes), `closed` when the picker goes away.

signal changed
signal closed

const SCENE_PATH: String = "res://features/season/facility/UI_View_OccupantPicker.tscn"
## Vertical room kept for the title, sub line, gaps and buttons when capping the grid scroll.
const CHROME_H: float = 420.0

var _state: Dictionary = {}
var _fid: String = ""


static func create() -> OccupantPicker:
	return (load(SCENE_PATH) as PackedScene).instantiate() as OccupantPicker


## Opens the picker of facility `fid` under `host` and returns it.
static func open(host: Node, state: Dictionary, fid: String) -> OccupantPicker:
	var p := create()
	host.add_child(p)
	p.bind(state, fid)
	return p


func _ready() -> void:
	for c in %Grid.get_children():
		%Grid.remove_child(c)
		c.queue_free()
	%Dim.pressed.connect(close)
	%Close.pressed.connect(close)
	%Release.pressed.connect(_on_release)
	DragScroll.attach(%Scroll)
	_fit_safe_area()
	if UiPreview.is_standalone(self):
		_fill_preview()


func bind(state: Dictionary, fid: String) -> void:
	_state = state
	_fid = fid
	_fill()


func close() -> void:
	if is_queued_for_deletion():
		return
	visible = false
	closed.emit()
	queue_free()


func _fill() -> void:
	var state: Dictionary = _state
	var fid: String = _fid
	var stat: String = FacilitySystem.stat_of(fid)
	var open_now: bool = ResearchSystem.can_select(state)
	var stat_name: String = StaffSystem.stat_label(stat)
	%Sub.text = Loc.t(L.FACILITY_UI_PICKER_SUB, {"stat": stat_name,
			"used": FacilitySystem.manager_slots_used(state), "max": FacilitySystem.manager_slots()})
	if not open_now:
		%Sub.text = Loc.t(L.FACILITY_UI_LOCKED)
	var people: Array = [FacilitySystem.OCC_MANAGER]
	for raw in ((state.get("run_setup", {}) as Dictionary).get("staff", []) as Array):
		people.append(str(int((raw as Dictionary).get("id", -1))))
	var grid: GridContainer = %Grid
	while grid.get_child_count() < people.size():
		var t := StaffThumb.create()
		grid.add_child(t)
		t.pressed.connect(_on_pick.bind(t))
	var here: String = FacilitySystem.occupant(state, fid)
	for i in grid.get_child_count():
		var t: StaffThumb = grid.get_child(i)
		t.visible = i < people.size()
		if not t.visible:
			continue
		var who: String = String(people[i])
		var value: int = StaffSystem.STAT_MIN
		var display: String = ""
		var sub: String = ""
		if who == FacilitySystem.OCC_MANAGER:
			display = Loc.t(L.TERM_PERSON_MANAGER)
			sub = Loc.t(L.FACILITY_UI_OCC_MANAGER_SUB, {"used": FacilitySystem.manager_slots_used(state),
					"max": FacilitySystem.manager_slots()})
			value = StaffSystem.manager_value(state, stat)
		else:
			var e: Dictionary = FacilitySystem.run_staff(state, int(who))
			display = StaffSystem.staff_name(e)
			var at: String = FacilitySystem.facility_of_staff(state, int(who))
			var job: String = StaffSystem.job_label(String(e.get("job", "")))
			sub = Loc.t(L.FACILITY_UI_OCC_FREE, {"job": job}) if at == "" \
					else Loc.t(L.FACILITY_UI_OCC_AT, {"job": job, "facility": FacilitySystem.facility_name(at)})
			value = clampi(int((e.get("stats", {}) as Dictionary).get(stat, StaffSystem.STAT_MIN)),
					StaffSystem.STAT_MIN, StaffSystem.STAT_MAX)
		var is_here: bool = who == here
		var why: String = "" if is_here else FacilitySystem.assign_block_reason(state, fid, who)
		t.show_person(who, display, why if why != "" else sub,
				Loc.t(L.FACILITY_UI_OCC_VALUE, {"stat": stat_name, "value": value}), is_here, why != "")
		t.disabled = not open_now or why != "" or is_here
	%Release.visible = here != FacilitySystem.OCC_NONE
	%Release.disabled = not open_now
	_fit_scroll(people.size())


# The grid scrolls only past what fits between the chrome and the safe area.
func _fit_scroll(n: int) -> void:
	var grid: GridContainer = %Grid
	var rows: int = ceili(float(n) / float(maxi(1, grid.columns)))
	var cell_h: float = 330.0
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


func _on_pick(t: StaffThumb) -> void:
	if FacilitySystem.assign(_state, _fid, t.who) != "":
		_fill()
		return
	changed.emit()
	close()


func _on_release() -> void:
	FacilitySystem.unassign(_state, _fid)
	changed.emit()
	close()


## F6 단독 실행 미리보기 — 메모리 런의 전력 분석실 담당자 고르기.
func _fill_preview() -> void:
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	UiPreview.trace(changed, "changed")
	bind(gm.season_state, "intel")
