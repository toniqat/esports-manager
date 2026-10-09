class_name FacilitySheet
extends VBoxContainer

# Facility sheet (§16 decision 11) — a `HubSheet` body opened by tapping a facility (or its
# research bubble) on the hub map: `FacilitySheet.open(host, fid)`.
#
# **Layout lives in `UI_View_FacilitySheet.tscn`** (+ item scenes `UI_Comp_FacilityOccupantRow`,
# `UI_Comp_ResearchRow`, `UI_Comp_ResearchTargetChip`). This script fills `%` nodes, keeps the
# list rows (reused, never freed while their button is emitting), and wires the buttons.
# Sections, top to bottom:
#   head      — facility icon (ring at the active research's progress), desc, stat value, weekly points
#   level     — `Lv n / max`, the front cap note, cost, two-step upgrade (like `FinancePanel`),
#               block reason from `FacilitySystem.upgrade_block_reason`
#   occupant  — who sits here, manager slots `n/3`, the manager + every run staff with their
#               value of this facility's stat, assign / unassign (`FacilitySystem.assign`)
#   research  — the active research line, stop, the target picker (rows whose kind handler
#               offers `targets`), and one `ResearchRow` per `ResearchSystem.rows_for(fid)`
#   kind body — `ResearchSystem.make_body(state, fid)` (kind agents; null = section hidden)
#
# Every change refills the same instance in place (`_fill`); the sheet stays open and the
# hub's `closed → refresh` hook redraws the map once at the end. Selection and seating are
# offered only while `ResearchSystem.can_select(state)` (HUB, before the week opens).
#
# Kind body contract (duck typing, every kind body is top-wide with its natural height): after
# every refill the sheet calls the body's `refresh()` if it has one, else frees it and builds a
# fresh one with `ResearchSystem.make_body`; a `changed` signal (e.g. `PersonnelBody` after a
# hire / dismiss) refills the whole sheet (deferred, so the emitting button is never freed
# mid-signal).

const SCENE_PATH: String = "res://features/season/facility/UI_View_FacilitySheet.tscn"
const OCC_ROW_SCENE: PackedScene = preload("res://features/season/facility/UI_Comp_FacilityOccupantRow.tscn")
const ROW_SCENE: PackedScene = preload("res://features/season/facility/UI_Comp_ResearchRow.tscn")
const CHIP_SCENE: PackedScene = preload("res://features/season/facility/UI_Comp_ResearchTargetChip.tscn")
const SEP: String = " · "

var _sheet: HubSheet = null
var _state: Dictionary = {}
var _fid: String = ""
var _upgrade_armed: bool = false
## The targeted row whose target chips are open ("" = none).
var _pending_rid: String = ""
var _kind_body: Control = null


## Instantiates the scene. `FacilitySheet.new()` is an empty box — don't use it.
static func create() -> FacilitySheet:
	return (load(SCENE_PATH) as PackedScene).instantiate() as FacilitySheet


## Opens the sheet of facility `fid` under `host` and returns the `HubSheet` (connect `closed`).
static func open(host: Node, fid: String) -> HubSheet:
	var sheet := HubSheet.open_on(host, FacilitySystem.facility_name(fid))
	var gm: Node = host.get_node_or_null("/root/GameManager")
	var panel := create()
	sheet.body.add_child(panel)
	panel.bind(sheet, gm.season_state if gm != null else {}, fid)
	return sheet


func _ready() -> void:
	_clear(%Occupants)
	_clear(%Rows)
	_clear(%Targets)
	(%Upgrade as Button).pressed.connect(_on_upgrade)
	(%UpgradeConfirm as Button).pressed.connect(_on_upgrade)
	(%Stop as Button).pressed.connect(_on_stop)
	resized.connect(_fit_sheet)
	if UiPreview.is_standalone(self):
		_fill_preview()


## Binds the run state and the facility, builds the kind body once and fills everything.
func bind(sheet: HubSheet, state: Dictionary, fid: String) -> void:
	_sheet = sheet
	_state = state
	_fid = fid
	_upgrade_armed = false
	var act: Dictionary = ResearchSystem.active(state, fid)
	_pending_rid = String(act.get("rid", "")) if String(act.get("target", "")) != "" else ""
	_fill()
	_fit_sheet()


## The sheet scrolls exactly this node's height (the scene's `Tail` is the bottom gap).
func _fit_sheet() -> void:
	if _sheet != null:
		_sheet.set_body_height(size.y)


# ── Fill ─────────────────────────────────────────────────────────────────────
func _fill() -> void:
	_fill_head()
	_fill_level()
	_fill_occupants()
	_fill_research()
	_refresh_kind_body()


func _fill_head() -> void:
	var state: Dictionary = _state
	var fid: String = _fid
	%Desc.text = FacilitySystem.facility_desc(fid)
	var stat: String = FacilitySystem.stat_of(fid)
	%StatLine.text = Loc.t(L.FACILITY_UI_SHEET_STAT_LINE, {"stat": StaffSystem.stat_label(stat),
			"value": FacilitySystem.stat_value(state, fid)})
	var rate: Label = %RateLine
	if FacilitySystem.occupant(state, fid) == FacilitySystem.OCC_NONE:
		rate.text = Loc.t(L.FACILITY_UI_SHEET_RATE_NONE)
		rate.add_theme_color_override(&"font_color", OutgameTheme.NEGATIVE)
	else:
		var bp: int = ResearchSystem.boost_pct(state)
		rate.text = Loc.t(L.FACILITY_UI_SHEET_RATE_BOOST if bp != 0 else L.FACILITY_UI_SHEET_RATE,
				{"points": ResearchSystem.weekly_points(state, fid), "pct": bp})
		rate.add_theme_color_override(&"font_color", OutgameTheme.ACCENT_TEXT)
	# Head icon: the active research at its progress, else the facility icon (grey).
	var act: Dictionary = ResearchSystem.active(state, fid)
	var icon: Texture2D = ResearchSystem.row_icon(String(act["rid"])) if not act.is_empty() else null
	if icon == null:
		icon = FacilitySystem.icon_texture(String(FacilitySystem.def(fid).get("icon", "")))
	_ring(%Icon, icon, ResearchSystem.progress(state, fid), act.is_empty())


func _fill_level() -> void:
	var state: Dictionary = _state
	var fid: String = _fid
	var lvl: int = FacilitySystem.level(state, fid)
	var top: int = FacilitySystem.max_level()
	%LevelTitle.text = Loc.t(L.FACILITY_UI_SHEET_LEVEL_TITLE, {"level": lvl, "max": top})
	%LevelNote.text = Loc.t(L.FACILITY_UI_SHEET_LEVEL_FRONT) if fid == FacilitySystem.FRONT \
			else Loc.t(L.FACILITY_UI_SHEET_LEVEL_CAP, {"level": FacilitySystem.level(state, FacilitySystem.FRONT)})
	var cost: int = FacilitySystem.upgrade_cost(state, fid)
	%UpgradeCost.visible = lvl < top
	%UpgradeCost.text = Loc.t(L.FACILITY_UI_SHEET_UPGRADE_COST, {"cost": FinanceSystem.fmt(cost),
			"available": FinanceSystem.fmt(FinanceSystem.upgrade_funds(state))})
	var why: String = FacilitySystem.upgrade_block_reason(state, fid)
	%Upgrade.visible = why == "" and not _upgrade_armed
	%Upgrade.text = Loc.t(L.FACILITY_UI_SHEET_UPGRADE, {"level": lvl + 1})
	%UpgradeConfirm.visible = why == "" and _upgrade_armed
	%UpgradeConfirm.text = Loc.t(L.FACILITY_UI_SHEET_UPGRADE_CONFIRM, {"cost": FinanceSystem.fmt(cost)})
	%UpgradeBlocked.visible = why != ""
	%UpgradeBlocked.text = why


func _fill_occupants() -> void:
	var state: Dictionary = _state
	var fid: String = _fid
	var stat: String = FacilitySystem.stat_of(fid)
	var open_now: bool = ResearchSystem.can_select(state)
	%OccLine.text = Loc.t(L.FACILITY_UI_OCC_LINE, {"name": FacilitySystem.occupant_name(state, fid),
			"used": FacilitySystem.manager_slots_used(state), "max": FacilitySystem.manager_slots()})
	# The manager first, then every run staff member (run_setup.staff order).
	var people: Array = [FacilitySystem.OCC_MANAGER]
	for raw in ((state.get("run_setup", {}) as Dictionary).get("staff", []) as Array):
		people.append(str(int((raw as Dictionary).get("id", -1))))
	var rows: Array = _ensure_rows(%Occupants, OCC_ROW_SCENE, people.size(), _wire_occ_row)
	var here: String = FacilitySystem.occupant(state, fid)
	for i in rows.size():
		var row: Panel = rows[i]
		var who: String = String(people[i])
		row.set_meta(&"who", who)
		var is_here: bool = who == here
		row.theme_type_variation = &"SelectableCardOn" if is_here else &"Card"
		var sub: String = ""
		var value: int = StaffSystem.STAT_MIN
		if who == FacilitySystem.OCC_MANAGER:
			row.get_node("%Name").text = Loc.t(L.TERM_PERSON_MANAGER)
			sub = Loc.t(L.FACILITY_UI_OCC_MANAGER_SUB, {"used": FacilitySystem.manager_slots_used(state),
					"max": FacilitySystem.manager_slots()})
			value = StaffSystem.manager_value(state, stat)
		else:
			var e: Dictionary = FacilitySystem.run_staff(state, int(who))
			row.get_node("%Name").text = StaffSystem.staff_name(e)
			var at: String = FacilitySystem.facility_of_staff(state, int(who))
			var job: String = StaffSystem.job_label(String(e.get("job", "")))
			sub = Loc.t(L.FACILITY_UI_OCC_FREE, {"job": job}) if at == "" \
					else Loc.t(L.FACILITY_UI_OCC_AT, {"job": job, "facility": FacilitySystem.facility_name(at)})
			value = clampi(int((e.get("stats", {}) as Dictionary).get(stat, StaffSystem.STAT_MIN)),
					StaffSystem.STAT_MIN, StaffSystem.STAT_MAX)
		var why: String = "" if is_here else FacilitySystem.assign_block_reason(state, fid, who)
		var sub_l: Label = row.get_node("%Sub")
		sub_l.text = why if why != "" else sub
		sub_l.add_theme_color_override(&"font_color", OutgameTheme.NEGATIVE if why != "" else OutgameTheme.TEXT_SUB)
		row.get_node("%Value").text = Loc.t(L.FACILITY_UI_OCC_VALUE, {"stat": StaffSystem.stat_label(stat), "value": value})
		var assign: Button = row.get_node("%Assign")
		var release: Button = row.get_node("%Release")
		assign.visible = not is_here
		assign.disabled = not open_now or why != ""
		release.visible = is_here
		release.disabled = not open_now


func _wire_occ_row(row: Node) -> void:
	(row.get_node("%Assign") as Button).pressed.connect(_on_assign.bind(row))
	(row.get_node("%Release") as Button).pressed.connect(_on_release)


func _fill_research() -> void:
	var state: Dictionary = _state
	var fid: String = _fid
	var open_now: bool = ResearchSystem.can_select(state)
	var act: Dictionary = ResearchSystem.active(state, fid)
	var act_rid: String = String(act.get("rid", ""))
	var act_target: String = String(act.get("target", ""))
	var line: Label = %ResearchLine
	if act.is_empty():
		line.text = Loc.t(L.FACILITY_UI_RESEARCH_NONE)
		line.add_theme_color_override(&"font_color", OutgameTheme.TEXT_SUB)
	else:
		var label: String = ResearchSystem.row_name(act_rid)
		var tl: String = ResearchSystem.target_label(state, ResearchSystem.row(act_rid), act_target)
		if tl != "":
			label += " (%s)" % tl
		line.text = Loc.t(L.FACILITY_UI_RESEARCH_ACTIVE, {"research": label,
				"pct": ResearchBubble.percent_text(ResearchSystem.progress(state, fid))})
		line.add_theme_color_override(&"font_color", OutgameTheme.ACCENT_TEXT)
	var note: Label = %ResearchNote
	note.visible = not open_now or FacilitySystem.occupant(state, fid) == FacilitySystem.OCC_NONE
	note.text = Loc.t(L.FACILITY_UI_LOCKED) if not open_now else Loc.t(L.FACILITY_UI_RESEARCH_VACANT_NOTE)
	%Stop.visible = not act.is_empty() and open_now

	# Rows: every row of the facility (blocked ones disabled with their reason).
	var all_rows: Array = ResearchSystem.rows_for(fid)
	var rows: Array = _ensure_rows(%Rows, ROW_SCENE, all_rows.size(), _wire_research_row)
	for i in rows.size():
		_fill_row(rows[i], all_rows[i], act_rid, act_target, open_now)
	%RowsEmpty.visible = all_rows.is_empty()

	# Target picker of the pending targeted row.
	var pend: Dictionary = ResearchSystem.row(_pending_rid)
	var offered: Array = ResearchSystem.targets(state, pend) if not pend.is_empty() else []
	if pend.is_empty() or offered.is_empty() or ResearchSystem.block_reason(state, fid, pend) != "":
		_pending_rid = ""
		offered = []
	%TargetBox.visible = not offered.is_empty()
	%TargetTitle.text = Loc.t(L.FACILITY_UI_RESEARCH_TARGET_TITLE,
			{"research": ResearchSystem.row_name(_pending_rid)}) if _pending_rid != "" else ""
	var chips: Array = _ensure_rows(%Targets, CHIP_SCENE, offered.size(), _wire_chip)
	for i in chips.size():
		var chip: Button = chips[i]
		var t: Dictionary = offered[i]
		var tid: String = String(t.get("id", ""))
		chip.set_meta(&"target", tid)
		var on: bool = _pending_rid == act_rid and tid == act_target
		chip.theme_type_variation = &"SelectableTileOn" if on else &"SelectableTile"
		chip.text = Loc.t(L.FACILITY_UI_RESEARCH_TARGET_CHIP, {"label": String(t.get("label", tid)),
				"pct": ResearchBubble.percent_text(ResearchSystem.progress(state, fid, _pending_rid, tid))})
		chip.icon = t.get("icon", null) as Texture2D
		chip.disabled = not open_now


func _fill_row(row: Button, r: Dictionary, act_rid: String, act_target: String, open_now: bool) -> void:
	var state: Dictionary = _state
	var fid: String = _fid
	var rid: String = String(r["id"])
	row.set_meta(&"rid", rid)
	var why: String = ResearchSystem.block_reason(state, fid, r)
	var offered: Array = ResearchSystem.targets(state, r)
	var is_active: bool = rid == act_rid
	var targeted: bool = not offered.is_empty()
	# Progress / done of this row: the active target, else the furthest target (paused work).
	var target: String = act_target if is_active else ""
	var done: int = 0
	if targeted:
		for raw in offered:
			var tid: String = String((raw as Dictionary).get("id", ""))
			done += ResearchSystem.done_count(state, rid, tid)
			if not is_active and ResearchSystem.points(state, rid, tid) > ResearchSystem.points(state, rid, target):
				target = tid
	else:
		done = ResearchSystem.done_count(state, rid, "")
	var p: float = ResearchSystem.progress(state, fid, rid, target)
	row.theme_type_variation = &"SelectableCardButtonOn" if is_active or rid == _pending_rid \
			else &"SelectableCardButton"
	row.disabled = not open_now or why != ""
	_ring(row.get_node("%Icon"), ResearchSystem.row_icon(rid), p, why != "")
	row.get_node("%Name").text = ResearchSystem.row_name(rid)
	row.get_node("%Desc").text = ResearchSystem.row_desc(rid)
	var meta: Array = [Loc.t(L.FACILITY_UI_ROW_WEEKS, {"weeks": int(r.get("weeks", 1))})]
	if is_active or not targeted:
		var left: int = ResearchSystem.weeks_left(state, fid, rid, target)
		meta.append(Loc.t(L.FACILITY_UI_ROW_NEVER) if left < 0 else Loc.t(L.FACILITY_UI_ROW_LEFT, {"weeks": left}))
	if done > 0:
		meta.append(Loc.t(L.FACILITY_UI_ROW_DONE, {"n": done}))
	row.get_node("%Meta").text = SEP.join(meta)
	var block: Label = row.get_node("%Block")
	block.visible = why != ""
	block.text = why
	var state_l: Label = row.get_node("%State")
	state_l.text = Loc.t(L.FACILITY_UI_ROW_ACTIVE) if is_active \
			else (Loc.t(L.FACILITY_UI_ROW_PICK_TARGET) if targeted and why == "" else "")
	row.get_node("%Pct").text = ResearchBubble.percent_text(p)
	_set_fill(row.get_node("%Fill"), p)


func _wire_research_row(row: Node) -> void:
	(row as Button).pressed.connect(_on_row.bind(row))


func _wire_chip(chip: Node) -> void:
	(chip as Button).pressed.connect(_on_chip.bind(chip))


# The kind handler's own section (agents own its content): refreshed in place when the
# body can (`refresh()`), else rebuilt from `ResearchSystem.make_body`.
func _refresh_kind_body() -> void:
	if _kind_body != null and is_instance_valid(_kind_body) and _kind_body.has_method(&"refresh"):
		_kind_body.call(&"refresh")
		return
	if _kind_body != null and is_instance_valid(_kind_body):
		_kind_body.get_parent().remove_child(_kind_body)
		_kind_body.queue_free()
	_kind_body = ResearchSystem.make_body(_state, _fid) if not _state.is_empty() else null
	%KindSection.visible = _kind_body != null
	if _kind_body == null:
		return
	%KindSlot.add_child(_kind_body)
	if _kind_body.has_signal(&"changed"):
		_kind_body.connect(&"changed", _on_kind_changed, CONNECT_DEFERRED)


# `changed` may carry a payload or not — accept up to two and ignore them.
func _on_kind_changed(_a: Variant = null, _b: Variant = null) -> void:
	_fill()


# ── Handlers ─────────────────────────────────────────────────────────────────
func _on_upgrade() -> void:
	if not _upgrade_armed:
		_upgrade_armed = true
		_fill()
		return
	# A refusal needs no message — the refill shows the reason on the blocked button.
	FacilitySystem.upgrade(_state, _fid)
	_upgrade_armed = false
	_fill()


func _on_assign(row: Node) -> void:
	FacilitySystem.assign(_state, _fid, String(row.get_meta(&"who", "")))
	_upgrade_armed = false
	_fill()


func _on_release() -> void:
	FacilitySystem.unassign(_state, _fid)
	_upgrade_armed = false
	_fill()


func _on_row(row: Node) -> void:
	var rid: String = String(row.get_meta(&"rid", ""))
	var r: Dictionary = ResearchSystem.row(rid)
	_upgrade_armed = false
	if not ResearchSystem.targets(_state, r).is_empty():
		# Targeted: open (or close) its target chips; the chip makes the selection.
		_pending_rid = "" if _pending_rid == rid else rid
	elif String(ResearchSystem.active(_state, _fid).get("rid", "")) != rid:
		ResearchSystem.select(_state, _fid, rid, "")
		_pending_rid = ""
	_fill()


func _on_chip(chip: Node) -> void:
	if _pending_rid != "":
		ResearchSystem.select(_state, _fid, _pending_rid, String(chip.get_meta(&"target", "")))
	_upgrade_armed = false
	_fill()


func _on_stop() -> void:
	ResearchSystem.clear(_state, _fid)
	_pending_rid = ""
	_upgrade_armed = false
	_fill()


# ── Helpers ──────────────────────────────────────────────────────────────────
## A ring icon (`research_ring.gdshader` on a TextureRect): texture, progress, greyed.
static func _ring(rect: TextureRect, icon: Texture2D, ratio: float, grey: bool) -> void:
	rect.texture = icon
	var mat := rect.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter(&"progress", clampf(ratio, 0.0, 1.0))
	mat.set_shader_parameter(&"all_grey", grey)
	mat.set_shader_parameter(&"fill_color", OutgameTheme.ACCENT)
	mat.set_shader_parameter(&"track_color", OutgameTheme.BORDER)


## Progress bar fill: width = ratio of the track (anchor).
static func _set_fill(fill: Control, ratio: float) -> void:
	fill.anchor_right = clampf(ratio, 0.0, 1.0)
	fill.visible = ratio > 0.0


## The scene's sample rows are previews only — drop them before the first fill.
static func _clear(list: Node) -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()


## Keeps exactly `n` rows in `list` (instancing missing ones, wiring them once with `wire`)
## and returns them. Existing rows are reused, so a row whose button is emitting survives.
static func _ensure_rows(list: Node, scene: PackedScene, n: int, wire: Callable) -> Array:
	while list.get_child_count() > n:
		var last: Node = list.get_child(list.get_child_count() - 1)
		list.remove_child(last)
		last.queue_free()
	while list.get_child_count() < n:
		var row: Node = scene.instantiate()
		list.add_child(row)
		if wire.is_valid():
			wire.call(row)
	return list.get_children()


## F6 단독 실행 미리보기 — 메모리 런의 전장 훈련장: 감독을 앉히고 첫 연구를 골라 한 주
## 진행한 시트 본문(`resources/UiPreview.gd`). 시트 없이 서므로 높이 맞추기는 건너뛴다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var state: Dictionary = gm.season_state
	var fid: String = "train_field"
	FacilitySystem.assign(state, fid, FacilitySystem.OCC_MANAGER)
	var avail: Array = ResearchSystem.available(state, fid)
	if not avail.is_empty():
		var r: Dictionary = avail[0]
		var offered: Array = ResearchSystem.targets(state, r)
		ResearchSystem.select(state, fid, String(r["id"]),
				String((offered[0] as Dictionary).get("id", "")) if not offered.is_empty() else "")
		ResearchSystem.tick_week(state)
	bind(null, state, fid)
