class_name VisitMenu
extends CanvasLayer

# ── Afternoon visit popup (방문, §15 D) ───────────────────────────────────────
# Four pages in one card (`UI_View_VisitMenu.tscn` owns the layout):
#   pick     2+ pilots who can be visited share the tapped map spot → `pilot_picked(pid)`
#            (Back / the dim = `closed`, nothing recorded yet)
#   menu     집중 훈련 / 이야기 / 외출 → `option_picked("focus" | "story" | "outing")`.
#            The visit is already recorded (`MentalSystem.begin_visit`), so this page has
#            no way out but an option.
#   courses  the focus training courses (`FocusTraining.courses_view`): tap one, then
#            Confirm → `course_picked(id)`; Back → menu
#   result   the focus training notes; Confirm → `closed`
# The owner (`WeekProgressView`) applies everything — this popup only draws and emits.
# Create with `create()`, add it, then `open_picker` / `open_menu`.

signal pilot_picked(pid: int)
signal option_picked(option: String)
signal course_picked(id: String)
signal closed

const SCENE_PATH: String = "res://features/season/week/UI_View_VisitMenu.tscn"
const PILOT_ROW_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_VisitPilotRow.tscn")
const COURSE_ROW_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_VisitCourseRow.tscn")

const OPTION_FOCUS: String = "focus"
const OPTION_STORY: String = "story"
const OPTION_OUTING: String = "outing"

enum Page { PICK, MENU, COURSES, RESULT }

const HEADER_PORTRAIT_D: float = 96.0
const ROW_PORTRAIT_D: float = 88.0

var _page: int = Page.MENU
var _pid: int = -1
var _course: String = ""          # course picked on the courses page ("" = none yet)
var _course_rows: Dictionary = {}  # course id -> row Button


## Instantiates the scene (`VisitMenu.new()` is an empty CanvasLayer).
static func create() -> VisitMenu:
	return (load(SCENE_PATH) as PackedScene).instantiate() as VisitMenu


func _ready() -> void:
	(%Dim as Button).pressed.connect(_on_dim)
	(%Back as Button).pressed.connect(_on_back)
	(%Confirm as Button).pressed.connect(_on_confirm)
	(%Focus as Button).pressed.connect(func(): option_picked.emit(OPTION_FOCUS))
	(%Story as Button).pressed.connect(func(): option_picked.emit(OPTION_STORY))
	(%Outing as Button).pressed.connect(func(): option_picked.emit(OPTION_OUTING))
	_fit_safe_area()
	if UiPreview.is_standalone(self):
		_fill_preview()


## Pick page: who of `pids` (all on the tapped spot) to visit.
func open_picker(state: Dictionary, pids: Array) -> void:
	_pid = -1
	_fill_header(state)
	for c in (%PickList as Control).get_children():
		c.queue_free()
	for raw in pids:
		_add_pilot_row(state, int(raw))
	_show_page(Page.PICK)


## Menu page for the visited pilot `pid` on weekday `day`.
func open_menu(state: Dictionary, pid: int, day: int) -> void:
	_pid = pid
	_fill_header(state)
	_fill_options(state, day)
	_show_page(Page.MENU)


## Courses page (focus training) for the visited pilot.
func show_courses(state: Dictionary) -> void:
	_course = ""
	_course_rows.clear()
	_fill_header(state)
	for c in (%Courses as Control).get_children():
		c.queue_free()
	for raw in FocusTraining.courses_view(state, _pid):
		_add_course_row(raw)
	_show_page(Page.COURSES)


## Result page: the outcome's note texts (`MentalEvents.note_texts`).
func show_result(state: Dictionary, lines: Array) -> void:
	_fill_header(state)
	var holder: Control = %Result
	var template: Label = %ResultLine
	for c in holder.get_children():
		if c != template:
			c.queue_free()
	for t in lines:
		if String(t) == "":
			continue
		var lbl: Label = template.duplicate() as Label
		lbl.text = String(t)
		lbl.visible = true
		holder.add_child(lbl)
	_show_page(Page.RESULT)


func is_open() -> bool:
	return visible


# ── Pages ────────────────────────────────────────────────────────────────────
func _show_page(page: int) -> void:
	_page = page
	(%PickList as Control).visible = page == Page.PICK
	(%Options as Control).visible = page == Page.MENU
	(%Courses as Control).visible = page == Page.COURSES
	(%Result as Control).visible = page == Page.RESULT
	var caption: String = Loc.t(L.MENTAL_UI_VISIT_TITLE_MENU)
	match page:
		Page.PICK:
			caption = Loc.t(L.MENTAL_UI_VISIT_TITLE_PICK)
		Page.COURSES:
			caption = Loc.t(L.MENTAL_UI_VISIT_TITLE_COURSES)
		Page.RESULT:
			caption = Loc.t(L.MENTAL_UI_VISIT_TITLE_RESULT)
	(%Caption as Label).text = caption
	var back: Button = %Back
	var confirm: Button = %Confirm
	back.visible = page == Page.PICK or page == Page.COURSES
	back.text = Loc.t(L.UI_BUTTON_CANCEL if page == Page.PICK else L.UI_BUTTON_BACK)
	confirm.visible = page == Page.COURSES or page == Page.RESULT
	confirm.text = Loc.t(L.MENTAL_UI_VISIT_FOCUS if page == Page.COURSES else L.UI_BUTTON_CONFIRM)
	confirm.disabled = page == Page.COURSES and _course == ""
	(%Buttons as Control).visible = back.visible or confirm.visible
	visible = true


## Header: the visited pilot (portrait · name · trust / stress) and the week's coach points.
## The pick page has no pilot yet: only the points.
func _fill_header(state: Dictionary) -> void:
	var portrait: Control = %Portrait
	for c in portrait.get_children():
		c.queue_free()
	var has_pilot: bool = _pid >= 0
	portrait.visible = has_pilot
	(%Name as Label).visible = has_pilot
	(%PilotLine as Label).visible = has_pilot
	if has_pilot:
		OutgameTheme.add_round_portrait(portrait, PilotImages.circle_for(_pid), Vector2.ZERO,
				HEADER_PORTRAIT_D, OutgameTheme.ACCENT)
		(%Name as Label).text = MentalEvents.pilot_name(state, _pid)
		(%PilotLine as Label).text = _pilot_line(state, _pid)
	(%Coach as Label).text = Loc.t(L.MENTAL_UI_VISIT_COACH_POINTS, {"n": StaffSystem.coach_points(state)})


static func _pilot_line(state: Dictionary, pid: int) -> String:
	return Loc.t(L.MENTAL_UI_VISIT_PILOT_LINE, {"trust": MentalSystem.trust_level(state, pid),
			"stress": StressSystem.value(state, pid)})


## The three options. 집중 훈련 is greyed out when no course can be paid (points short);
## 외출 when the trust level is below `TRUST_OUTING_LEVEL` (the note says why).
func _fill_options(state: Dictionary, day: int) -> void:
	(%FocusTitle as Label).text = Loc.t(L.MENTAL_UI_VISIT_FOCUS)
	var can_focus: bool = StaffSystem.coach_points(state) >= ConstTable.int_of("FOCUS_COST")
	(%Focus as Button).disabled = not can_focus
	var focus_note: Label = %FocusNote
	focus_note.text = Loc.t(L.MENTAL_UI_VISIT_FOCUS_NOTE) if can_focus \
			else Loc.t(L.MENTAL_UI_VISIT_NEED_POINTS, {"n": ConstTable.int_of("FOCUS_COST")})
	focus_note.theme_type_variation = &"CaptionLabel" if can_focus else &"NegativeLabel"
	(%StoryTitle as Label).text = Loc.t(L.MENTAL_UI_VISIT_STORY)
	(%StoryNote as Label).text = _story_note(state, day)
	(%OutingTitle as Label).text = Loc.t(L.TERM_ACTIVITY_OUTING)
	var can_out: bool = MentalSystem.can_outing(state, _pid)
	(%Outing as Button).disabled = not can_out
	var out_note: Label = %OutingNote
	out_note.text = Loc.t(L.MENTAL_UI_VISIT_OUTING_NOTE) if can_out \
			else Loc.t(L.MENTAL_UI_VISIT_OUTING_LOCKED, {"n": ConstTable.int_of("TRUST_OUTING_LEVEL")})
	out_note.theme_type_variation = &"CaptionLabel" if can_out else &"NegativeLabel"


## What today's story is about — the first pool of `MentalSystem.story_kinds_for`.
static func _story_note(state: Dictionary, day: int) -> String:
	match String(MentalSystem.story_kinds_for(state, day)[0]):
		MentalEvents.KIND_STORY:
			return Loc.t(L.MENTAL_UI_VISIT_STORY_NOTE_WEEKDAY)
		MentalEvents.KIND_STORY_SAT:
			return Loc.t(L.MENTAL_UI_VISIT_STORY_NOTE_SAT)
		MentalEvents.KIND_STORY_SUN:
			return Loc.t(L.MENTAL_UI_VISIT_STORY_NOTE_SUN)
	return Loc.t(L.MENTAL_UI_VISIT_STORY_NOTE_FREE)


func _add_pilot_row(state: Dictionary, pid: int) -> void:
	var row: Button = PILOT_ROW_SCENE.instantiate() as Button
	(%PickList as Control).add_child(row)
	OutgameTheme.add_round_portrait(row.get_node("%Portrait"), PilotImages.circle_for(pid), Vector2.ZERO,
			ROW_PORTRAIT_D)
	(row.get_node("%Name") as Label).text = MentalEvents.pilot_name(state, pid)
	(row.get_node("%Line") as Label).text = _pilot_line(state, pid)
	row.pressed.connect(func(): pilot_picked.emit(pid))


func _add_course_row(c: Dictionary) -> void:
	var row: Button = COURSE_ROW_SCENE.instantiate() as Button
	(%Courses as Control).add_child(row)
	var id: String = String(c["id"])
	(row.get_node("%Name") as Label).text = String(c["name"])
	(row.get_node("%Stats") as Label).text = String(c["stats"])
	(row.get_node("%Cost") as Label).text = Loc.t(L.MENTAL_UI_VISIT_COST, {"n": int(c["cost"])})
	var reason: Label = row.get_node("%Reason")
	reason.text = String(c["reason"])
	reason.visible = not bool(c["enabled"])
	row.disabled = not bool(c["enabled"])
	row.pressed.connect(_on_course_row.bind(id))
	_course_rows[id] = row


func _on_course_row(id: String) -> void:
	_course = id
	for k in _course_rows.keys():
		(_course_rows[k] as Button).theme_type_variation = \
				&"SelectableCardButtonOn" if String(k) == id else &"SelectableCardButton"
	(%Confirm as Button).disabled = false


func _on_dim() -> void:
	if _page == Page.PICK:
		closed.emit()


func _on_back() -> void:
	if _page == Page.PICK:
		closed.emit()
	elif _page == Page.COURSES:
		_show_page(Page.MENU)


func _on_confirm() -> void:
	if _page == Page.COURSES and _course != "":
		course_picked.emit(_course)
	elif _page == Page.RESULT:
		closed.emit()


## The card sits in `%SafeArea` (CenterContainer), shrunk to the safe area so the
## buttons never fall into the notch or the gesture band.
func _fit_safe_area() -> void:
	var safe: Control = %SafeArea
	safe.offset_top = ScreenMetrics.top_y()
	safe.offset_bottom = ScreenMetrics.bottom_y() - ScreenMetrics.viewport_size().y


## F6 preview — an in-memory run (`resources/UiPreview.gd`), the menu page for my first
## pilot on Wednesday; the options and the courses page are live (nothing is applied).
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var s: Dictionary = gm.season_state
	var ids: Array = MentalSystem.my_pilot_ids(s)
	if ids.is_empty():
		return
	UiPreview.trace(pilot_picked)
	UiPreview.trace(course_picked)
	UiPreview.trace(closed)
	option_picked.connect(func(opt: String):
		if opt == OPTION_FOCUS:
			show_courses(s))
	open_menu(s, int(ids[0]), 2)
