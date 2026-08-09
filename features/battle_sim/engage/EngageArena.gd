class_name EngageArena
extends Control

# 실시간 교전 아레나 — RealtimeEngageSim 의 상태를 그리기만 한다.
# 게임 상태 변경은 전부 시뮬레이터/매니저 쪽에서 일어난다.
#
# 텍스트는 전부 Label 노드로 만든다(draw_string 은 한글 폴백 폰트를 태우기
# 어렵다). 그래픽 — 바닥, 셀 육각, 포탑 사거리원, 유닛, 투사체 — 은 두 개의
# DrawProxy 노드가 나눠 그린다:
#
#   _clip (clip_contents=true, VIEW_RECT)   ← 아레나 밖은 여기서 잘린다
#     └ _world (position/scale = 카메라)     ← draw_world() : 아레나 좌표계
#   _hud  (풀스크린)                          ← draw_hud()   : 화면 좌표계
#
# 자기 자신(_draw)에 그리지 않는 이유: Control 은 자기 그림을 먼저 그리고 그
# 위에 자식을 그린다. 풀스크린 딤 ColorRect 가 자식이므로 자기 _draw 로 그린
# 아레나는 딤 아래에 깔려 버린다. 딤보다 뒤에 붙은 프록시 노드에 그려야
# "아레나 밖만 딤드"가 성립한다.

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
## HP 바가 경고색으로 바뀌는 비율. 게임플레이 의미는 없다(이탈이 없으므로) —
## 순수하게 "이 유닛 위험하다"를 관전자에게 알리는 표시.
const LOW_HP_RATIO: float = 0.30

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

# ─── 아레나 뷰 (클리핑 창) ───────────────────────────────────────────────────
## 교전 그래픽이 그려지는 유일한 사각형. 이 밖으로 나간 것은 잘린다.
## 위로는 타이머 바(+ 상태 라벨 226px), 아래로는 로스터 헤더(1438px)를 피한다.
const VIEW_RECT := Rect2(24.0, 236.0, 1032.0, 1184.0)
## 뷰 안에서 아레나 바닥 바깥으로 남는 여백(레터박스)의 색.
const VIEW_BACKDROP := Color(0.03, 0.04, 0.07, 1.0)
const VIEW_FRAME    := Color(0.45, 0.53, 0.72, 0.90)
## 아레나 밖 화면(전장 · 핸드 행 등)을 덮는 딤.
const DIM_COLOR     := Color(0.0, 0.0, 0.0, 0.82)

# ─── 카메라 워킹 ─────────────────────────────────────────────────────────────
## 최대 확대 배율. 최소 배율은 "아레나 전체가 뷰에 들어가는 배율"로 계산한다
## (VIEW_RECT / 아레나 크기 → 약 1.06) — 그보다 더 축소해 봐야 빈 여백만 는다.
const CAM_MAX_ZOOM: float = 2.4
## 프레이밍 여백 — 유닛 바운딩 박스 바깥으로 이만큼(아레나 px) 더 잡는다.
const CAM_PAD: float = 120.0
## 지수 감쇠 추종 계수(1/s). 클수록 즉각적이고 딱딱하다. 줌이 더 느린 이유는
## 유닛 하나가 잠깐 튀었다고 화면 배율이 출렁이면 멀미가 나기 때문.
const CAM_POS_RATE: float = 4.0
const CAM_ZOOM_RATE: float = 2.6

var _bs: BattleSim = null
var _sim: RealtimeEngageSim = null
var _is_duel: bool = false

## 아레나 뷰 노드 — _ready 에서 만든다.
var _clip: Control = null
var _world: DrawProxy = null
var _hud: DrawProxy = null

## 카메라 상태 (아레나 좌표계 기준).
var _cam_center: Vector2 = RealtimeEngageSim.ARENA_CENTER
var _cam_zoom: float = 1.0
var _cam_target_center: Vector2 = RealtimeEngageSim.ARENA_CENTER
var _cam_target_zoom: float = 1.0
var _cam_min_zoom: float = 1.0

var _time_lbl: Label = null
var _phase_lbl: Label = null
## 종료 유예 동안 상단에 띄우는 배너(빈 문자열 = 아직 전투 중).
var _end_banner: String = ""
## row_data[PilotData] = {row, name, hp_bg, hp_fill, shield_fill}
var _row_data: Dictionary = {}
var _dashboard: Panel = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # 뒤쪽 입력 차단
	# 크기를 직접 박는다. CanvasLayer 밑의 Control 은 PRESET_FULL_RECT 만으로는
	# 사이즈가 잡히지 않아 (0,0) 으로 남는다 — 그러면 자식 ColorRect 의
	# 풀스크린 앵커도 0 이 되어 딤이 아예 안 그려지고, MOUSE_FILTER_STOP 도
	# 뒤쪽 입력을 못 막는다. 아레나 UI 는 어차피 1080×1920 절대 좌표계다.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = Vector2(VP_W, VP_H)

	# 1) 풀스크린 딤 — 아레나 밖(전장 · 핸드 행)을 눌러 준다.
	var dim := ColorRect.new()
	dim.color = DIM_COLOR
	dim.position = Vector2.ZERO
	dim.size = Vector2(VP_W, VP_H)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# 2) 아레나 뷰 — clip_contents 가 이 사각형 밖을 전부 잘라 낸다.
	_clip = Control.new()
	_clip.name = "ArenaView"
	_clip.position = VIEW_RECT.position
	_clip.size = VIEW_RECT.size
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)

	var backdrop := ColorRect.new()
	backdrop.color = VIEW_BACKDROP
	backdrop.position = Vector2.ZERO
	backdrop.size = VIEW_RECT.size
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(backdrop)

	# 3) 월드 — position/scale 이 곧 카메라 변환. 데미지 팝업도 여기 자식으로
	#    붙어서 카메라를 따라 움직이고 뷰 밖에서 함께 잘린다.
	_world = DrawProxy.new()
	_world.name = "ArenaWorld"
	_world.draw_fn = Callable(self, "draw_world")
	_clip.add_child(_world)

	# 4) 화면 좌표계 그래픽(뷰 테두리 · 남은 시간 바) — 딤과 클립 위.
	_hud = DrawProxy.new()
	_hud.name = "ArenaHud"
	_hud.draw_fn = Callable(self, "draw_hud")
	_hud.position = Vector2.ZERO
	add_child(_hud)

	_cam_min_zoom = minf(
			VIEW_RECT.size.x / (RealtimeEngageSim.ARENA_HALF.x * 2.0),
			VIEW_RECT.size.y / (RealtimeEngageSim.ARENA_HALF.y * 2.0))
	_cam_zoom = _cam_min_zoom
	_cam_target_zoom = _cam_min_zoom


func setup(bs: BattleSim, sim: RealtimeEngageSim, title_text: String,
		is_duel: bool) -> void:
	_bs = bs
	_sim = sim
	_is_duel = is_duel
	_build_ui(title_text)
	# 첫 프레임은 보간 없이 딱 맞춰 잡는다 — 아레나 중앙에서 스르륵 밀려오는
	# 연출은 교전 시작 순간을 놓치게 만든다.
	_update_camera(0.0, true)
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


func _process(delta: float) -> void:
	if _sim == null:
		return
	_refresh_header()
	_refresh_rows()
	_update_camera(delta, false)
	_drain_popups()
	_world.queue_redraw()
	_hud.queue_redraw()


# ─── 카메라 워킹 ─────────────────────────────────────────────────────────────
# 생존(= 미처치) 유닛 전원을 담는 바운딩 박스를 프레이밍한다. 흩어지면
# 축소되고 뭉치면 확대된다. 아레나 밖은 절대 보여 주지 않는다 —
# _clamp_cam_center 가 뷰를 아레나 사각형 안에 가둔다.
func _update_camera(delta: float, snap: bool) -> void:
	var pts := _focus_positions()
	if not pts.is_empty():
		var mn: Vector2 = pts[0]
		var mx: Vector2 = pts[0]
		for raw in pts:
			var p: Vector2 = raw
			mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
			mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
		var pad: float = RealtimeEngageSim.UNIT_RADIUS + CAM_PAD
		mn -= Vector2(pad, pad)
		mx += Vector2(pad, pad)
		var span: Vector2 = mx - mn
		_cam_target_zoom = clampf(minf(
					VIEW_RECT.size.x / maxf(1.0, span.x),
					VIEW_RECT.size.y / maxf(1.0, span.y)),
				_cam_min_zoom, CAM_MAX_ZOOM)
		_cam_target_center = (mn + mx) * 0.5
	# 유닛이 하나도 안 남았으면 마지막 타겟을 그대로 유지한다(화면이 튀지 않게).

	if snap:
		_cam_zoom = _cam_target_zoom
		_cam_center = _cam_target_center
	else:
		_cam_zoom = lerpf(_cam_zoom, _cam_target_zoom,
				1.0 - exp(-CAM_ZOOM_RATE * delta))
		_cam_center = _cam_center.lerp(_cam_target_center,
				1.0 - exp(-CAM_POS_RATE * delta))
	# 줌이 보간 중이어도 매 프레임 다시 가둔다 — 축소되는 동안 아레나 밖이
	# 잠깐 노출되는 것을 막는다.
	_cam_center = _clamp_cam_center(_cam_center, _cam_zoom)

	_world.scale = Vector2(_cam_zoom, _cam_zoom)
	_world.position = VIEW_RECT.size * 0.5 - _cam_center * _cam_zoom


func _focus_positions() -> Array:
	var out: Array = []
	for raw in _sim.units:
		var u := raw as RealtimeEngageSim.EUnit
		if u.is_active():
			out.append(u.pos)
	return out


# 뷰가 아레나 사각형 밖을 비추지 않도록 카메라 중심을 가둔다. 뷰가 아레나보다
# 넓은 축(= 최소 배율 근처)은 그냥 아레나 중앙에 고정한다.
static func _clamp_cam_center(c: Vector2, zoom: float) -> Vector2:
	var half: Vector2 = VIEW_RECT.size / (2.0 * maxf(0.01, zoom))
	var ac: Vector2 = RealtimeEngageSim.ARENA_CENTER
	var ah: Vector2 = RealtimeEngageSim.ARENA_HALF
	var out := c
	if half.x >= ah.x:
		out.x = ac.x
	else:
		out.x = clampf(c.x, ac.x - ah.x + half.x, ac.x + ah.x - half.x)
	if half.y >= ah.y:
		out.y = ac.y
	else:
		out.y = clampf(c.y, ac.y - ah.y + half.y, ac.y + ah.y - half.y)
	return out


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
		if _end_banner != "":
			_phase_lbl.text = _end_banner
		else:
			_phase_lbl.text = "교전 종료" if _sim.finished else ""


# 매니저가 종료 판정 직후(대시보드가 뜨기 END_HOLD_SEC 전에) 부른다.
# 상태 라벨을 종료 사유 배너로 승격시키고 한 번 튕겨 준다 — 유예 시간 자체가
# "지금 뭔가 끝났다"를 알아채라는 연출이므로 시선을 한 번 끌어 줘야 한다.
func mark_engage_over(reason: String) -> void:
	_end_banner = reason
	if _phase_lbl == null:
		return
	_phase_lbl.text = reason
	_phase_lbl.add_theme_font_size_override("font_size", 28)
	_phase_lbl.add_theme_color_override("font_color", TITLE_COLOR)
	_phase_lbl.position = Vector2(0, TIME_BAR_Y + TIME_BAR_H + 2.0)
	_phase_lbl.size = Vector2(VP_W, 40)
	_phase_lbl.pivot_offset = _phase_lbl.size * 0.5
	var tw := create_tween()
	tw.tween_property(_phase_lbl, "scale", Vector2(1.18, 1.18), 0.12) \
			.set_ease(Tween.EASE_OUT)
	tw.tween_property(_phase_lbl, "scale", Vector2.ONE, 0.18) \
			.set_ease(Tween.EASE_IN_OUT)


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
		fill.color = HP_BAR_FILL if ratio >= LOW_HP_RATIO \
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


static func _state_tag(u: RealtimeEngageSim.EUnit) -> String:
	match u.state:
		RealtimeEngageSim.State.DEAD:
			return "   (처치됨)"
		RealtimeEngageSim.State.DASH:
			return "   (대쉬)"
	return ""


# 시뮬레이터가 쌓아 둔 데미지 팝업을 Label 로 꺼내 띄우고 큐를 비운다.
func _drain_popups() -> void:
	for raw in _sim.popups:
		var e: Dictionary = raw
		_spawn_popup(e["pos"], String(e["text"]), e["color"])
	_sim.popups.clear()


# 팝업은 _world 의 자식(= 아레나 좌표계)이다. 카메라를 따라 움직이고 뷰 밖에서
# 잘린다. 대신 월드 스케일까지 같이 먹으므로 글자 크기가 배율에 휘둘리지
# 않도록 1/zoom 을 되먹여 화면상 크기를 고정한다.
func _spawn_popup(at: Vector2, text: String, color: Color) -> void:
	var lbl := _make_label(text, 30, color, HORIZONTAL_ALIGNMENT_CENTER)
	lbl.size = Vector2(240, 40)
	lbl.pivot_offset = lbl.size * 0.5
	lbl.scale = Vector2.ONE / maxf(0.01, _cam_zoom)
	lbl.position = Vector2(at.x - 120.0, at.y - 98.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(lbl)
	var rise: float = 54.0 / maxf(0.01, _cam_zoom)
	var tw := create_tween().set_parallel()
	tw.tween_property(lbl, "position:y", lbl.position.y - rise, 0.55) \
			.set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.55).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(Callable(lbl, "queue_free"))


# ─── 아레나 렌더링 (아레나 좌표계 · _world 에 그린다) ────────────────────────
func draw_world(c: CanvasItem) -> void:
	if _sim == null:
		return
	_draw_floor(c)
	_draw_cells(c)
	_draw_turrets(c)
	_draw_projectiles(c)
	_draw_units(c)


# ─── 화면 좌표계 렌더링 (_hud 에 그린다) ─────────────────────────────────────
func draw_hud(c: CanvasItem) -> void:
	if _sim == null:
		return
	_draw_view_frame(c)
	_draw_time_bar(c)


func _draw_floor(c: CanvasItem) -> void:
	var ac: Vector2 = RealtimeEngageSim.ARENA_CENTER
	var h: Vector2 = RealtimeEngageSim.ARENA_HALF
	var rect := Rect2(ac - h, h * 2.0)
	c.draw_rect(rect, FLOOR_BG, true)
	c.draw_rect(rect, FLOOR_EDGE, false, 2.0)


# 교전에 참여한 전장 셀을 육각 외곽선으로 깔아 준다 — 아레나 좌표가 전장
# 배치를 그대로 확대한 것임을 시각적으로 알려 주는 역할.
func _draw_cells(c: CanvasItem) -> void:
	var r: float = _sim.cell_radius
	for raw in _sim.area_cell_positions:
		var at: Vector2 = raw
		var pts := PackedVector2Array()
		for i in range(6):
			var a: float = TAU * float(i) / 6.0
			pts.append(at + Vector2(cos(a), sin(a)) * r)
		pts.append(pts[0])
		c.draw_polyline(pts, CELL_LINE, 2.0)


func _draw_turrets(c: CanvasItem) -> void:
	for raw in _sim.turrets:
		var t := raw as RealtimeEngageSim.ETurret
		var col: Color = TEAM_COLORS[t.team]
		# 사거리원 — 회피/다이브 판단의 근거를 화면에 그대로 노출한다.
		c.draw_circle(t.pos, RealtimeEngageSim.TURRET_RANGE, TURRET_ZONE)
		c.draw_arc(t.pos, RealtimeEngageSim.TURRET_RANGE, 0.0, TAU, 64,
				TURRET_EDGE, 2.0)
		# 포탑 본체 — 팀색 사각 + 밝은 코어.
		var s := 26.0
		c.draw_rect(Rect2(t.pos - Vector2(s, s), Vector2(s * 2.0, s * 2.0)),
				Color(0.10, 0.11, 0.16, 0.95), true)
		c.draw_rect(Rect2(t.pos - Vector2(s, s), Vector2(s * 2.0, s * 2.0)),
				col, false, 3.0)
		c.draw_circle(t.pos, 9.0, col)


func _draw_projectiles(c: CanvasItem) -> void:
	for raw in _sim.projectiles:
		var p: Dictionary = raw
		var f: float = clampf(float(p["t"]) / max(0.001, float(p["dur"])), 0.0, 1.0)
		var from: Vector2 = p["from"]
		var to: Vector2 = p["to"]
		var at: Vector2 = from.lerp(to, f)
		var col: Color = TEAM_COLORS[int(p["team"])]
		if bool(p["is_turret"]):
			col = Color(1.0, 0.72, 0.30)
			c.draw_line(from.lerp(to, max(0.0, f - 0.22)), at,
					col * Color(1, 1, 1, 0.55), 3.0)
			c.draw_circle(at, 9.0, col)
		else:
			c.draw_line(from.lerp(to, max(0.0, f - 0.18)), at,
					col * Color(1, 1, 1, 0.5), 2.5)
			c.draw_circle(at, 6.0, col)


func _draw_units(c: CanvasItem) -> void:
	for raw in _sim.units:
		var u := raw as RealtimeEngageSim.EUnit
		var dead: bool = (u.state == RealtimeEngageSim.State.DEAD)
		var alpha: float = 0.30 if dead else 1.0
		var col: Color = TEAM_COLORS[u.team]
		var r: float = RealtimeEngageSim.UNIT_RADIUS

		# 접지 그림자.
		c.draw_circle(u.pos + Vector2(0, r * 0.72),
				r * 0.72, Color(0, 0, 0, 0.30 * alpha))

		# 사거리 표시 — 살아 있고 근접이 아닌 유닛만(원거리 카이팅 가독성).
		if not dead and not u.is_melee:
			c.draw_arc(u.pos, u.atk_range, 0.0, TAU, 48,
					Color(col.r, col.g, col.b, 0.12), 1.5)

		# 대쉬 트레일.
		if u.state == RealtimeEngageSim.State.DASH:
			c.draw_line(u.pos - u.dash_dir * 70.0, u.pos,
					Color(1.0, 0.95, 0.6, 0.55), 6.0)

		# 초상.
		var portrait: Texture2D = PilotImages.circle_for(u.pilot.pilot_id)
		if portrait != null:
			c.draw_texture_rect(portrait,
					Rect2(u.pos - Vector2(r, r), Vector2(r * 2.0, r * 2.0)),
					false, Color(1, 1, 1, alpha))
		else:
			c.draw_circle(u.pos, r, Color(col.r, col.g, col.b, alpha))

		# 피격 플래시.
		if u.hit_flash > 0.0:
			c.draw_circle(u.pos, r + 3.0,
					Color(1.0, 0.35, 0.35, 0.45 * (u.hit_flash / 0.22)))

		# 공격 모션 — 바라보는 방향으로 짧은 호를 튀긴다.
		if u.swing_t > 0.0 and u.is_melee:
			var a0: float = u.facing.angle() - 0.6
			c.draw_arc(u.pos, r + 14.0, a0, a0 + 1.2, 16,
					Color(1.0, 0.95, 0.6, 0.85), 5.0)

		# 팀색 HP 링.
		var ring_w := 7.0
		var ring_r: float = r + ring_w * 0.5 + 1.0
		c.draw_arc(u.pos, ring_r, 0.0, TAU, 36,
				Color(0.15, 0.15, 0.15, alpha), ring_w)
		if not dead:
			var frac: float = u.hp_ratio()
			var start_a: float = -PI * 0.5
			c.draw_arc(u.pos, ring_r, start_a, start_a + TAU * frac, 36,
					col, ring_w)


# 뷰 테두리 — "여기까지가 아레나, 밖은 잘려 있다"를 명시한다.
func _draw_view_frame(c: CanvasItem) -> void:
	c.draw_rect(VIEW_RECT.grow(2.0), Color(0.0, 0.0, 0.0, 0.55), false, 6.0)
	c.draw_rect(VIEW_RECT, VIEW_FRAME, false, 2.0)


func _draw_time_bar(c: CanvasItem) -> void:
	if _is_duel:
		return
	var x: float = (VP_W - TIME_BAR_W) * 0.5
	c.draw_rect(Rect2(x, TIME_BAR_Y, TIME_BAR_W, TIME_BAR_H),
			Color(0.10, 0.11, 0.16, 0.95), true)
	var frac: float = 0.0
	if _sim.duration > 0.0:
		frac = clampf(_sim.time_left() / _sim.duration, 0.0, 1.0)
	c.draw_rect(Rect2(x, TIME_BAR_Y, TIME_BAR_W * frac, TIME_BAR_H),
			TIME_LOW if frac <= 0.25 else Color(0.45, 0.80, 0.95), true)
	c.draw_rect(Rect2(x, TIME_BAR_Y, TIME_BAR_W, TIME_BAR_H),
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
	var suffix := "  (처치됨)" if not p.alive else ""
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


# _draw 를 바깥으로 위임하기만 하는 껍데기 노드. draw_* 는 그 CanvasItem 이
# 그리기 상태일 때만 유효하므로, 아레나가 draw_fn 안에서 이 노드를 받아
# c.draw_*() 로 그린다.
#
# Control 이 아니라 Node2D 인 이유: Control 은 매 DRAW 통지마다 자기 크기로
# custom_rect 를 다시 박는다. 크기 0 인 Control 은 빈 사각형으로 컬링되어
# _draw 안의 그림이 통째로 사라진다. Node2D 는 실제 그린 커맨드에서 rect 를
# 잡으므로 카메라 변환 아래에서도 안전하다.
class DrawProxy extends Node2D:
	var draw_fn: Callable = Callable()

	func _draw() -> void:
		if draw_fn.is_valid():
			draw_fn.call(self)
