class_name TrainingView
extends Control

# Weekly training scheduler. 5-pilot × 7-weekday grid. Tap a cell to open
# the TrainingType picker. Match cells (Fri/Sat/Sun) are locked when the
# player has a real match scheduled this week. Top of the screen shows each
# pilot's current stats and the projected post-week stats. Bottom row
# exposes "자동 채우기" (defaults) and "주 진행" (apply training and route
# to TRAINING_RESULT).

const TYPE_LABELS: Dictionary = {
	GameEnums.TrainingType.REST:      "휴식",
	GameEnums.TrainingType.LANING:    "라인전",
	GameEnums.TrainingType.MECHANICS: "메카닉",
	GameEnums.TrainingType.GAMESENSE: "게임감각",
	GameEnums.TrainingType.TEAMFIGHT: "한타",
	GameEnums.TrainingType.SCRIM:     "스크림",
	GameEnums.TrainingType.MATCH:     "경기",
}

const TYPE_SHORT: Dictionary = {
	GameEnums.TrainingType.REST:      "휴",
	GameEnums.TrainingType.LANING:    "라",
	GameEnums.TrainingType.MECHANICS: "메",
	GameEnums.TrainingType.GAMESENSE: "겜",
	GameEnums.TrainingType.TEAMFIGHT: "한",
	GameEnums.TrainingType.SCRIM:     "스",
	GameEnums.TrainingType.MATCH:     "경",
}

const TYPE_COLORS: Dictionary = {
	GameEnums.TrainingType.REST:      Color(0.55, 0.75, 1.00),
	GameEnums.TrainingType.LANING:    Color(0.55, 0.85, 0.55),
	GameEnums.TrainingType.MECHANICS: Color(1.00, 0.70, 0.30),
	GameEnums.TrainingType.GAMESENSE: Color(0.85, 0.55, 1.00),
	GameEnums.TrainingType.TEAMFIGHT: Color(1.00, 0.50, 0.50),
	GameEnums.TrainingType.SCRIM:     Color(1.00, 0.85, 0.30),
	GameEnums.TrainingType.MATCH:     Color(0.55, 0.55, 0.65),
}

const ROLE_NAMES: Array = ["TANK", "FIGHTER", "ASSASSIN", "SUPPORT", "SNIPER"]
const ROLE_COLORS: Array = [
	Color(0.30, 0.55, 1.00),
	Color(1.00, 0.55, 0.20),
	Color(0.75, 0.40, 1.00),
	Color(0.30, 0.85, 0.45),
	Color(1.00, 0.35, 0.35),
]

const WEEKDAY_NAMES: Array = ["월", "화", "수", "목", "금", "토", "일"]

const STAT_KEYS: Array   = ["laning", "mechanics", "gamesense", "teamfight", "mental"]
const STAT_LABELS: Array = ["라", "메", "겜", "한", "멘"]

# Picker shows only player-editable training types. MATCH is reserved for the
# weekend lock and never appears in the dialog.
const PICKER_OPTIONS: Array = [
	GameEnums.TrainingType.REST,
	GameEnums.TrainingType.LANING,
	GameEnums.TrainingType.MECHANICS,
	GameEnums.TrainingType.GAMESENSE,
	GameEnums.TrainingType.TEAMFIGHT,
	GameEnums.TrainingType.SCRIM,
]

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _scheduler: TrainingScheduler = null

var _name_lbls: Array = []           # 5 Label — pilot name in preview row
var _face_rects: Array = []          # 5 TextureRect — face image in preview row
var _stat_cells: Array = []          # 5 rows × 5 stats of {"current","projected"} Label pair
var _cell_buttons: Array = []        # 5 rows × 7 cols of Button (schedule grid)

var _picker_layer: Control = null
var _picker_pilot_id: int = -1
var _picker_day: int = -1
var _built: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	if not _built:
		_build()
		_built = true
	_resolve_scheduler()
	refresh()


# Idempotent — SeasonHub calls this each time it routes to TRAINING.
func ensure_view() -> void:
	if not _built:
		_build()
		_built = true
	_resolve_scheduler()
	refresh()


func _resolve_scheduler() -> void:
	if _scheduler != null:
		return
	if _hub == null:
		return
	_scheduler = _hub.get_node_or_null("TrainingScheduler") as TrainingScheduler


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 제목이 깔리지 않게. 제목만 따로 내리면 본문과 겹친다.
	ScreenMetrics.indent_to_safe_top(self)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.14, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 배경만은 안전 영역 밖(노치 자리)까지 덮는다 — 안 그러면 그 띠가
	# 엔진 기본 배경색으로 남는다.
	ScreenMetrics.extend_background(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	UiHelpers.mk_label(self, "훈련 편집", 36, Color(1.0, 0.85, 0.20),
			Vector2(0, 18), Vector2(1080, 44), HORIZONTAL_ALIGNMENT_CENTER)

	UiHelpers.mk_label(self, "이번 주 적용 시 예상 변화", 22, Color(0.85, 0.85, 0.95),
			Vector2(0, 76), Vector2(1080, 28), HORIZONTAL_ALIGNMENT_CENTER)

	_build_preview_table()
	_build_grid()
	_build_buttons()
	_build_picker()


func _build_preview_table() -> void:
	var x0: float = 30.0
	var y0: float = 116.0
	var row_h: float = 60.0
	var role_w: float = 80.0
	var name_w: float = 150.0
	var stat_w: float = 150.0

	# 줄 순서는 **역할 열거값 순서가 아니라 화면 순서**다(탑 · 정글 · 미드 ·
	# 원딜 · 서폿) — `GameEnums.ROLE_DISPLAY_ORDER`. 아래 라벨 배열들은 그리는
	# 순서(= 자리 순서)로 쌓이고, `_player_pilots_by_seat()` 도 같은 순서로
	# 파일럿을 돌려주므로 인덱스 하나가 끝까지 자리 번호로 남는다.
	for seat in 5:
		var r: int = int(GameEnums.ROLE_DISPLAY_ORDER[seat])
		var y: float = y0 + seat * row_h
		var role_col: Color = ROLE_COLORS[r]

		var panel := Panel.new()
		var sty := StyleBoxFlat.new()
		sty.bg_color = Color(0.10, 0.12, 0.18, 1.0)
		sty.border_color = role_col
		sty.border_width_bottom = 1
		panel.add_theme_stylebox_override("panel", sty)
		panel.position = Vector2(x0, y)
		panel.size     = Vector2(1020.0, row_h - 6)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)

		var face_rect := TextureRect.new()
		face_rect.position     = Vector2(8, 7)
		face_rect.size         = Vector2(40, 40)
		face_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		face_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		face_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(face_rect)
		_face_rects.append(face_rect)

		UiHelpers.mk_label(panel, ROLE_NAMES[r], 16, role_col,
				Vector2(56, 16), Vector2(role_w, 22), HORIZONTAL_ALIGNMENT_LEFT)

		var name_lbl := UiHelpers.mk_label(panel, "—", 18, Color(1, 1, 1),
				Vector2(56 + role_w, 16), Vector2(name_w, 22),
				HORIZONTAL_ALIGNMENT_LEFT)
		_name_lbls.append(name_lbl)

		var stat_row: Array = []
		var sx0: float = 56 + role_w + name_w + 16
		for s in STAT_KEYS.size():
			var sx: float = sx0 + s * stat_w
			UiHelpers.mk_label(panel, STAT_LABELS[s], 14, Color(0.65, 0.7, 0.8),
					Vector2(sx, 4), Vector2(28, 18), HORIZONTAL_ALIGNMENT_LEFT)
			var cur_lbl := UiHelpers.mk_label(panel, "—", 18, Color(0.95, 0.95, 1.0),
					Vector2(sx, 24), Vector2(48, 22), HORIZONTAL_ALIGNMENT_LEFT)
			var prj_lbl := UiHelpers.mk_label(panel, "", 16, Color(0.55, 0.95, 0.55),
					Vector2(sx + 50, 26), Vector2(stat_w - 50, 22),
					HORIZONTAL_ALIGNMENT_LEFT)
			stat_row.append({"current": cur_lbl, "projected": prj_lbl})
		_stat_cells.append(stat_row)


func _build_grid() -> void:
	var name_col_w: float = 160.0
	var cell_w: float = 120.0
	var cell_h: float = 120.0
	var header_h: float = 40.0
	var grid_w: float = name_col_w + 7 * cell_w
	var grid_x0: float = (1080.0 - grid_w) / 2.0
	var grid_y0: float = 440.0

	UiHelpers.mk_label(self, "파일럿", 20, Color(0.75, 0.85, 0.95),
			Vector2(grid_x0, grid_y0), Vector2(name_col_w, header_h),
			HORIZONTAL_ALIGNMENT_CENTER)

	for c in 7:
		var col_color: Color = Color(0.95, 0.95, 1.0)
		if c == 4 or c == 5:
			col_color = Color(1.0, 0.85, 0.30)
		elif c == 6:
			col_color = Color(1.0, 0.55, 0.55)
		UiHelpers.mk_label(self, WEEKDAY_NAMES[c], 22, col_color,
				Vector2(grid_x0 + name_col_w + c * cell_w, grid_y0),
				Vector2(cell_w, header_h), HORIZONTAL_ALIGNMENT_CENTER)

	for seat in 5:
		var r: int = int(GameEnums.ROLE_DISPLAY_ORDER[seat])
		var y: float = grid_y0 + header_h + seat * cell_h
		UiHelpers.mk_label(self, ROLE_NAMES[r], 18, ROLE_COLORS[r],
				Vector2(grid_x0, y + (cell_h - 24) / 2.0),
				Vector2(name_col_w, 24), HORIZONTAL_ALIGNMENT_CENTER)

		var btn_row: Array = []
		for c in 7:
			var btn := Button.new()
			btn.position = Vector2(grid_x0 + name_col_w + c * cell_w + 4, y + 4)
			btn.size     = Vector2(cell_w - 8, cell_h - 8)
			btn.add_theme_font_size_override("font_size", 22)
			btn.text = ""
			btn.pressed.connect(_on_cell_pressed.bind(seat, c))
			add_child(btn)
			btn_row.append(btn)
		_cell_buttons.append(btn_row)


func _build_buttons() -> void:
	var w: float = 480.0
	var h: float = 100.0
	# 하단 안전선에 매단다 — 이 자리는 아이폰 홈 인디케이터 / 안드로이드
	# 제스처 바가 터치를 가져가는 구간과 맞닿아 있다.
	var y: float = ScreenMetrics.safe_h() - 80.0 - h
	var gap: float = 40.0
	var total_w: float = 2.0 * w + gap
	var x0: float = (1080.0 - total_w) / 2.0

	var fill_btn := Button.new()
	fill_btn.text = "자동 채우기"
	fill_btn.position = Vector2(x0, y)
	fill_btn.size     = Vector2(w, h)
	fill_btn.add_theme_font_size_override("font_size", 30)
	fill_btn.pressed.connect(_on_autofill_pressed)
	add_child(fill_btn)

	var save_btn := Button.new()
	save_btn.text = "주 진행"
	save_btn.position = Vector2(x0 + w + gap, y)
	save_btn.size     = Vector2(w, h)
	save_btn.add_theme_font_size_override("font_size", 30)
	save_btn.pressed.connect(_on_close_pressed)
	add_child(save_btn)


func _build_picker() -> void:
	_picker_layer = Control.new()
	_picker_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker_layer.visible = false
	add_child(_picker_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	_picker_layer.add_child(dim)

	var card := Panel.new()
	var sty := StyleBoxFlat.new()
	sty.bg_color     = Color(0.13, 0.15, 0.22, 1.0)
	sty.border_color = Color(0.85, 0.85, 1.0, 0.8)
	sty.border_width_left = 2; sty.border_width_right = 2
	sty.border_width_top  = 2; sty.border_width_bottom = 2
	sty.corner_radius_top_left     = 8
	sty.corner_radius_top_right    = 8
	sty.corner_radius_bottom_left  = 8
	sty.corner_radius_bottom_right = 8
	card.add_theme_stylebox_override("panel", sty)
	card.size     = Vector2(640, 800)
	# 이 뷰는 안전 영역 위끝으로 내려가 있으므로 세로 가운데는 뷰포트 높이가
	# 아니라 안전 영역 높이로 잡는다.
	card.position = (Vector2(ScreenMetrics.vp_w(), ScreenMetrics.safe_h())
			- Vector2(640.0, 800.0)) * 0.5
	_picker_layer.add_child(card)

	UiHelpers.mk_label(card, "훈련 선택", 28, Color(1.0, 0.85, 0.20),
			Vector2(0, 18), Vector2(640, 36), HORIZONTAL_ALIGNMENT_CENTER)

	for i in PICKER_OPTIONS.size():
		var t: int = int(PICKER_OPTIONS[i])
		var btn := Button.new()
		btn.text = TYPE_LABELS[t]
		btn.position = Vector2(40, 70 + i * 100)
		btn.size     = Vector2(560, 90)
		btn.add_theme_font_size_override("font_size", 30)
		btn.add_theme_color_override("font_color", TYPE_COLORS[t])
		btn.pressed.connect(_on_picker_choose.bind(t))
		card.add_child(btn)

	var cancel := Button.new()
	cancel.text = "취소"
	cancel.position = Vector2(40, 70 + 6 * 100)
	cancel.size     = Vector2(560, 90)
	cancel.add_theme_font_size_override("font_size", 28)
	cancel.pressed.connect(_close_picker)
	card.add_child(cancel)


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not _built:
		return
	_normalize_locked_cells()
	_refresh_preview()
	_refresh_grid()


# Reconcile schedule cells with actual lock state. Locked weekday (= player team
# has a real scheduled match this week) → MATCH. Unlocked weekday whose value is
# still MATCH (left over from default-fill) → REST so it can be edited.
func _normalize_locked_cells() -> void:
	var pilots: Array = _player_pilots_by_seat()
	var sched: Dictionary = _gm.season_state["training_schedule"]
	for seat in 5:
		var p: PlayerData = pilots[seat]
		if p == null or not sched.has(p.id):
			continue
		var week: Array = sched[p.id]
		for c in 7:
			if _is_cell_locked(c):
				week[c] = GameEnums.TrainingType.MATCH
			elif int(week[c]) == GameEnums.TrainingType.MATCH:
				week[c] = GameEnums.TrainingType.REST


func _refresh_preview() -> void:
	var pilots: Array = _player_pilots_by_seat()
	for seat in 5:
		var p: PlayerData = pilots[seat]
		if p == null:
			_name_lbls[seat].text = "—"
			(_face_rects[seat] as TextureRect).texture = null
			for s in STAT_KEYS.size():
				_stat_cells[seat][s]["current"].text = "—"
				_stat_cells[seat][s]["projected"].text = ""
			continue
		_name_lbls[seat].text = p.name
		(_face_rects[seat] as TextureRect).texture = PilotImages.face_for(p.id)
		var projected: Dictionary = {}
		if _scheduler != null:
			projected = _scheduler.projected_week_stats(p)
		for s in STAT_KEYS.size():
			var key: String = STAT_KEYS[s]
			var cur: int = int(p.get(key))
			_stat_cells[seat][s]["current"].text = "%d" % cur
			var prj_lbl: Label = _stat_cells[seat][s]["projected"]
			if projected.has(key):
				var prj: int = int(projected[key])
				var diff: int = prj - cur
				if diff > 0:
					prj_lbl.text = "→ %d  (+%d)" % [prj, diff]
					prj_lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
				elif diff < 0:
					prj_lbl.text = "→ %d  (%d)" % [prj, diff]
					prj_lbl.add_theme_color_override("font_color", Color(1.00, 0.55, 0.55))
				else:
					prj_lbl.text = ""
			else:
				prj_lbl.text = ""


func _refresh_grid() -> void:
	var pilots: Array = _player_pilots_by_seat()
	var sched: Dictionary = _gm.season_state["training_schedule"]
	for seat in 5:
		var p: PlayerData = pilots[seat]
		for c in 7:
			var btn: Button = _cell_buttons[seat][c]
			if p == null:
				btn.text = ""
				btn.disabled = true
				continue
			var t: int = GameEnums.TrainingType.REST
			if sched.has(p.id):
				t = int(sched[p.id][c])
			btn.text = "%s\n%s" % [TYPE_SHORT.get(t, "?"), TYPE_LABELS.get(t, "?")]
			_apply_cell_style(btn, t, _is_cell_locked(c))
			btn.disabled = _is_cell_locked(c)


func _apply_cell_style(btn: Button, t: int, locked: bool) -> void:
	var base: Color = TYPE_COLORS.get(t, Color(0.30, 0.30, 0.40))
	var bg: Color = Color(base.r * 0.35, base.g * 0.35, base.b * 0.35, 1.0)
	var sty := StyleBoxFlat.new()
	sty.bg_color = bg
	sty.border_color = base
	sty.border_width_left = 2; sty.border_width_right = 2
	sty.border_width_top  = 2; sty.border_width_bottom = 2
	sty.corner_radius_top_left     = 6
	sty.corner_radius_top_right    = 6
	sty.corner_radius_bottom_left  = 6
	sty.corner_radius_bottom_right = 6

	var hover_sty := sty.duplicate()
	hover_sty.bg_color = Color(base.r * 0.55, base.g * 0.55, base.b * 0.55, 1.0)

	btn.add_theme_stylebox_override("normal",   sty)
	btn.add_theme_stylebox_override("pressed",  hover_sty)
	btn.add_theme_stylebox_override("hover",    hover_sty)
	btn.add_theme_stylebox_override("disabled", sty)

	btn.add_theme_color_override("font_color",          Color(1, 1, 1))
	btn.add_theme_color_override("font_hover_color",    Color(1, 1, 1))
	btn.add_theme_color_override("font_pressed_color",  Color(1, 1, 1))
	btn.add_theme_color_override("font_disabled_color",
			Color(1.0, 1.0, 1.0, 0.85) if locked else Color(0.7, 0.7, 0.75))


# Fri/Sat/Sun cells (weekday 4/5/6) lock to MATCH iff the player has a real
# match scheduled this week (league, playoff, or INTL). Day-of-week is
# fictional under weekly progression — we just lock all three F/S/S cells
# together so the player sees a stable "match weekend" block.
func _is_cell_locked(weekday: int) -> bool:
	if weekday < 4:
		return false
	if _hub == null:
		return true
	var league: LeagueManager = _hub.get_node_or_null("LeagueManager") as LeagueManager
	if league != null and league.player_match_this_week() != null:
		return true
	var tm: TournamentManager = _hub.get_node_or_null("TournamentManager") as TournamentManager
	if tm != null and tm.find_player_match_this_week_idx() >= 0:
		return true
	var intl: InternationalTournament = _hub.get_node_or_null("InternationalTournament") as InternationalTournament
	if intl != null and intl.find_player_match_this_week_idx() >= 0:
		return true
	return false


## 플레이어 팀 다섯 명을 **화면 자리 순서**(탑 · 정글 · 미드 · 원딜 · 서폿)로.
## 예전에는 역할 색인이었는데, 미리보기 표 · 격자 · 셀 클릭이 전부 같은 인덱스
## 하나를 돌려 쓰므로 그 인덱스가 화면 줄 번호와 어긋나면 **엉뚱한 파일럿의
## 훈련이 바뀐다**. 그래서 표 쪽을 자리 순서로 옮겼다.
func _player_pilots_by_seat() -> Array:
	var pool: Array = _gm.season_state["all_pilots"]
	var pid: int = int(_gm.season_state["player_team_id"])
	var by_seat: Array = [null, null, null, null, null]
	for raw in pool:
		var p := raw as PlayerData
		if p.team_id == pid and p.role >= 0 and p.role < 5:
			by_seat[GameEnums.role_seat(int(p.role))] = p
	return by_seat


# ── Interaction ──────────────────────────────────────────────────────────────
func _on_cell_pressed(seat_row: int, day_col: int) -> void:
	if _is_cell_locked(day_col):
		return
	var pilots: Array = _player_pilots_by_seat()
	if seat_row >= pilots.size() or pilots[seat_row] == null:
		return
	var p: PlayerData = pilots[seat_row]
	_open_picker(p.id, day_col)


func _open_picker(pilot_id: int, day: int) -> void:
	_picker_pilot_id = pilot_id
	_picker_day = day
	if _picker_layer != null:
		_picker_layer.visible = true


func _close_picker() -> void:
	_picker_pilot_id = -1
	_picker_day = -1
	if _picker_layer != null:
		_picker_layer.visible = false


func _on_picker_choose(t: int) -> void:
	if _picker_pilot_id == -1 or _picker_day == -1:
		_close_picker()
		return
	var sched: Dictionary = _gm.season_state["training_schedule"]
	if sched.has(_picker_pilot_id):
		var week: Array = sched[_picker_pilot_id]
		if _picker_day >= 0 and _picker_day < week.size():
			week[_picker_day] = t
	_close_picker()
	refresh()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_picker()


func _on_autofill_pressed() -> void:
	if _scheduler != null:
		_scheduler.refill_player_team_defaults()
	refresh()


func _on_close_pressed() -> void:
	if _hub != null and _hub.has_method("on_training_save_and_advance"):
		_hub.on_training_save_and_advance()
