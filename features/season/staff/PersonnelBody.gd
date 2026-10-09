class_name PersonnelBody
extends VBoxContainer

# Personnel section of the `personnel` facility sheet (§16, decision 10) — built by
# `PersonnelResearch.make_body`. Two lists of `UI_Comp_PersonnelStaffRow`:
#   스태프 목록 — every run staffer: name, job (specialty label), six stats, weekly salary,
#                 the facility they sit in; `해고` (two-step: the first press arms the row,
#                 the second dismisses — a seated staffer is unseated first).
#   영입 후보   — the last scout's unanswered candidates: `영입` (two-step, salary on the
#                 row) adds one to the run team and consumes the list; `모두 보내기`
#                 (two-step) passes on all.
# Every change goes through `StaffSystem` / `PersonnelResearch`; the body then refills itself
# and emits `changed` so the host sheet can refresh what depends on staff (occupant picker,
# stat values, salary).
#
# **Layout lives in `UI_View_PersonnelBody.tscn`** (+ item scene `UI_Comp_PersonnelStaffRow.tscn`).
# The script fills `%` nodes, instances rows and swaps button texts / variations (armed state).

## After a hire / dismiss / pass — the host refreshes whatever reads the staff.
signal changed

const SCENE_PATH: String = "res://features/season/staff/UI_View_PersonnelBody.tscn"
const ROW_SCENE: PackedScene = preload("res://features/season/staff/UI_Comp_PersonnelStaffRow.tscn")
const _ARM_DISMISS: String = "dismiss:"
const _ARM_HIRE: String = "hire:"
const _ARM_PASS: String = "pass"

var _state: Dictionary = {}
# The armed two-step action ("" none, "dismiss:<id>", "hire:<id>", "pass").
var _armed: String = ""


## Instantiates the scene. `PersonnelBody.new()` is an empty box — don't use it.
static func create() -> PersonnelBody:
	return (load(SCENE_PATH) as PackedScene).instantiate() as PersonnelBody


func _ready() -> void:
	%PassAll.pressed.connect(_on_pass_pressed)
	if UiPreview.is_standalone(self):
		_fill_preview()


## Binds the live `season_state` and fills both lists.
func bind(state: Dictionary) -> void:
	_state = state
	_armed = ""
	if is_node_ready():
		refresh()
	else:
		ready.connect(refresh, CONNECT_ONE_SHOT)


func refresh() -> void:
	_fill_staff()
	_fill_candidates()


# ── Lists ────────────────────────────────────────────────────────────────────
func _fill_staff() -> void:
	var staff: Array = (_state.get("run_setup", {}) as Dictionary).get("staff", [])
	%StaffSub.text = Loc.t(L.RESEARCH_PERSONNEL_BODY_STAFF_SUB,
			{"n": staff.size(), "amount": StaffSystem.weekly_salary_total(_state)})
	%StaffEmpty.visible = staff.is_empty()
	var rows: Array = _rows(%StaffList, staff.size())
	for i in rows.size():
		var e: Dictionary = staff[i]
		var sid: int = int(e.get("id", -1))
		var row: Control = rows[i]
		_fill_row(row, e)
		var fid: String = FacilitySystem.facility_of_staff(_state, sid)
		var seat: Label = row.get_node("%Seat")
		seat.visible = true
		if fid != "":
			seat.text = Loc.t(L.RESEARCH_PERSONNEL_BODY_SEAT, {"facility": FacilitySystem.facility_name(fid)})
			seat.theme_type_variation = &"AccentLabel"
		else:
			seat.text = Loc.t(L.RESEARCH_PERSONNEL_BODY_SEAT_NONE)
			seat.theme_type_variation = &"FaintLabel"
		var armed: bool = _armed == _ARM_DISMISS + str(sid)
		var confirm_key: String = L.RESEARCH_PERSONNEL_BODY_DISMISS_SEATED_CONFIRM if fid != "" \
				else L.RESEARCH_PERSONNEL_BODY_DISMISS_CONFIRM
		var action_text: String = Loc.t(confirm_key if armed else L.RESEARCH_PERSONNEL_BODY_DISMISS)  # l10n-dynamic: research_personnel.body.dismiss*
		_set_action(row.get_node("%Action"), action_text, armed, _on_dismiss_pressed.bind(sid))


func _fill_candidates() -> void:
	var ids: Array = PersonnelResearch.candidates(_state)
	%CandSub.text = Loc.t(L.RESEARCH_PERSONNEL_BODY_CAND_SUB, {"n": ids.size()})
	%CandSub.visible = not ids.is_empty()
	%CandEmpty.visible = ids.is_empty()
	%PassRow.visible = not ids.is_empty()
	var rows: Array = _rows(%CandList, ids.size())
	for i in rows.size():
		var sid: int = int(ids[i])
		var row: Control = rows[i]
		_fill_row(row, StaffSystem.staff_row(sid))
		(row.get_node("%Seat") as Label).visible = false
		var armed: bool = _armed == _ARM_HIRE + str(sid)
		_set_action(row.get_node("%Action"),
				Loc.t(L.RESEARCH_PERSONNEL_BODY_HIRE_CONFIRM if armed else L.RESEARCH_PERSONNEL_BODY_HIRE),
				armed, _on_hire_pressed.bind(sid))
	var pass_armed: bool = _armed == _ARM_PASS
	(%PassAll as Button).text = Loc.t(L.RESEARCH_PERSONNEL_BODY_PASS_CONFIRM if pass_armed
			else L.RESEARCH_PERSONNEL_BODY_PASS_ALL)
	(%PassAll as Button).theme_type_variation = &"PrimaryButton" if pass_armed else &"GhostButton"


## Name · job · six stats · salary of one staff entry (run staff or `staff_row`).
func _fill_row(row: Control, e: Dictionary) -> void:
	row.get_node("%Name").text = StaffSystem.staff_name(e)
	row.get_node("%Job").text = StaffSystem.job_label(String(e.get("job", "")))
	row.get_node("%Stats").text = stats_text(e)
	row.get_node("%Salary").text = Loc.t(L.STAFF_PANEL_SALARY, {"amount": int(e.get("salary", 0))})


## "훈련 17 · 전술 8 · 메크 지식 6 · …" — the six stats in `StaffSystem.STATS` order.
static func stats_text(e: Dictionary) -> String:
	var stats: Dictionary = e.get("stats", {})
	var parts: Array = []
	for s in StaffSystem.STATS:
		parts.append("%s %d" % [StaffSystem.stat_label(String(s)), int(stats.get(s, StaffSystem.STAT_MIN))])
	return " · ".join(parts)


# Action button: text, armed look (PrimaryButton) and one fresh `pressed` handler.
static func _set_action(btn: Button, text: String, armed: bool, handler: Callable) -> void:
	btn.text = text
	btn.theme_type_variation = &"PrimaryButton" if armed else &"GhostButton"
	btn.pressed.connect(handler)


# ── Actions (two-step) ───────────────────────────────────────────────────────
func _on_dismiss_pressed(sid: int) -> void:
	if _armed != _ARM_DISMISS + str(sid):
		_arm(_ARM_DISMISS + str(sid))
		return
	_armed = ""
	StaffSystem.dismiss(_state, sid)
	_after_change()


func _on_hire_pressed(sid: int) -> void:
	if _armed != _ARM_HIRE + str(sid):
		_arm(_ARM_HIRE + str(sid))
		return
	_armed = ""
	PersonnelResearch.hire_candidate(_state, sid)
	_after_change()


func _on_pass_pressed() -> void:
	if _armed != _ARM_PASS:
		_arm(_ARM_PASS)
		return
	_armed = ""
	PersonnelResearch.pass_all(_state)
	_after_change()


func _arm(what: String) -> void:
	_armed = what
	refresh.call_deferred()


func _after_change() -> void:
	refresh.call_deferred()
	changed.emit()


# ── Helpers ──────────────────────────────────────────────────────────────────
## Replaces the list's rows with `n` fresh instances; the list hides when empty.
static func _rows(list: Node, n: int) -> Array:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	for i in n:
		list.add_child(ROW_SCENE.instantiate())
	(list as CanvasItem).visible = n > 0
	return list.get_children()


## F6 단독 실행 미리보기 — 메모리 런의 스태프 + 스카우트 후보 3명(`PersonnelResearch.draw`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var state: Dictionary = gm.season_state
	var sc: Dictionary = state.get("scout", {})
	sc["candidates"] = PersonnelResearch.draw(state, 3, 7)
	state["scout"] = sc
	changed.connect(func() -> void: print("[UiPreview] PersonnelBody changed"))
	bind(state)
