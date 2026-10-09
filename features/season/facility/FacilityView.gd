class_name FacilityView
extends Control

# Facility screen (§16, `SeasonHub.Screen.FACILITY`) — opened by tapping a facility (or its
# research bubble) on the hub map: `SeasonHub.open_facility(fid)`. Replaces the old facility
# sheet popup: a full screen that never scrolls as a whole.
#
# **Layout lives in `UI_View_FacilityView.tscn`.** Header: facility icon · name · status line
# (weekly points, or red: nobody seated / week running), the occupant button (portrait + the
# facility stat; tap → `OccupantPicker` modal) and level + upgrade (lit only while
# `FacilitySystem.can_upgrade`; a lit tap asks `ConfirmPopup`, an unlit tap toasts the block
# reason). `%BodySlot` holds the kind body (`ResearchSystem.make_body`, full rect). Bottom bar:
# the body's optional action (left) and back to the hub (right).
#
# **Body contract** (duck typing, README "Body contract"): the body fills `%BodySlot` (full-rect
# anchors) and scrolls inside itself only. Optional members:
#   refresh()                       — called after the header changed (seat, upgrade)
#   signal changed                  — the body changed state → the header refreshes
#   signal message(text: String)    — shown as this screen's toast
#   bottom_action_text() -> String  — label of the bar's left slot ("" = slot hidden)
#   on_bottom_action()              — that slot was pressed
# Research selection stays HUB-only: bodies read `ResearchSystem.can_select(state)`.

const SCENE_PATH: String = "res://features/season/facility/UI_View_FacilityView.tscn"
const TOAST_SECONDS: float = 2.5

@onready var _hub: SeasonHub = get_parent() as SeasonHub

var _state: Dictionary = {}
var _fid: String = ""
var _body: Control = null
var _built: bool = false
var _confirm: ConfirmPopup = null


## Instantiates the scene. `FacilityView.new()` is an empty Control — don't use it.
## Load (not preload) — preloading its own scene is a script ↔ scene cycle.
static func create() -> FacilityView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as FacilityView


func _ready() -> void:
	_bind()
	if UiPreview.is_standalone(self):
		_fill_preview()


func _bind() -> void:
	if _built:
		return
	_built = true
	ScreenMetrics.indent_to_safe_top(self)
	ScreenMetrics.extend_background(%Background)
	OutgameTheme.fit_bottom_bar(%BottomBar, %SafeBottom)
	%Toast.visible = false
	%Occupant.pressed.connect(_on_occupant)
	%Upgrade.pressed.connect(_on_upgrade)
	%Action.pressed.connect(_on_action)
	%Back.pressed.connect(_on_back)


## Shows facility `fid` of the run `state` (the body is rebuilt for the facility).
func show_facility(state: Dictionary, fid: String) -> void:
	_bind()
	_state = state
	_fid = fid
	%Toast.visible = false
	_set_body(ResearchSystem.make_body(state, fid))
	refresh()


func current_fid() -> String:
	return _fid


## Header + the body's own `refresh()` + the bar's body action.
func refresh() -> void:
	if _fid == "":
		return
	_fill_header()
	if _body != null and is_instance_valid(_body) and _body.has_method(&"refresh"):
		_body.call(&"refresh")
	_fill_action()


## A short line above the bottom bar for a few seconds (block reasons, body messages).
func toast(msg: String) -> void:
	var box: Control = %Toast
	var t: Label = %ToastText
	t.text = msg
	box.visible = true
	var tween := create_tween()
	tween.tween_interval(TOAST_SECONDS)
	tween.tween_callback(func() -> void:
		if t.text == msg:
			box.visible = false)


# ── Fill ─────────────────────────────────────────────────────────────────────
func _fill_header() -> void:
	var state: Dictionary = _state
	var fid: String = _fid
	(%Icon as TextureRect).texture = FacilitySystem.icon_of(fid)
	%Title.text = FacilitySystem.facility_name(fid)
	var status: Label = %Status
	var occ: String = FacilitySystem.occupant(state, fid)
	if occ == FacilitySystem.OCC_NONE:
		status.text = Loc.t(L.FACILITY_UI_SHEET_RATE_NONE)
		status.theme_type_variation = &"NegativeLabel"
	elif not ResearchSystem.can_select(state):
		status.text = Loc.t(L.FACILITY_UI_LOCKED)
		status.theme_type_variation = &"CaptionLabel"
	elif ResearchSystem.rows_for(fid).is_empty():
		status.text = ""
	else:
		status.text = Loc.t(L.FACILITY_UI_SHEET_RATE, {"points": ResearchSystem.weekly_points(state, fid)})
		status.theme_type_variation = &"AccentLabel"

	# Occupant button: portrait, name, the facility stat at the bottom.
	var stat_name: String = StaffSystem.stat_label(FacilitySystem.stat_of(fid))
	(%OccPortrait as TextureRect).texture = StaffImages.portrait(occ) if occ != FacilitySystem.OCC_NONE else null
	%OccName.text = FacilitySystem.occupant_name(state, fid)
	var occ_stat: Label = %OccStat
	occ_stat.text = Loc.t(L.FACILITY_UI_OCC_VALUE, {"stat": stat_name,
			"value": FacilitySystem.stat_value(state, fid)})
	occ_stat.theme_type_variation = &"NegativeLabel" if occ == FacilitySystem.OCC_NONE else &"AccentLabel"

	# Level + upgrade: lit only when it can go now.
	var lvl: int = FacilitySystem.level(state, fid)
	var top: int = FacilitySystem.max_level()
	%Level.text = Loc.t(L.FACILITY_UI_VIEW_LEVEL, {"level": lvl, "max": top})
	var up: Button = %Upgrade
	var can: bool = FacilitySystem.can_upgrade(state, fid)
	up.theme_type_variation = &"PrimaryButton" if can else &"GhostButton"
	up.text = Loc.t(L.UI_WORD_MAX_LEVEL) if lvl >= top else Loc.t(L.FACILITY_UI_VIEW_UPGRADE)
	up.disabled = lvl >= top


func _fill_action() -> void:
	var text: String = ""
	if _body != null and is_instance_valid(_body) and _body.has_method(&"bottom_action_text"):
		text = String(_body.call(&"bottom_action_text"))
	%Action.text = text
	%Action.visible = text != ""


func _set_body(b: Control) -> void:
	if _body != null and is_instance_valid(_body):
		_body.get_parent().remove_child(_body)
		_body.queue_free()
	_body = b
	if b == null:
		return
	%BodySlot.add_child(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if b.has_signal(&"changed"):
		b.connect(&"changed", _on_body_changed, CONNECT_DEFERRED)
	if b.has_signal(&"message"):
		b.connect(&"message", toast)


# ── Handlers ─────────────────────────────────────────────────────────────────
func _on_occupant() -> void:
	var p := OccupantPicker.open(self, _state, _fid)
	p.changed.connect(refresh)


func _on_upgrade() -> void:
	var why: String = FacilitySystem.upgrade_block_reason(_state, _fid)
	if why != "":
		toast(why)
		return
	if _confirm == null:
		_confirm = ConfirmPopup.create()
		add_child(_confirm)
		_confirm.confirmed.connect(_on_upgrade_confirmed)
	var lvl: int = FacilitySystem.level(_state, _fid)
	_confirm.open(Loc.t(L.FACILITY_UI_VIEW_UPGRADE_TITLE, {"facility": FacilitySystem.facility_name(_fid)}),
			Loc.t(L.FACILITY_UI_VIEW_UPGRADE_BODY, {"from": lvl, "to": lvl + 1,
				"cost": FinanceSystem.fmt(FacilitySystem.upgrade_cost(_state, _fid)),
				"available": FinanceSystem.fmt(FinanceSystem.upgrade_funds(_state))}),
			Loc.t(L.UI_BUTTON_CANCEL), Loc.t(L.FACILITY_UI_VIEW_UPGRADE))


func _on_upgrade_confirmed() -> void:
	var why: String = FacilitySystem.upgrade(_state, _fid)
	if why != "":
		toast(why)
	refresh()


func _on_body_changed(_a: Variant = null, _b: Variant = null) -> void:
	_fill_header()
	_fill_action()


func _on_action() -> void:
	if _body != null and is_instance_valid(_body) and _body.has_method(&"on_bottom_action"):
		_body.call(&"on_bottom_action")


func _on_back() -> void:
	if _hub != null:
		_hub.goto(SeasonHub.Screen.HUB)


## F6 단독 실행 미리보기 — 메모리 런의 전력 분석실 화면. "허브로" 는 호스트가 없어 출력만.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	UiPreview.trace(%Back.pressed, "back")
	show_facility(gm.season_state, "intel")
