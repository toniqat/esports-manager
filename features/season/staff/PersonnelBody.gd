class_name PersonnelBody
extends VBoxContainer

# Personnel office body (§16, facility `personnel`) — `FacilityView` %BodySlot, built by
# `PersonnelResearch.make_body`. The office scouts on its own (auto research, no picker):
#   스태프 목록 — every run staffer as a `StaffThumb` (job · where they sit, weekly salary), 3 columns,
#                 about 2.5 rows visible, scrolls inside. Count · salary total on the title line.
#                 Tap → `ConfirmPopup` (name, job, salary, six stats) → `StaffSystem.dismiss`.
#   영입 후보   — the last scout's unanswered candidates (`PersonnelResearch.candidates`), same cards,
#                 the rest of the body, scrolls inside. The scouting gauge (bar + %) sits on the
#                 header line. Tap → `ConfirmPopup` → `PersonnelResearch.hire_candidate` (the list is
#                 consumed — the others go back).
# After a hire / dismiss the body refills and emits `changed` (the header and the occupant picker
# read staff). Refusals go out as `message` (the screen's toast).
#
# **Layout lives in `UI_View_PersonnelBody.tscn`**; cards are `staff/UI_Comp_StaffThumb.tscn`.

## After a hire / dismiss — the host refreshes whatever reads the staff.
signal changed
## A refusal to show as the facility screen's toast.
signal message(text: String)

const SCENE_PATH: String = "res://features/season/staff/UI_View_PersonnelBody.tscn"
var _state: Dictionary = {}
var _confirm: ConfirmPopup = null
# What the open confirm popup acts on: {"op": "dismiss" | "hire", "id": int}.
var _pending: Dictionary = {}


## Instantiates the scene. `PersonnelBody.new()` is an empty box — don't use it.
static func create() -> PersonnelBody:
	return (load(SCENE_PATH) as PackedScene).instantiate() as PersonnelBody


func _ready() -> void:
	for grid: Node in [%StaffGrid, %CandGrid]:
		for c in grid.get_children():
			grid.remove_child(c)
			c.queue_free()
	DragScroll.attach(%StaffScroll)
	DragScroll.attach(%CandScroll)
	if UiPreview.is_standalone(self):
		_fill_preview()


## Binds the live `season_state` and fills both grids.
func bind(state: Dictionary) -> void:
	_state = state
	if is_node_ready():
		refresh()
	else:
		ready.connect(refresh, CONNECT_ONE_SHOT)


func refresh() -> void:
	if _state.is_empty():
		return
	_fill_staff()
	_fill_candidates()


# ── Grids ────────────────────────────────────────────────────────────────────
func _fill_staff() -> void:
	var staff: Array = (_state.get("run_setup", {}) as Dictionary).get("staff", [])
	%StaffSub.text = Loc.t(L.RESEARCH_PERSONNEL_BODY_STAFF_SUB,
			{"n": staff.size(), "amount": StaffSystem.weekly_salary_total(_state)})
	%StaffEmpty.visible = staff.is_empty()
	%StaffScroll.visible = not staff.is_empty()
	var grid: GridContainer = %StaffGrid
	_thumbs(grid, staff.size(), _on_staff_pressed)
	for i in staff.size():
		var e: Dictionary = staff[i]
		var sid: int = int(e.get("id", -1))
		var job: String = StaffSystem.job_label(String(e.get("job", "")))
		var fid: String = FacilitySystem.facility_of_staff(_state, sid)
		var sub: String = Loc.t(L.RESEARCH_PERSONNEL_BODY_SUB_FREE, {"job": job}) if fid == "" \
				else Loc.t(L.RESEARCH_PERSONNEL_BODY_SUB_SEATED, {"job": job, "facility": FacilitySystem.facility_name(fid)})
		(grid.get_child(i) as StaffThumb).show_person(str(sid), StaffSystem.staff_name(e), sub,
				Loc.t(L.STAFF_PANEL_SALARY, {"amount": int(e.get("salary", 0))}))


func _fill_candidates() -> void:
	var ratio: float = ResearchSystem.progress(_state, PersonnelResearch.FACILITY)
	(%ScoutFill as Control).anchor_right = ratio
	%ScoutPct.text = Loc.t(L.RESEARCH_PERSONNEL_BODY_SCOUT_PROGRESS,
			{"percent": ResearchBubble.percent_text(ratio)})
	var ids: Array = PersonnelResearch.candidates(_state)
	var grid: GridContainer = %CandGrid
	_thumbs(grid, ids.size(), _on_cand_pressed)
	for i in ids.size():
		var sid: int = int(ids[i])
		var e: Dictionary = StaffSystem.staff_row(sid)
		(grid.get_child(i) as StaffThumb).show_person(str(sid), StaffSystem.staff_name(e),
				StaffSystem.job_label(String(e.get("job", ""))),
				Loc.t(L.STAFF_PANEL_SALARY, {"amount": int(e.get("salary", 0))}))


# Keeps exactly `n` thumbs in `grid` (new ones wired to `handler(thumb)`).
static func _thumbs(grid: GridContainer, n: int, handler: Callable) -> void:
	while grid.get_child_count() > n:
		var c: Node = grid.get_child(grid.get_child_count() - 1)
		grid.remove_child(c)
		c.queue_free()
	while grid.get_child_count() < n:
		var t := StaffThumb.create()
		grid.add_child(t)
		t.pressed.connect(handler.bind(t))


# ── Actions (confirm popup) ──────────────────────────────────────────────────
func _on_staff_pressed(t: StaffThumb) -> void:
	var sid: int = int(t.who)
	var why: String = StaffSystem.dismiss_block_reason(_state, sid)
	if why != "":
		message.emit(why)
		return
	var e: Dictionary = FacilitySystem.run_staff(_state, sid)
	var lines: Array = [info_text(e)]
	var fid: String = FacilitySystem.facility_of_staff(_state, sid)
	if fid != "":
		lines.append(Loc.t(L.RESEARCH_PERSONNEL_BODY_DISMISS_SEATED, {"facility": FacilitySystem.facility_name(fid)}))
	_open_confirm({"op": "dismiss", "id": sid},
			Loc.t(L.RESEARCH_PERSONNEL_BODY_DISMISS_TITLE, {"name": StaffSystem.staff_name(e)}),
			"\n\n".join(lines), Loc.t(L.RESEARCH_PERSONNEL_BODY_DISMISS), true)


func _on_cand_pressed(t: StaffThumb) -> void:
	var sid: int = int(t.who)
	var why: String = StaffSystem.hire_block_reason(_state, sid)
	if why != "":
		message.emit(why)
		return
	var e: Dictionary = StaffSystem.staff_row(sid)
	var lines: Array = [info_text(e)]
	var rest: int = PersonnelResearch.candidates(_state).size() - 1
	if rest > 0:
		lines.append(Loc.t(L.RESEARCH_PERSONNEL_BODY_HIRE_REST, {"n": rest}))
	_open_confirm({"op": "hire", "id": sid},
			Loc.t(L.RESEARCH_PERSONNEL_BODY_HIRE_TITLE, {"name": StaffSystem.staff_name(e)}),
			"\n\n".join(lines), Loc.t(L.RESEARCH_PERSONNEL_BODY_HIRE), false)


func _open_confirm(pending: Dictionary, title: String, body: String, ok_text: String, danger: bool) -> void:
	if _confirm == null:
		_confirm = ConfirmPopup.create()
		add_child(_confirm)
		_confirm.confirmed.connect(_on_confirmed)
		_confirm.cancelled.connect(func() -> void: _pending = {})
	_pending = pending
	_confirm.open(title, body, Loc.t(L.UI_BUTTON_CANCEL), ok_text, danger)


func _on_confirmed() -> void:
	var p: Dictionary = _pending
	_pending = {}
	if p.is_empty():
		return
	var sid: int = int(p["id"])
	var why: String = StaffSystem.dismiss(_state, sid) if String(p["op"]) == "dismiss" \
			else PersonnelResearch.hire_candidate(_state, sid)
	if why != "":
		message.emit(why)
	refresh()
	changed.emit()


## "<job> · 주급 n" then the six stats, three per line (`StaffSystem.STATS` order).
static func info_text(e: Dictionary) -> String:
	var head: String = Loc.t(L.RESEARCH_PERSONNEL_BODY_INFO, {
			"job": StaffSystem.job_label(String(e.get("job", ""))), "salary": int(e.get("salary", 0))})
	var stats: Dictionary = e.get("stats", {})
	var parts: Array = []
	for s in StaffSystem.STATS:
		parts.append("%s %d" % [StaffSystem.stat_label(String(s)), int(stats.get(s, StaffSystem.STAT_MIN))])
	var half: int = ceili(parts.size() / 2.0)
	return "%s\n%s\n%s" % [head, " · ".join(parts.slice(0, half)), " · ".join(parts.slice(half))]


## F6 단독 실행 미리보기 — 메모리 런의 스태프 + 스카우트 후보 4명(`PersonnelResearch.draw`),
## 스카우트 게이지 일부 채움.
func _fill_preview() -> void:
	UiPreview.stage(self)
	offset_left = 40.0
	offset_right = -40.0
	offset_top = 40.0
	offset_bottom = -40.0
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var state: Dictionary = gm.season_state
	var sc: Dictionary = state.get("scout", {})
	sc["candidates"] = PersonnelResearch.draw(state, 4, 7)
	state["scout"] = sc
	var a: Dictionary = ResearchSystem.active(state, PersonnelResearch.FACILITY)
	if not a.is_empty():
		var r: Dictionary = ResearchSystem.row(String(a["rid"]))
		var res: Dictionary = state.get("research", {})
		(res["points"] as Dictionary)[ResearchSystem.key_of(String(a["rid"]), String(a["target"]))] = \
				int(ResearchSystem.cost(r) * 0.4)
	UiPreview.trace(changed, "changed")
	UiPreview.trace(message, "message")
	bind(state)
