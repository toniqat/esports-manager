class_name CardTargetingOverlay
extends Node

# 핸드에서 카드를 고르는 순간 켜지는 **대상 지정 오버레이**.
#
# 예전에는 카드를 고른 뒤 설명 상자의 "카드 내기"를 눌러야 비로소 모달 대상
# 지정이 열렸다. 지금은 **카드 선택 자체가 대상 지정 단계**다 — 카드를 드는
# 순간 사거리 밖 타일이 딤드되고, 대상을 찍은 뒤 좌하단 확인을 눌러야 카드가
# 소비된다. 모달이 아니므로 핸드 클릭(다른 카드로 갈아타기)과 턴 넘기기는
# 그대로 살아 있다.
#
#   • PILOT    — 사거리 안 타일은 노란 채움, 그 밖은 검은 딤. 유효 대상이
#                아닌 파일럿은 마커 단위로 딤드된다. 파일럿 초상(마커)을
#                눌러 대상을 지정하면 시안 링이 붙는다.
#   • LOCATION — 같은 사거리 표시 + 유효 셀에 초록 외곽선. 셀을 눌러 지정.
#   • PREVIEW  — 전투 개시류. 시전자 셀 + 인접 6칸이 영역이고 좌/우에 참여
#                파일럿 패널이 뜬다. 따로 찍을 대상이 없으므로 확인은 처음부터
#                활성.
#   • INSTANT  — 대상이 없는 카드. 전장 표시는 하나도 없고 확인만 뜬다.
#
# 확인 / 취소는 화면 **우하단**(Discard 카운터 바로 위)에 나란히 뜬다. 확인을
# 누르기 전까지는 비용도 빠지지 않고 카드도 핸드에 그대로 있으므로, 취소는
# 되돌릴 게 없다 — 그냥 선택 해제다. (버리기 / 찾기 카드의 스냅샷 환불 경로는
# CardSelectOverlay 쪽에 그대로 남아 있다.)

enum Mode { NONE, INSTANT, PILOT, LOCATION, PREVIEW }

# ─── State ────────────────────────────────────────────────────────────────────
var mode: int = Mode.NONE

# Public read-only state read by BattleRenderer.
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
# but has not yet pressed 확인. Holds either PilotData or Vector2i.
var pending_pick: Variant = null

var _bs: BattleSim = null
var _on_confirm: Callable = Callable()
var _on_cancel:  Callable = Callable()
# CardPhaseManager 가 "비용/시전자 생존/유효 대상"을 판정해 내려주는 값.
# 확인 버튼은 이 값 AND 대상 지정 완료일 때만 활성화된다.
var _play_allowed: bool = false

# ─── UI consts ───────────────────────────────────────────────────────────────
const BTN_W            := 180.0
const BTN_H            := 56.0
# 버튼 행은 핸드 행 바로 위에 뜬다. HudBuilder 가 이 두 상수로 전략 포인트
# 도넛의 세로 위치를 잡으므로(도넛이 버튼 띠를 덮지 않도록) 이름을 유지한다.
const BTN_HAND_GAP     := 10.0
const BTN_SIDE_MARGIN  := 24.0
const CONFIRM_BTN_GAP  := 12.0
# 좌/우 팀 패널 — 좌측에 플레이어 팀, 우측에 적 팀.
# 패널 하단(=TEAM_PANEL_Y + TEAM_PANEL_H)이 확인/취소 버튼 상단
# (BS_HAND_CENTER.y - BTN_HAND_GAP - BTN_H ≈ 1434)을 침범하지 않도록
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
	# Layer above HUD (CardSelectOverlay uses 10) so 확인/취소 sit on top of the
	# cost donut and the description box.
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 11
	add_child(_ui_layer)


# Bind step so the overlay does not need to know its parent type at construction.
func bind(bs: BattleSim) -> void:
	_bs = bs


# ─── State accessors (read by renderer / play path) ──────────────────────────
# There is no modal state any more: selecting a card never blocks the hand or
# 턴 넘기기. BattleRenderer asks is_visualizing() to decide whether to paint
# the range fill and the out-of-range dim — INSTANT cards have neither.
func is_visualizing() -> bool:
	return mode == Mode.PILOT or mode == Mode.LOCATION or mode == Mode.PREVIEW


## True while a card is lifted in hand with this overlay live (any kind).
func is_selecting() -> bool:
	return mode != Mode.NONE


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


## 대상 지정이 끝났는가. PILOT / LOCATION 만 실제로 찍어야 하고, PREVIEW 와
## INSTANT 는 고른 즉시 확정 가능하다.
func has_required_pick() -> bool:
	if mode == Mode.PILOT or mode == Mode.LOCATION:
		return pending_pick != null
	return mode != Mode.NONE


# ─── Entry point ─────────────────────────────────────────────────────────────
## 핸드에서 카드를 고른 순간 CardPhaseManager._select_card 가 호출한다.
## `on_confirm` 은 확인 시 `Variant`(PilotData / Vector2i / null) 하나를 받고,
## `on_cancel` 은 인자 없이 호출된다. 둘 다 오버레이가 스스로 정리된 뒤에
## 불리므로 콜백 안에서 다시 선택을 걸어도 안전하다.
func start_card_selection(cd: CardData, on_confirm: Callable,
		on_cancel: Callable) -> void:
	_clear_visual_state()
	_free_ui()
	if cd == null:
		return
	var caster: PilotData = cd.owner_pilot
	var kind: String = ""
	if _bs.card_phase != null:
		kind = _bs.card_phase.targeting_kind(cd)
	# 시전자가 없는 레거시 카드는 대상 지정 자체가 성립하지 않으므로 INSTANT
	# 취급 — 확인 버튼만 뜬다.
	if caster == null:
		kind = "none"
	match kind:
		"pilot":
			mode = Mode.PILOT
			range_caster = caster
			range_radius = max(0, cd.cast_range)
			var team_filter: int = 1 if cd.target == "enemy" else 0
			for raw in _bs.card_phase.compute_valid_pilot_targets(cd, caster, team_filter):
				valid_pilots[raw as PilotData] = true
		"location":
			mode = Mode.LOCATION
			range_caster = caster
			range_radius = max(1, cd.cast_range)
			for c in _bs.card_phase.compute_valid_location_targets(cd, caster):
				valid_cells[c as Vector2i] = true
		"preview":
			mode = Mode.PREVIEW
			preview_caster = caster
			var area := _bs.card_phase.compute_engage_area(caster)
			for c in area:
				area_cells[c as Vector2i] = true
			var exclude_lane: bool = _bs.card_phase.has_clause_flag(
					cd.effect, "engage", "exclude_lane")
			preview_participants = _bs.card_phase.compute_engage_participants(
					caster, area, exclude_lane)
			_build_team_panels()
		_:
			mode = Mode.INSTANT
	_on_confirm = on_confirm
	_on_cancel  = on_cancel
	_play_allowed = false
	_build_buttons()
	_request_redraw()


## 선택 해제 — 아직 비용도 카드도 건드리지 않았으므로 되돌릴 상태가 없다.
## 콜백은 부르지 않는다(호출 측이 이미 정리 중일 때 재진입하지 않도록).
## 이미 꺼져 있으면 no-op.
func clear_selection() -> void:
	if mode == Mode.NONE and _btn_confirm == null:
		return
	_teardown()


## CardPhaseManager 가 "비용 / 시전자 생존 / 유효 대상" 판정 결과를 내려준다.
## 확인 버튼은 이 값과 has_required_pick() 이 둘 다 참일 때만 눌린다.
func set_play_allowed(allowed: bool) -> void:
	_play_allowed = allowed
	_refresh_confirm_disabled()


# ─── Cancel / confirm handlers ───────────────────────────────────────────────
func _on_cancel_pressed() -> void:
	var cb := _on_cancel
	_teardown()
	if cb.is_valid():
		cb.call()


func _on_confirm_pressed() -> void:
	if not _play_allowed or not has_required_pick():
		return
	var picked: Variant = pending_pick
	var cb := _on_confirm
	_teardown()
	if cb.is_valid():
		cb.call(picked)


# Click hit-testing for PILOT and LOCATION modes. A press anywhere on the
# battlefield is consumed while one of those two kinds is live: a hit sets the
# pending pick, a miss is simply swallowed. Swallowing the miss is deliberate —
# CardPhaseManager._unhandled_input would otherwise read a slightly-off tap as
# "clicked outside" and drop the selection (and the pick with it). Getting out
# is the 취소 button, a re-click on the card, or picking another card.
func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.PILOT and mode != Mode.LOCATION:
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
	get_viewport().set_input_as_handled()
	if mode == Mode.PILOT:
		# Click lands on the pilot's drawn marker (offset above/below the
		# tile). _hit_test_pilot inspects the marker positions directly so a
		# tap on the marker registers even when it sits in a neighbouring cell
		# from the tile-centre's perspective.
		var picked := _hit_test_pilot(pos)
		if picked == null:
			return
		_set_pending_pick(picked)
	else:
		var cell := _hit_test_cell(pos)
		if cell == Vector2i(-2147483648, -2147483648):
			return
		if not valid_cells.has(cell):
			return
		_set_pending_pick(cell)


# Stores the clicked target as the pending pick, re-evaluates the 확인 button,
# and triggers a redraw so the renderer can highlight the chosen pilot/cell.
func _set_pending_pick(target: Variant) -> void:
	pending_pick = target
	_refresh_confirm_disabled()
	_request_redraw()


func _refresh_confirm_disabled() -> void:
	if _btn_confirm != null and is_instance_valid(_btn_confirm):
		_btn_confirm.disabled = not (_play_allowed and has_required_pick())


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
# and the team-direction offset position (returned by
# BattleSim.pilot_marker_pos_solo) so a tap on the visible marker always
# resolves regardless of how BattleRenderer ended up laying out the cell.
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
# 확인 / 취소는 화면 **우하단**, Discard 카운터 바로 위에 나란히 뜬다. y 는
# BS_HAND_CENTER.y(핸드 행 상단)에서 역산하므로 핸드 행이 움직이면 따라간다.
# 좌우 순서는 CardSelectOverlay 와 동일하게 확인(왼쪽) / 취소(오른쪽).
func _btn_top_y() -> float:
	return _bs.BS_HAND_CENTER.y - BTN_HAND_GAP - BTN_H


## 뷰포트 실제 폭. 팀 패널 / 버튼 배치가 모두 이 값을 기준으로 우측 정렬된다.
func _screen_w() -> float:
	return get_viewport().get_visible_rect().size.x


func _build_buttons() -> void:
	# 우측 끝에서 역산: [확인][gap][취소] 순으로 붙여 오른쪽 여백에 맞춘다.
	var cancel_x: float = _screen_w() - BTN_SIDE_MARGIN - BTN_W
	var confirm_x: float = cancel_x - CONFIRM_BTN_GAP - BTN_W

	_btn_confirm = _make_btn("확인")
	_btn_confirm.position = Vector2(confirm_x, _btn_top_y())
	_btn_confirm.disabled = true
	_btn_confirm.pressed.connect(_on_confirm_pressed)
	_ui_layer.add_child(_btn_confirm)

	_btn_cancel = _make_btn("취소")
	_btn_cancel.position = Vector2(cancel_x, _btn_top_y())
	_btn_cancel.pressed.connect(_on_cancel_pressed)
	_ui_layer.add_child(_btn_cancel)


func _make_btn(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 24)
	b.size = Vector2(BTN_W, BTN_H)
	return b


# 좌/우 팀 패널을 빌드한다. 좌측에 플레이어팀(0), 우측에 적팀(1) 참여
# 파일럿을 파일럿 이미지 + HP 텍스트 + HP 프로그레스 바로 표시한다.
# PREVIEW 모드 전용.
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
	var screen_w: float = _screen_w()
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


# ─── Teardown ────────────────────────────────────────────────────────────────
# Common reset helper used by start_card_selection / _teardown before stamping
# new state. Does NOT touch button refs — the entry point rebuilds them.
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
	_play_allowed = false


func _free_ui() -> void:
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


func _teardown() -> void:
	_clear_visual_state()
	_free_ui()
	_on_confirm = Callable()
	_on_cancel  = Callable()
	_request_redraw()


# Force tile + battlefield redraws so dim state takes effect immediately.
# The tilemap modulate stays at the default (WHITE) — per-cell black dim is
# drawn by BattleRenderer for cells outside the cast range.
func _request_redraw() -> void:
	if _bs.tiles_layer != null:
		_bs.tiles_layer.modulate = Color.WHITE
	if _bs.renderer != null:
		_bs.renderer.queue_redraw()
