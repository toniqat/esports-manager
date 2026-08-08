class_name CardTargetingOverlay
extends Node

# Modal targeting UI for cards that pick a pilot, a cell, or confirm a
# caster-centred area (engage). Owned by BattleSim; activated from
# CardPhaseManager._play_card_direct after the played card's CardData is
# inspected for a target requirement. While active:
#   • PILOT mode      — battlefield tiles are dimmed; only valid pilots stay
#                       at full brightness. Click on a valid pilot's cell
#                       resolves the target.
#   • LOCATION mode   — pilots are dimmed; tiles stay normal and valid cells
#                       are outlined. Click on a valid cell resolves it.
#   • PREVIEW mode    — engage card pre-flight. The caster's hex area is
#                       highlighted, the participating pilots are listed in
#                       a side panel, and the player presses 확인 to launch
#                       the engage modal (or 취소 to refund).
# Cancel always restores the pre-play snapshot via the on_cancel callback.

enum Mode { NONE, PILOT, LOCATION, PREVIEW, SELECTION_PREVIEW }

# ─── State ────────────────────────────────────────────────────────────────────
var mode: int = Mode.NONE

# Public read-only state read by BattleRenderer / tiles_layer modulate.
var valid_pilots: Dictionary = {}    # PilotData    → true
var valid_cells:  Dictionary = {}    # Vector2i     → true
var area_cells:   Dictionary = {}    # Vector2i     → true (PREVIEW area)
var preview_caster: PilotData = null
var preview_participants: Array = []  # PilotData (engage participants)
# Range info for PILOT / LOCATION modes — drives the in-range tile highlight
# and the out-of-range black dim drawn by BattleRenderer.
var range_caster: PilotData = null
var range_radius: int = 0

# PILOT / LOCATION pending pick — set when the player clicks a valid target
# but has not yet pressed 확인. Fires _on_complete only after confirmation.
# Holds either PilotData (PILOT mode) or Vector2i (LOCATION mode).
var pending_pick: Variant = null

var _bs: BattleSim = null
var _on_complete: Callable = Callable()
var _on_cancel:   Callable = Callable()

# ─── UI consts ───────────────────────────────────────────────────────────────
const BTN_W            := 180.0
const BTN_H            := 56.0
# Buttons sit just above the hand row's top edge (BS_HAND_CENTER.y), aligned
# right so they hover at the top-right corner of the hand area.
const BTN_HAND_GAP     := 10.0
const BTN_SIDE_MARGIN  := 24.0
const CONFIRM_BTN_GAP  := 12.0
# 좌/우 팀 패널 — 좌측에 플레이어 팀, 우측에 적 팀.
# 패널 하단(=TEAM_PANEL_Y + TEAM_PANEL_H)이 핸드 위 cancel/confirm 버튼
# 상단(BS_HAND_CENTER.y - BTN_HAND_GAP - BTN_H ≈ 1434)을 침범하지 않도록
# 1200 까지만 확장한다. 행 16개 정도까지는 안전.
const TEAM_PANEL_W     := 300.0
const TEAM_PANEL_H     := 1200.0
const TEAM_PANEL_Y     := 200.0
const TEAM_PANEL_MARGIN := 20.0   # 화면 가장자리에서의 여백
const TEAM_ROW_H        := 70.0
const TEAM_ROW_GAP      := 8.0
const TEAM_ROW_IMG_SIZE := 56.0

# ─── UI refs ─────────────────────────────────────────────────────────────────
var _ui_layer:    CanvasLayer = null
var _btn_cancel:  Button = null
var _btn_confirm: Button = null
# 좌/우 팀 패널. 각각 0=플레이어팀, 1=적팀의 참여 파일럿 목록을 표시.
var _team_panels: Array = [null, null]


func _ready() -> void:
	# Layer above HUD (CardSelectOverlay uses 10) so cancel/confirm sit on top
	# of cost bars and the description box.
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 11
	add_child(_ui_layer)


# Bind step so the overlay does not need to know its parent type at construction.
func bind(bs: BattleSim) -> void:
	_bs = bs


# ─── State accessors (read by renderer / tiles_layer / play path) ────────────
# A modal targeting session blocks input and gates can_end_card_phase. The
# non-modal SELECTION_PREVIEW mode (shown while a card is selected in hand)
# only affects the renderer — the player can still click hand cards and
# 단계 넘기기. is_active() therefore reports modal-only; renderers read
# is_visualizing() to decide whether to draw range overlays.
func is_active() -> bool:
	return mode != Mode.NONE and mode != Mode.SELECTION_PREVIEW


func is_visualizing() -> bool:
	return mode != Mode.NONE


# Tiles are no longer dimmed via the global tilemap modulate — BattleRenderer
# now draws per-cell black overlays on cells outside the cast range.
func should_dim_tiles() -> bool:
	return false


# Non-valid pilots are dimmed in PILOT mode; ALL pilots are dimmed in LOCATION.
# In PREVIEW, participating pilots stay bright and others dim.
func should_dim_pilot(p: PilotData) -> bool:
	match mode:
		Mode.PILOT:
			return not valid_pilots.has(p)
		Mode.LOCATION:
			return true
		Mode.PREVIEW:
			return not (p in preview_participants)
		_:
			return false


# Cells inside the highlighted "range" area (LOCATION / PILOT use the caster's
# cast_range; PREVIEW uses the engage area). Used by BattleRenderer to:
#  • highlight in-range cells with a soft yellow fill, and
#  • black-dim every other valid grid cell.
func is_in_range_cell(cell: Vector2i) -> bool:
	if mode == Mode.PREVIEW:
		return area_cells.has(cell)
	if range_caster == null or range_radius <= 0:
		return false
	if cell == range_caster.grid_pos:
		return true
	var d: int = _bs.hex_grid.hex_distance(range_caster.grid_pos, cell)
	return d > 0 and d <= range_radius


# A valid target cell? — used by BattleRenderer to draw the cell outline.
func is_valid_cell(cell: Vector2i) -> bool:
	return mode == Mode.LOCATION and valid_cells.has(cell)


# A cell inside the engage preview area? — drawn with a softer fill.
func is_area_cell(cell: Vector2i) -> bool:
	return mode == Mode.PREVIEW and area_cells.has(cell)


# ─── Entry points ────────────────────────────────────────────────────────────
func start_pilot_target(valid: Array, caster: PilotData, max_r: int,
		on_complete: Callable, on_cancel: Callable) -> void:
	if valid.is_empty():
		# Nothing to pick — fall through as cancel; caller refunds.
		on_cancel.call()
		return
	_clear_visual_state()
	mode = Mode.PILOT
	valid_pilots.clear()
	for raw in valid:
		valid_pilots[raw as PilotData] = true
	range_caster = caster
	range_radius = max_r
	pending_pick = null
	_on_complete = on_complete
	_on_cancel   = on_cancel
	_build_cancel_button()
	# Confirm sits next to Cancel from the start; disabled until a valid
	# target is clicked. Lets the player see both buttons up front so the
	# 확인 step doesn't surprise them.
	_build_confirm_button()
	_btn_confirm.disabled = true
	_disable_phase_button()
	_request_redraw()


func start_location_target(valid: Array, caster: PilotData, max_r: int,
		on_complete: Callable, on_cancel: Callable) -> void:
	if valid.is_empty():
		on_cancel.call()
		return
	_clear_visual_state()
	mode = Mode.LOCATION
	valid_cells.clear()
	for c in valid:
		valid_cells[c as Vector2i] = true
	range_caster = caster
	range_radius = max_r
	pending_pick = null
	_on_complete = on_complete
	_on_cancel   = on_cancel
	_build_cancel_button()
	_build_confirm_button()
	_btn_confirm.disabled = true
	_disable_phase_button()
	_request_redraw()


# ─── Selection preview (non-modal) ───────────────────────────────────────────
# Called by CardPhaseManager._select_card so the same yellow range fill /
# engage area shown in modal targeting also appears while the player is just
# inspecting the card in their hand. No buttons are built and no input is
# captured — the player can still click 카드 내기 / 단계 넘기기 / outside.
func start_selection_preview(cd: CardData) -> void:
	clear_selection_preview()
	if cd == null:
		return
	var caster: PilotData = cd.owner_pilot
	var kind: String = ""
	if _bs.card_phase != null:
		kind = _bs.card_phase._targeting_kind(cd)
	if kind == "" or kind == "none" or caster == null:
		return
	mode = Mode.SELECTION_PREVIEW
	range_caster = caster
	range_radius = max(0, cd.cast_range)
	preview_caster = caster
	if kind == "pilot":
		var team_filter: int = 1 if cd.target == "enemy" else 0
		var valid := _bs.card_phase._compute_valid_pilot_targets(cd, caster, team_filter)
		for raw in valid:
			valid_pilots[raw as PilotData] = true
	elif kind == "location":
		var valid_cells_arr := _bs.card_phase._compute_valid_location_targets(cd, caster)
		for c in valid_cells_arr:
			valid_cells[c as Vector2i] = true
	elif kind == "preview":
		var area := _bs.card_phase._compute_engage_area(caster)
		for c in area:
			area_cells[c as Vector2i] = true
		var exclude_lane: bool = _bs.card_phase._has_clause_flag(
				cd.effect, "engage", "exclude_lane")
		preview_participants = _bs.card_phase._compute_engage_participants(
				caster, area, exclude_lane)
	_request_redraw()


# Drops the non-modal preview state. Called when the player deselects a card
# (or selects a different one). No-op when a modal session is active —
# start_*_target clears state on entry.
func clear_selection_preview() -> void:
	if mode != Mode.SELECTION_PREVIEW:
		return
	_clear_visual_state()
	_request_redraw()


# Common reset helper used by start_pilot_target / start_location_target /
# start_preview / clear_selection_preview before stamping new state. Does
# NOT touch button refs — the modal entry points decide whether to rebuild.
func _clear_visual_state() -> void:
	mode = Mode.NONE
	valid_pilots.clear()
	valid_cells.clear()
	area_cells.clear()
	preview_caster = null
	preview_participants.clear()
	range_caster = null
	range_radius = 0
	pending_pick = null


# Engage preview — caster cell + radius-1 neighbours are the area, the listed
# `participants` are the pilots that would actually fight. The player must
# 확인 to launch the engage, or 취소 to refund.
# `card_label`는 좌/우 팀 패널 디자인으로 바뀌면서 더 이상 표시하지 않지만,
# 호출 측 호환을 위해 시그니처에 남겨둔다.
func start_preview(caster: PilotData, area: Array, participants: Array,
		_card_label: String,
		on_complete: Callable, on_cancel: Callable) -> void:
	_clear_visual_state()
	mode = Mode.PREVIEW
	preview_caster = caster
	area_cells.clear()
	for c in area:
		area_cells[c as Vector2i] = true
	preview_participants = participants.duplicate()
	_on_complete = on_complete
	_on_cancel   = on_cancel
	_build_cancel_button()
	_build_confirm_button()
	_build_team_panels()
	_disable_phase_button()
	_request_redraw()


# ─── Cancel / confirm handlers ───────────────────────────────────────────────
func _on_cancel_pressed() -> void:
	var cb := _on_cancel
	_teardown()
	if cb.is_valid():
		cb.call()


func _on_confirm_pressed() -> void:
	if mode == Mode.PREVIEW:
		var cb := _on_complete
		_teardown()
		if cb.is_valid():
			cb.call()
		return
	if mode == Mode.PILOT or mode == Mode.LOCATION:
		# Confirm only fires once a target was clicked — button is otherwise
		# disabled in start_*_target / _set_pending_pick.
		if pending_pick == null:
			return
		var picked: Variant = pending_pick
		var cb_ploc := _on_complete
		_teardown()
		if cb_ploc.is_valid():
			cb_ploc.call(picked)


# Click hit-testing for PILOT and LOCATION modes. Skipped if a Button or other
# Control consumed the event. Clicking a valid target now stores it as the
# pending pick (highlighted by BattleRenderer); the play only fires when the
# player presses 확인.
func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.NONE or mode == Mode.PREVIEW or mode == Mode.SELECTION_PREVIEW:
		return
	var pressed: bool = false
	var pos: Vector2 = Vector2.ZERO
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pressed = true
			pos = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch and event.pressed:
		pressed = true
		pos = (event as InputEventScreenTouch).position
	if not pressed:
		return
	if mode == Mode.PILOT:
		# Click lands on the pilot's drawn marker (offset above/below the
		# tile). _hit_test_pilot inspects the marker positions directly so a
		# tap on the marker registers even when it sits in a neighbouring cell
		# from the tile-centre's perspective.
		var picked := _hit_test_pilot(pos)
		if picked == null:
			return
		_set_pending_pick(picked)
	elif mode == Mode.LOCATION:
		var cell := _hit_test_cell(pos)
		if cell == Vector2i(-2147483648, -2147483648):
			return
		if not valid_cells.has(cell):
			return
		_set_pending_pick(cell)


# Stores the clicked target as the pending pick, enables the 확인 button,
# and triggers a redraw so the renderer can highlight the chosen pilot/cell.
func _set_pending_pick(target: Variant) -> void:
	pending_pick = target
	if _btn_confirm != null and is_instance_valid(_btn_confirm):
		_btn_confirm.disabled = false
	_request_redraw()


# Closest cell whose centre is within hex_size of `pos`. Returns a sentinel
# value when nothing is close enough. Used by LOCATION mode only.
func _hit_test_cell(pos: Vector2) -> Vector2i:
	var best: Vector2i = Vector2i(-2147483648, -2147483648)
	var best_d: float = INF
	var hex_size: float = (_bs.hex_grid as HexGrid).hex_size
	for c_raw in valid_cells.keys():
		var c := c_raw as Vector2i
		var centre := _bs.cell_center(c)
		var d := centre.distance_to(pos)
		if d < best_d and d <= hex_size:
			best_d = d
			best = c
	return best


# PILOT mode hit test — picks the valid pilot whose drawn marker is closest
# to the click position. We probe both the tile centre (solo render position)
# and the team-direction offset position (offset render when stacked) so a
# tap on the visible marker always resolves regardless of how
# BattleRenderer ended up laying out the cell.
func _hit_test_pilot(pos: Vector2) -> PilotData:
	var best: PilotData = null
	var best_d: float = INF
	var hex_size: float = (_bs.hex_grid as HexGrid).hex_size
	# Slightly looser than half a tile so the click area covers the visible
	# marker circle (~31.5 px radius at default scale).
	var max_r: float = hex_size * 0.85
	for raw in valid_pilots.keys():
		var p := raw as PilotData
		if not p.alive:
			continue
		var probes: Array = [
			_bs.cell_center(p.grid_pos),
			_bs.pilot_marker_pos_solo(p),
		]
		for probe_v in probes:
			var d := (probe_v as Vector2).distance_to(pos)
			if d < best_d and d <= max_r:
				best_d = d
				best = p
	return best


# ─── UI construction ─────────────────────────────────────────────────────────
# Buttons hover at the top-right of the hand area so they sit next to where
# the player's eye already is when picking a card. The y is computed from
# BS_HAND_CENTER.y (top of the hand row) so the layout follows any future
# hand-row movement automatically.
func _btn_top_y() -> float:
	return _bs.BS_HAND_CENTER.y - BTN_HAND_GAP - BTN_H


func _build_cancel_button() -> void:
	_btn_cancel = _make_btn("취소")
	var cancel_x: float = 1080.0 - BTN_SIDE_MARGIN - BTN_W
	_btn_cancel.position = Vector2(cancel_x, _btn_top_y())
	_btn_cancel.pressed.connect(_on_cancel_pressed)
	_ui_layer.add_child(_btn_cancel)


func _build_confirm_button() -> void:
	_btn_confirm = _make_btn("확인")
	var cancel_x: float = 1080.0 - BTN_SIDE_MARGIN - BTN_W
	_btn_confirm.position = Vector2(cancel_x - CONFIRM_BTN_GAP - BTN_W, _btn_top_y())
	_btn_confirm.pressed.connect(_on_confirm_pressed)
	_ui_layer.add_child(_btn_confirm)


func _make_btn(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 24)
	b.size = Vector2(BTN_W, BTN_H)
	return b


# 좌/우 팀 패널을 빌드한다. 좌측에 플레이어팀(0), 우측에 적팀(1) 참여
# 파일럿을 파일럿 이미지 + HP 텍스트 + HP 프로그레스 바로 표시한다.
# PREVIEW 모드 전용 (SELECTION_PREVIEW에서는 호출하지 않음).
func _build_team_panels() -> void:
	# 참여자 팀별 그룹화 + 역할 정렬.
	var by_team: Array = [[], []]
	for raw in preview_participants:
		var p := raw as PilotData
		(by_team[p.team] as Array).append(p)
	for t in range(2):
		(by_team[t] as Array).sort_custom(func(a: PilotData, b: PilotData) -> bool:
			return a.role < b.role)

	var team_titles: Array = ["아군", "적군"]
	var team_colors: Array = [
		Color(0.32, 0.62, 0.95),
		Color(0.95, 0.40, 0.32),
	]
	# 화면 X 좌표: 좌측 패널 = MARGIN, 우측 패널 = 화면 폭 - PANEL_W - MARGIN
	var screen_w: float = 1080.0
	var xs: Array = [
		TEAM_PANEL_MARGIN,
		screen_w - TEAM_PANEL_W - TEAM_PANEL_MARGIN,
	]
	for t in range(2):
		_team_panels[t] = _build_one_team_panel(
				team_titles[t] as String,
				team_colors[t] as Color,
				by_team[t] as Array,
				xs[t] as float)


# 한쪽 팀의 파일럿 목록을 담는 단일 패널을 만들어 _ui_layer 의 자식으로
# 추가하고 인스턴스를 반환.
func _build_one_team_panel(title_text: String, accent: Color,
		pilots: Array, x: float) -> Panel:
	var panel := Panel.new()
	panel.position = Vector2(x, TEAM_PANEL_Y)
	panel.size = Vector2(TEAM_PANEL_W, TEAM_PANEL_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.18, 0.94)
	sb.border_color = accent
	sb.border_width_top    = 2
	sb.border_width_bottom = 2
	sb.border_width_left   = 2
	sb.border_width_right  = 2
	sb.corner_radius_top_left     = 12
	sb.corner_radius_top_right    = 12
	sb.corner_radius_bottom_left  = 12
	sb.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", sb)
	_ui_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   = 12
	vbox.offset_top    = 12
	vbox.offset_right  = -12
	vbox.offset_bottom = -12
	vbox.add_theme_constant_override("separation", TEAM_ROW_GAP)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "%s (%d)" % [title_text, pilots.size()]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", accent)
	vbox.add_child(title)

	if pilots.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "참여자 없음"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 16)
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		vbox.add_child(empty_lbl)
		return panel

	for raw in pilots:
		var p := raw as PilotData
		vbox.add_child(_build_pilot_row(p, accent))
	return panel


# 한 명의 파일럿 row (이미지 + 라벨 + HP 텍스트 + HP 바). 팀 패널의 vbox에
# 자식으로 추가될 컨트롤을 반환.
func _build_pilot_row(p: PilotData, accent: Color) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0.0, TEAM_ROW_H)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 좌측 이미지 박스. PilotImages.face_for 가 직사각형 face 텍스처를 돌려준다.
	var img_box := TextureRect.new()
	img_box.position = Vector2(0.0, (TEAM_ROW_H - TEAM_ROW_IMG_SIZE) * 0.5)
	img_box.size = Vector2(TEAM_ROW_IMG_SIZE, TEAM_ROW_IMG_SIZE)
	img_box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img_box.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img_box.texture = PilotImages.face_for(p.pilot_id)
	row.add_child(img_box)

	# 우측 정보 컬럼 (이름 + HP 텍스트 + HP 바).
	var info_x: float = TEAM_ROW_IMG_SIZE + 10.0
	var info_w: float = TEAM_PANEL_W - 24.0 - info_x   # 패널 padding 24 보정
	var name_lbl := Label.new()
	name_lbl.text = _bs.pilot_label(p)
	name_lbl.position = Vector2(info_x, 4.0)
	name_lbl.size = Vector2(info_w, 24.0)
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", accent)
	row.add_child(name_lbl)

	var hp_text := Label.new()
	hp_text.text = "HP %d / %d" % [p.hp, p.max_hp]
	hp_text.position = Vector2(info_x, 28.0)
	hp_text.size = Vector2(info_w, 20.0)
	hp_text.add_theme_font_size_override("font_size", 14)
	hp_text.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	row.add_child(hp_text)

	# HP 프로그레스 바.
	var bar_h: float = 8.0
	var bar_y: float = 52.0
	var bar_bg := ColorRect.new()
	bar_bg.position = Vector2(info_x, bar_y)
	bar_bg.size = Vector2(info_w, bar_h)
	bar_bg.color = Color(0.06, 0.06, 0.08, 1.0)
	row.add_child(bar_bg)
	var ratio: float = 0.0
	if p.max_hp > 0:
		ratio = clamp(float(p.hp) / float(p.max_hp), 0.0, 1.0)
	var bar_fill := ColorRect.new()
	bar_fill.position = bar_bg.position
	bar_fill.size = Vector2(info_w * ratio, bar_h)
	bar_fill.color = Color(0.30, 0.85, 0.45, 1.0)
	row.add_child(bar_fill)

	return row


# Locks the 전략 포인트 도넛 while targeting owns the screen so the player
# can't flip it into 턴 넘기기 and bypass the pending play. The donut stays
# visible — the point readout is still useful while picking a target.
func _disable_phase_button() -> void:
	if _bs.cost_donut == null:
		return
	_bs.cost_donut.set_locked(true)


func _restore_phase_button() -> void:
	if _bs.cost_donut == null:
		return
	_bs.cost_donut.set_locked(false)


# ─── Teardown ────────────────────────────────────────────────────────────────
func _teardown() -> void:
	_clear_visual_state()
	if _btn_cancel != null and is_instance_valid(_btn_cancel):
		_btn_cancel.queue_free()
	_btn_cancel = null
	if _btn_confirm != null and is_instance_valid(_btn_confirm):
		_btn_confirm.queue_free()
	_btn_confirm = null
	for i in range(_team_panels.size()):
		var pn = _team_panels[i]
		if pn != null and is_instance_valid(pn):
			(pn as Panel).queue_free()
		_team_panels[i] = null
	_on_complete = Callable()
	_on_cancel   = Callable()
	_restore_phase_button()
	_request_redraw()


# Force tile + battlefield redraws so dim state takes effect immediately.
# The tilemap modulate stays at the default (WHITE) — per-cell black dim is
# now drawn by BattleRenderer for cells outside the targeting range.
func _request_redraw() -> void:
	if _bs.tiles_layer != null:
		_bs.tiles_layer.modulate = Color.WHITE
	if _bs.renderer != null:
		_bs.renderer.queue_redraw()
