class_name EngageArena
extends Control

# 실시간 교전 아레나 — RealtimeEngageSim 의 상태를 그리기만 한다.
# 게임 상태 변경은 전부 시뮬레이터/매니저 쪽에서 일어난다.
#
# 텍스트는 전부 Label 노드로 만든다(_draw 의 draw_string 은 한글 폴백 폰트를
# 태우기 어렵다). _draw 는 아레나 그래픽 — 바닥, 셀 육각, 포탑 사거리원,
# 유닛, 투사체 — 만 담당한다.

const VP_W: float = 1080.0
const VP_H: float = 1920.0

const TEAM_COLORS := [
	Color(0.32, 0.62, 0.95),   # team 0 (player)
	Color(0.95, 0.40, 0.32),   # team 1 (enemy)
]
const FLOOR_BG      := Color(0.07, 0.09, 0.14, 0.96)
const FLOOR_EDGE    := Color(0.35, 0.40, 0.55, 0.85)
const CELL_LINE     := Color(0.30, 0.36, 0.50, 0.42)
const TURRET_ZONE   := Color(0.95, 0.35, 0.25, 0.10)
const TURRET_EDGE   := Color(0.95, 0.45, 0.30, 0.55)
const TITLE_COLOR   := Color(1.0, 0.95, 0.55, 1.0)
const TIME_COLOR    := Color(0.92, 0.96, 1.0, 1.0)
const TIME_LOW      := Color(1.0, 0.55, 0.40, 1.0)
const HP_BAR_BG     := Color(0.06, 0.06, 0.08, 1.0)
const HP_BAR_FILL   := Color(0.30, 0.85, 0.45, 1.0)
const SHIELD_FILL   := Color(0.85, 0.85, 0.30, 0.85)
const ROW_BG        := Color(0.10, 0.12, 0.18, 0.92)
const ROW_BG_DEAD   := Color(0.18, 0.10, 0.10, 0.92)
const ROW_BG_FLED   := Color(0.11, 0.14, 0.11, 0.92)

## 하단 팀 로스터 스트립.
const ROSTER_TOP: float = 1470.0
const ROSTER_ROW_H: float = 58.0
const ROSTER_GAP: float = 8.0
const ROSTER_COL_W: float = 470.0
const ROSTER_COL_X := [50.0, 560.0]

## 남은 시간 바.
const TIME_BAR_W: float = 560.0
const TIME_BAR_H: float = 12.0
const TIME_BAR_Y: float = 176.0

var _bs: BattleSim = null
var _sim: RealtimeEngageSim = null
var _is_duel: bool = false

var _time_lbl: Label = null
var _phase_lbl: Label = null
## row_data[PilotData] = {row, name, hp_bg, hp_fill, shield_fill}
var _row_data: Dictionary = {}
var _dashboard: Panel = null
## 이탈에 성공한 파일럿 집합 — 매니저가 대시보드 직전에 mark_fled 로 채운다.
var _fled_pilots: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # 뒤쪽 입력 차단
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)


func setup(bs: BattleSim, sim: RealtimeEngageSim, title_text: String,
		is_duel: bool) -> void:
	_bs = bs
	_sim = sim
	_is_duel = is_duel
	_build_ui(title_text)
	set_process(true)


func _build_ui(title_text: String) -> void:
	var title := _make_label(title_text, 40, TITLE_COLOR,
			HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, 60)
	title.size = Vector2(VP_W, 56)
	add_child(title)

	_time_lbl = _make_label("", 46, TIME_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_time_lbl.position = Vector2(0, 112)
	_time_lbl.size = Vector2(VP_W, 56)
	add_child(_time_lbl)

	_phase_lbl = _make_label("", 24, Color(0.85, 0.85, 0.9),
			HORIZONTAL_ALIGNMENT_CENTER)
	_phase_lbl.position = Vector2(0, TIME_BAR_Y + TIME_BAR_H + 6.0)
	_phase_lbl.size = Vector2(VP_W, 32)
	add_child(_phase_lbl)

	for t in range(2):
		var hdr := _make_label("아군" if t == 0 else "적군", 24, TEAM_COLORS[t],
				HORIZONTAL_ALIGNMENT_LEFT)
		hdr.position = Vector2(ROSTER_COL_X[t], ROSTER_TOP - 32.0)
		hdr.size = Vector2(ROSTER_COL_W, 28)
		add_child(hdr)
		var team_units: Array = _sim.units_of(t)
		for i in team_units.size():
			var u := team_units[i] as RealtimeEngageSim.EUnit
			_build_roster_row(u, ROSTER_COL_X[t],
					ROSTER_TOP + float(i) * (ROSTER_ROW_H + ROSTER_GAP), t)


func _build_roster_row(u: RealtimeEngageSim.EUnit, x: float, y: float,
		team: int) -> void:
	var panel := Panel.new()
	panel.position = Vector2(x, y)
	panel.size = Vector2(ROSTER_COL_W, ROSTER_ROW_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _row_style(ROW_BG))
	add_child(panel)

	var name_lbl := _make_label("", 22, TEAM_COLORS[team],
			HORIZONTAL_ALIGNMENT_LEFT)
	name_lbl.position = Vector2(12, 4)
	name_lbl.size = Vector2(ROSTER_COL_W - 24, 26)
	panel.add_child(name_lbl)

	var hp_bg := ColorRect.new()
	hp_bg.position = Vector2(12, ROSTER_ROW_H - 20.0)
	hp_bg.size = Vector2(ROSTER_COL_W - 24, 12)
	hp_bg.color = HP_BAR_BG
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hp_bg)
	var hp_fill := ColorRect.new()
	hp_fill.position = hp_bg.position
	hp_fill.size = Vector2(hp_bg.size.x * u.hp_ratio(), hp_bg.size.y)
	hp_fill.color = HP_BAR_FILL
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hp_fill)
	var shield_fill := ColorRect.new()
	shield_fill.position = Vector2(hp_bg.position.x + hp_fill.size.x, hp_bg.position.y)
	shield_fill.size = Vector2(0.0, hp_bg.size.y)
	shield_fill.color = SHIELD_FILL
	shield_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(shield_fill)

	_row_data[u.pilot] = {
		"row": panel, "name": name_lbl, "hp_bg": hp_bg,
		"hp_fill": hp_fill, "shield_fill": shield_fill, "unit": u,
	}


func _process(_delta: float) -> void:
	if _sim == null:
		return
	_refresh_header()
	_refresh_rows()
	_drain_popups()
	queue_redraw()


func _refresh_header() -> void:
	if _is_duel:
		_time_lbl.text = _fmt_time(_sim.elapsed)
		_time_lbl.add_theme_color_override("font_color", TIME_COLOR)
	else:
		var left: float = _sim.time_left()
		_time_lbl.text = _fmt_time(left)
		_time_lbl.add_theme_color_override("font_color",
				TIME_LOW if left <= 3.0 else TIME_COLOR)
	if _phase_lbl != null:
		if _sim.finished:
			_phase_lbl.text = "교전 종료"
		elif _sim.time_left() <= 0.0 and not _is_duel:
			_phase_lbl.text = "전원 후퇴"
		else:
			_phase_lbl.text = ""


static func _fmt_time(secs: float) -> String:
	var s: float = max(0.0, secs)
	return "%02d:%04.1f" % [int(s) / 60, fmod(s, 60.0)]


func _refresh_rows() -> void:
	for key in _row_data:
		var row: Dictionary = _row_data[key]
		var u := row["unit"] as RealtimeEngageSim.EUnit
		var p := key as PilotData
		(row["name"] as Label).text = "%s  %d/%d%s" % [
			_bs.pilot_label(p), p.hp, p.max_hp, _state_tag(u)]
		var bg := row["hp_bg"] as ColorRect
		var fill := row["hp_fill"] as ColorRect
		var ratio: float = u.hp_ratio()
		fill.size = Vector2(bg.size.x * ratio, bg.size.y)
		fill.color = HP_BAR_FILL if ratio >= RealtimeEngageSim.FLEE_HP_RATIO \
				else Color(0.90, 0.55, 0.25)
		var shield_fill := row["shield_fill"] as ColorRect
		var shield_w: float = 0.0
		if p.shield > 0 and p.max_hp > 0:
			shield_w = bg.size.x * clampf(float(p.shield) / float(p.max_hp), 0.0, 1.0)
		shield_fill.position = Vector2(bg.position.x + fill.size.x, bg.position.y)
		shield_fill.size = Vector2(shield_w, bg.size.y)
		var panel := row["row"] as Panel
		if u.state == RealtimeEngageSim.State.DEAD:
			panel.add_theme_stylebox_override("panel", _row_style(ROW_BG_DEAD))
		elif u.state == RealtimeEngageSim.State.FLED:
			panel.add_theme_stylebox_override("panel", _row_style(ROW_BG_FLED))


static func _state_tag(u: RealtimeEngageSim.EUnit) -> String:
	match u.state:
		RealtimeEngageSim.State.DEAD:
			return "   (처치됨)"
		RealtimeEngageSim.State.FLED:
			return "   (이탈)"
		RealtimeEngageSim.State.RETREAT:
			return "   (후퇴 중)"
		RealtimeEngageSim.State.DASH:
			return "   (대쉬)"
	return ""


# 시뮬레이터가 쌓아 둔 데미지 팝업을 Label 로 꺼내 띄우고 큐를 비운다.
func _drain_popups() -> void:
	for raw in _sim.popups:
		var e: Dictionary = raw
		_spawn_popup(e["pos"], String(e["text"]), e["color"])
	_sim.popups.clear()


func _spawn_popup(at: Vector2, text: String, color: Color) -> void:
	var lbl := _make_label(text, 30, color, HORIZONTAL_ALIGNMENT_CENTER)
	lbl.size = Vector2(240, 40)
	lbl.position = Vector2(at.x - 120.0, at.y - 78.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween().set_parallel()
	tw.tween_property(lbl, "position:y", lbl.position.y - 54.0, 0.55) \
			.set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.55).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(Callable(lbl, "queue_free"))


# ─── 아레나 렌더링 ───────────────────────────────────────────────────────────
func _draw() -> void:
	if _sim == null:
		return
	_draw_floor()
	_draw_cells()
	_draw_turrets()
	_draw_projectiles()
	_draw_units()
	_draw_time_bar()


func _draw_floor() -> void:
	var c: Vector2 = RealtimeEngageSim.ARENA_CENTER
	var h: Vector2 = RealtimeEngageSim.ARENA_HALF
	var rect := Rect2(c - h, h * 2.0)
	draw_rect(rect, FLOOR_BG, true)
	draw_rect(rect, FLOOR_EDGE, false, 2.0)


# 교전에 참여한 전장 셀을 육각 외곽선으로 깔아 준다 — 아레나 좌표가 전장
# 배치를 그대로 확대한 것임을 시각적으로 알려 주는 역할.
func _draw_cells() -> void:
	var r: float = _sim.cell_radius
	for raw in _sim.area_cell_positions:
		var c: Vector2 = raw
		var pts := PackedVector2Array()
		for i in range(6):
			var a: float = TAU * float(i) / 6.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		pts.append(pts[0])
		draw_polyline(pts, CELL_LINE, 2.0)


func _draw_turrets() -> void:
	for raw in _sim.turrets:
		var t := raw as RealtimeEngageSim.ETurret
		var col: Color = TEAM_COLORS[t.team]
		# 사거리원 — 회피/다이브 판단의 근거를 화면에 그대로 노출한다.
		draw_circle(t.pos, RealtimeEngageSim.TURRET_RANGE, TURRET_ZONE)
		draw_arc(t.pos, RealtimeEngageSim.TURRET_RANGE, 0.0, TAU, 64,
				TURRET_EDGE, 2.0)
		# 포탑 본체 — 팀색 사각 + 밝은 코어.
		var s := 26.0
		draw_rect(Rect2(t.pos - Vector2(s, s), Vector2(s * 2.0, s * 2.0)),
				Color(0.10, 0.11, 0.16, 0.95), true)
		draw_rect(Rect2(t.pos - Vector2(s, s), Vector2(s * 2.0, s * 2.0)),
				col, false, 3.0)
		draw_circle(t.pos, 9.0, col)


func _draw_projectiles() -> void:
	for raw in _sim.projectiles:
		var p: Dictionary = raw
		var f: float = clampf(float(p["t"]) / max(0.001, float(p["dur"])), 0.0, 1.0)
		var from: Vector2 = p["from"]
		var to: Vector2 = p["to"]
		var at: Vector2 = from.lerp(to, f)
		var col: Color = TEAM_COLORS[int(p["team"])]
		if bool(p["is_turret"]):
			col = Color(1.0, 0.72, 0.30)
			draw_line(from.lerp(to, max(0.0, f - 0.22)), at, col * Color(1, 1, 1, 0.55), 3.0)
			draw_circle(at, 9.0, col)
		else:
			draw_line(from.lerp(to, max(0.0, f - 0.18)), at, col * Color(1, 1, 1, 0.5), 2.5)
			draw_circle(at, 6.0, col)


func _draw_units() -> void:
	for raw in _sim.units:
		var u := raw as RealtimeEngageSim.EUnit
		if u.state == RealtimeEngageSim.State.FLED:
			continue
		var dead: bool = (u.state == RealtimeEngageSim.State.DEAD)
		var alpha: float = 0.30 if dead else 1.0
		var col: Color = TEAM_COLORS[u.team]
		var r: float = RealtimeEngageSim.UNIT_RADIUS

		# 접지 그림자.
		draw_circle(u.pos + Vector2(0, r * 0.72),
				r * 0.72, Color(0, 0, 0, 0.30 * alpha))

		# 사거리 표시 — 살아 있고 근접이 아닌 유닛만(원거리 카이팅 가독성).
		if not dead and not u.is_melee:
			draw_arc(u.pos, u.atk_range, 0.0, TAU, 48,
					Color(col.r, col.g, col.b, 0.12), 1.5)

		# 대쉬 트레일.
		if u.state == RealtimeEngageSim.State.DASH:
			draw_line(u.pos - u.dash_dir * 70.0, u.pos,
					Color(1.0, 0.95, 0.6, 0.55), 6.0)

		# 초상.
		var portrait: Texture2D = PilotImages.circle_for(u.pilot.pilot_id)
		if portrait != null:
			draw_texture_rect(portrait,
					Rect2(u.pos - Vector2(r, r), Vector2(r * 2.0, r * 2.0)),
					false, Color(1, 1, 1, alpha))
		else:
			draw_circle(u.pos, r, Color(col.r, col.g, col.b, alpha))

		# 피격 플래시.
		if u.hit_flash > 0.0:
			draw_circle(u.pos, r + 3.0,
					Color(1.0, 0.35, 0.35, 0.45 * (u.hit_flash / 0.22)))

		# 공격 모션 — 바라보는 방향으로 짧은 호를 튀긴다.
		if u.swing_t > 0.0 and u.is_melee:
			var a0: float = u.facing.angle() - 0.6
			draw_arc(u.pos, r + 14.0, a0, a0 + 1.2, 16,
					Color(1.0, 0.95, 0.6, 0.85), 5.0)

		# 팀색 HP 링.
		var ring_w := 7.0
		var ring_r: float = r + ring_w * 0.5 + 1.0
		draw_arc(u.pos, ring_r, 0.0, TAU, 36,
				Color(0.15, 0.15, 0.15, alpha), ring_w)
		if not dead:
			var frac: float = u.hp_ratio()
			var start_a: float = -PI * 0.5
			draw_arc(u.pos, ring_r, start_a, start_a + TAU * frac, 36,
					col, ring_w)

		# 후퇴 화살표 — 이탈 방향을 짧은 삼각형으로.
		if u.state == RealtimeEngageSim.State.RETREAT:
			var tip: Vector2 = u.pos + u.facing * (r + 26.0)
			var side: Vector2 = u.facing.orthogonal() * 9.0
			draw_colored_polygon(
					PackedVector2Array([tip,
						u.pos + u.facing * (r + 12.0) + side,
						u.pos + u.facing * (r + 12.0) - side]),
					Color(0.95, 0.95, 0.55, 0.9))


func _draw_time_bar() -> void:
	if _is_duel:
		return
	var x: float = (VP_W - TIME_BAR_W) * 0.5
	draw_rect(Rect2(x, TIME_BAR_Y, TIME_BAR_W, TIME_BAR_H),
			Color(0.10, 0.11, 0.16, 0.95), true)
	var frac: float = 0.0
	if _sim.duration > 0.0:
		frac = clampf(_sim.time_left() / _sim.duration, 0.0, 1.0)
	draw_rect(Rect2(x, TIME_BAR_Y, TIME_BAR_W * frac, TIME_BAR_H),
			TIME_LOW if frac <= 0.25 else Color(0.45, 0.80, 0.95), true)
	draw_rect(Rect2(x, TIME_BAR_Y, TIME_BAR_W, TIME_BAR_H),
			Color(0.4, 0.45, 0.6, 0.8), false, 1.5)


# ─── 결과 대시보드 ───────────────────────────────────────────────────────────
func show_dashboard(team0: Array, team1: Array, stats: Dictionary,
		on_confirm: Callable) -> void:
	set_process(false)
	_dashboard = Panel.new()
	var dash_w := 940.0
	var dash_h := 1240.0
	_dashboard.position = Vector2((VP_W - dash_w) * 0.5, (VP_H - dash_h) * 0.5)
	_dashboard.size = Vector2(dash_w, dash_h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.16, 0.98)
	sb.border_color = TITLE_COLOR
	sb.border_width_top    = 3
	sb.border_width_bottom = 3
	sb.border_width_left   = 3
	sb.border_width_right  = 3
	sb.corner_radius_top_left     = 16
	sb.corner_radius_top_right    = 16
	sb.corner_radius_bottom_left  = 16
	sb.corner_radius_bottom_right = 16
	_dashboard.add_theme_stylebox_override("panel", sb)
	add_child(_dashboard)

	var title := _make_label("교전 결과", 40, TITLE_COLOR,
			HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, 24)
	title.size = Vector2(dash_w, 56)
	_dashboard.add_child(title)

	var sub := _make_label("교전 시간 %s" % _fmt_time(_sim.elapsed), 22,
			Color(0.8, 0.8, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(0, 72)
	sub.size = Vector2(dash_w, 30)
	_dashboard.add_child(sub)

	var hdr_y: float = 118.0
	_dashboard_header_row(hdr_y, dash_w)

	var y: float = hdr_y + 40.0
	for t in range(2):
		var team_pilots: Array = team0 if t == 0 else team1
		var team_lbl := _make_label("아군" if t == 0 else "적군", 22,
				TEAM_COLORS[t], HORIZONTAL_ALIGNMENT_LEFT)
		team_lbl.position = Vector2(28, y)
		team_lbl.size = Vector2(dash_w - 56, 28)
		_dashboard.add_child(team_lbl)
		y += 32.0
		for raw in team_pilots:
			var p := raw as PilotData
			var s: Dictionary = stats.get(p, {"dealt": 0, "taken": 0, "kills": 0})
			_dashboard_row(p, s, y, dash_w)
			y += 36.0
		y += 16.0

	var btn := Button.new()
	btn.text = "확인"
	btn.add_theme_font_size_override("font_size", 28)
	btn.position = Vector2((dash_w - 240.0) * 0.5, dash_h - 96.0)
	btn.size = Vector2(240, 64)
	btn.pressed.connect(on_confirm)
	_dashboard.add_child(btn)


func _dashboard_header_row(y: float, _dash_w: float) -> void:
	var cols := [
		{"text": "파일럿",   "x": 28.0,  "w": 240.0, "align": HORIZONTAL_ALIGNMENT_LEFT},
		{"text": "준 딜량",   "x": 270.0, "w": 200.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"text": "받은 딜량", "x": 470.0, "w": 200.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"text": "처치",     "x": 670.0, "w": 200.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	]
	for c in cols:
		var lbl := _make_label(String(c["text"]), 20,
				Color(0.8, 0.8, 0.8), int(c["align"]))
		lbl.position = Vector2(float(c["x"]), y)
		lbl.size = Vector2(float(c["w"]), 28)
		_dashboard.add_child(lbl)


func _dashboard_row(p: PilotData, s: Dictionary, y: float, _dash_w: float) -> void:
	var suffix := ""
	if not p.alive:
		suffix = "  (처치됨)"
	elif _fled_pilots.has(p):
		suffix = "  (이탈)"
	var name_lbl := _make_label(
			"%s  (HP %d/%d)%s" % [_bs.pilot_label(p), p.hp, p.max_hp, suffix],
			20, TEAM_COLORS[p.team], HORIZONTAL_ALIGNMENT_LEFT)
	name_lbl.position = Vector2(28, y)
	name_lbl.size = Vector2(240, 28)
	_dashboard.add_child(name_lbl)

	_dashboard.add_child(_stat_cell(int(s["dealt"]), 270.0, y, 200.0))
	_dashboard.add_child(_stat_cell(int(s["taken"]), 470.0, y, 200.0))
	_dashboard.add_child(_stat_cell(int(s["kills"]), 670.0, y, 200.0))

	if not p.alive:
		name_lbl.modulate = Color(0.7, 0.5, 0.5)


func mark_fled(pilots: Array) -> void:
	_fled_pilots.clear()
	for p in pilots:
		_fled_pilots[p] = true


func _stat_cell(value: int, x: float, y: float, w: float) -> Label:
	var lbl := _make_label(str(value), 22,
			Color(0.95, 0.95, 0.95), HORIZONTAL_ALIGNMENT_RIGHT)
	lbl.position = Vector2(x, y)
	lbl.size = Vector2(w, 28)
	return lbl


# ─── 보조 ────────────────────────────────────────────────────────────────────
func _make_label(text: String, font_size: int, color: Color,
		halign: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = halign
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


static func _row_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	return sb
