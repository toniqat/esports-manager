class_name EngageArena
extends Control

# 실시간 교전 아레나 — RealtimeEngageSim 의 상태를 그리기만 한다.
# 게임 상태 변경은 전부 시뮬레이터/매니저 쪽에서 일어난다.
#
# **사이드뷰 벨트스크롤**: 무대는 화면 중앙의 가로로 납작한 시네마 밴드
# (`BAND_RECT`) 하나뿐이고, 그 안에서 팀0(아군)이 왼쪽 · 팀1(적군)이 오른쪽을
# 보고 마주 선다. 밴드 아래에는 교전 참가자 전원의 원형 초상화가 팀별로
# 깔리고 그 밑에 체력 바가 붙는다.
#
# 텍스트는 전부 Label 노드로 만든다(draw_string 은 한글 폴백 폰트를 태우기
# 어렵다). 그래픽은 세 개의 DrawProxy 노드가 나눠 그린다:
#
#   _clip (clip_contents=true, BAND_RECT)   ← 무대 밖은 여기서 잘린다
#     └ _world (position/scale = 카메라)     ← draw_world()  : 벨트 좌표계
#   _hud    (풀스크린)                        ← draw_hud()    : 화면 좌표계
#   _roster (풀스크린)                        ← draw_roster() : 하단 초상화 스트립
#
# 자기 자신(_draw)에 그리지 않는 이유: Control 은 자기 그림을 먼저 그리고 그
# 위에 자식을 그린다. 풀스크린 딤 ColorRect 가 자식이므로 자기 _draw 로 그린
# 무대는 딤 아래에 깔려 버린다. 딤보다 뒤에 붙은 프록시 노드에 그려야
# "무대 밖만 딤드"가 성립한다.

const VP_W: float = 1080.0
const VP_H: float = 1920.0

const TEAM_COLORS := [
	Color(0.32, 0.62, 0.95),   # team 0 (player)
	Color(0.95, 0.40, 0.32),   # team 1 (enemy)
]
const TITLE_COLOR   := Color(1.0, 0.95, 0.55, 1.0)
const TIME_COLOR    := Color(0.92, 0.96, 1.0, 1.0)
const TIME_LOW      := Color(1.0, 0.55, 0.40, 1.0)
const HP_BAR_BG     := Color(0.06, 0.06, 0.08, 1.0)
const HP_BAR_FILL   := Color(0.30, 0.85, 0.45, 1.0)
const HP_BAR_LOW    := Color(0.90, 0.55, 0.25, 1.0)
const SHIELD_FILL   := Color(0.85, 0.85, 0.30, 0.85)
## HP 바가 경고색으로 바뀌는 비율.
const LOW_HP_RATIO: float = 0.30

# ─── 무대 (시네마 밴드) ──────────────────────────────────────────────────────
## 교전 그래픽이 그려지는 유일한 사각형. 이 밖으로 나간 것은 잘린다.
## 위로는 남은 시간 바 / 배너를, 아래로는 초상화 스트립을 피한다.
## 세로 1920 화면에서 위아래로 딤을 남기는 "시네마 밴드". 벨트(1240×400)가
## 가로로 딱 차고 세로로 약간 여유가 남는 비율로 잡혀 있다.
const BAND_RECT := Rect2(24.0, 440.0, 1032.0, 500.0)
const BAND_FRAME    := Color(0.45, 0.53, 0.72, 0.90)
## 무대 밖 화면(전장 · 핸드 행 등)을 덮는 딤.
const DIM_COLOR     := Color(0.0, 0.0, 0.0, 0.86)

# 배경 / 바닥 색 — 위(먼 곳)에서 아래(가까운 곳)로 갈수록 밝아진다.
# 지평선 위의 뒷벽을 바닥보다 **어둡게** 잡아야 사이드뷰의 깊이가 읽힌다.
const SKY_TOP       := Color(0.02, 0.03, 0.06, 1.0)
const SKY_BOTTOM    := Color(0.06, 0.07, 0.13, 1.0)
## 지평선 바로 위의 뒷벽 띠.
const BACKWALL      := Color(0.09, 0.10, 0.17, 1.0)
const BACKWALL_H: float = 120.0
const GROUND_FAR    := Color(0.17, 0.19, 0.28, 1.0)
const GROUND_NEAR   := Color(0.26, 0.29, 0.39, 1.0)
const HORIZON_LINE  := Color(0.52, 0.60, 0.80, 0.85)
## 좌우 진영 바닥에 얹는 팀색 틴트 강도.
const SIDE_TINT_A: float = 0.16
## 바닥 깊이감을 주는 가로 스캔라인 간격(벨트 px).
const FLOOR_LINE_STEP: float = 72.0
const FLOOR_LINE_COLOR := Color(0.55, 0.62, 0.80, 0.09)
## 벨트 위쪽(먼 배경)으로 더 그려 두는 높이 — 카메라가 위를 비출 때 빈칸이
## 생기지 않게 한다.
const BG_ABOVE: float = 420.0
## 벨트 아래쪽(가까운 전경)으로 더 그려 두는 높이.
const BG_BELOW: float = 200.0

# ─── 카메라 ──────────────────────────────────────────────────────────────────
## 최대 확대 배율. 최소 배율은 "벨트 전체가 밴드에 들어가는 배율"로 계산한다.
const CAM_MAX_ZOOM: float = 1.55
## 프레이밍 여백(벨트 px). 사이드뷰라 가로로 넉넉히, 세로로는 좁게 잡는다.
const CAM_PAD_X: float = 80.0
const CAM_PAD_Y: float = 40.0
## 지수 감쇠 추종 계수(1/s). 줌이 더 느린 이유는 유닛 하나가 잠깐 튀었다고
## 화면 배율이 출렁이면 멀미가 나기 때문.
const CAM_POS_RATE: float = 4.0
const CAM_ZOOM_RATE: float = 2.6

# ─── 하단 초상화 스트립 ──────────────────────────────────────────────────────
## 팀별 헤더 y 좌표와 초상화 행 y 좌표.
const STRIP_HEADER_Y := [976.0, 1258.0]
const STRIP_ROW_Y    := [1010.0, 1292.0]
const STRIP_LEFT: float = 24.0
const STRIP_WIDTH: float = 1032.0
## 한 참가자가 차지하는 칸 폭(최대 5명 기준).
const STRIP_CELL_W: float = 206.0
const STRIP_PORTRAIT: float = 150.0
const STRIP_HP_W: float = 168.0
const STRIP_HP_H: float = 18.0
## 초상화 아래 체력 바까지의 간격.
const STRIP_HP_GAP: float = 10.0

# ─── 포탑(배경 지형) ─────────────────────────────────────────────────────────
## 탑신 높이(축소 전). 총구 높이 = 이 값 × TURRET_BG_SCALE 이며 포격 투사체의
## 출발점(_shot_origin)도 같은 값을 쓴다.
const TURRET_BODY_H: float = 128.0
## 배경 지형에 선 구조물이므로 원근감을 위해 이만큼 줄여 그린다. 카메라가
## 유닛만 프레이밍하므로 탑신이 유닛 초상화보다 높으면 밴드 위로 잘린다.
const TURRET_BG_SCALE: float = 0.58
## 탑신 색 — 뒷벽(BACKWALL)보다 **밝게** 잡아야 벽 앞에 선 구조물로 읽힌다.
## 벽보다 어둡게 두면 실루엣이 벽에 먹혀 포탑이 사라진 것처럼 보인다.
const TURRET_BODY_COLOR := Color(0.15, 0.17, 0.24, 1.0)

# ─── 유닛 연출 ───────────────────────────────────────────────────────────────
## 초상화 원의 중심은 발밑(pos)에서 이만큼 위에 뜬다.
const UNIT_LIFT: float = 42.0
## 행동 중(돌진/타격) 유닛에 두르는 강조 링.
const ACT_RING_COLOR := Color(1.0, 0.92, 0.55, 0.85)

var _bs: BattleSim = null
var _sim: RealtimeEngageSim = null
var _is_duel: bool = false

## 무대 노드 — _ready 에서 만든다.
var _clip: Control = null
var _world: DrawProxy = null
var _hud: DrawProxy = null
var _roster: DrawProxy = null

## 카메라 상태 (벨트 좌표계 기준).
var _cam_center: Vector2 = Vector2.ZERO
var _cam_zoom: float = 1.0
var _cam_target_center: Vector2 = Vector2.ZERO
var _cam_target_zoom: float = 1.0
var _cam_min_zoom: float = 1.0

var _time_lbl: Label = null
var _phase_lbl: Label = null
## 종료 유예 동안 상단에 띄우는 배너(빈 문자열 = 아직 전투 중).
var _end_banner: String = ""
## 초상화 스트립 이름 라벨. _name_labels[PilotData] = Label
var _name_labels: Dictionary = {}
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

	# 1) 풀스크린 딤 — 무대 밖(전장 · 핸드 행)을 눌러 준다.
	var dim := ColorRect.new()
	dim.color = DIM_COLOR
	dim.position = Vector2.ZERO
	dim.size = Vector2(VP_W, VP_H)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# 2) 무대 — clip_contents 가 이 사각형 밖을 전부 잘라 낸다.
	_clip = Control.new()
	_clip.name = "ArenaBand"
	_clip.position = BAND_RECT.position
	_clip.size = BAND_RECT.size
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)

	# 3) 월드 — position/scale 이 곧 카메라 변환. 데미지 팝업도 여기 자식으로
	#    붙어서 카메라를 따라 움직이고 무대 밖에서 함께 잘린다.
	_world = DrawProxy.new()
	_world.name = "BeltWorld"
	_world.draw_fn = Callable(self, "draw_world")
	_clip.add_child(_world)

	# 4) 화면 좌표계 그래픽 — 무대 테두리 · 남은 시간 바.
	_hud = DrawProxy.new()
	_hud.name = "ArenaHud"
	_hud.draw_fn = Callable(self, "draw_hud")
	_hud.position = Vector2.ZERO
	add_child(_hud)

	# 5) 하단 초상화 스트립 — 초상화 · 체력 바(이름만 Label).
	_roster = DrawProxy.new()
	_roster.name = "RosterStrip"
	_roster.draw_fn = Callable(self, "draw_roster")
	_roster.position = Vector2.ZERO
	add_child(_roster)

	var belt := RealtimeEngageSim.belt_rect()
	_cam_min_zoom = minf(BAND_RECT.size.x / belt.size.x,
			BAND_RECT.size.y / belt.size.y)
	_cam_center = belt.get_center()
	_cam_target_center = _cam_center
	_cam_zoom = _cam_min_zoom
	_cam_target_zoom = _cam_min_zoom


func setup(bs: BattleSim, sim: RealtimeEngageSim, title_text: String,
		is_duel: bool) -> void:
	_bs = bs
	_sim = sim
	_is_duel = is_duel
	_build_ui(title_text)
	# 첫 프레임은 보간 없이 딱 맞춰 잡는다 — 무대 중앙에서 스르륵 밀려오는
	# 연출은 교전 시작 순간을 놓치게 만든다.
	_update_camera(0.0, true)
	set_process(true)


func _build_ui(title_text: String) -> void:
	var title := _make_label(title_text, 40, TITLE_COLOR,
			HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, 240)
	title.size = Vector2(VP_W, 56)
	add_child(title)

	_time_lbl = _make_label("", 46, TIME_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_time_lbl.position = Vector2(0, 296)
	_time_lbl.size = Vector2(VP_W, 56)
	add_child(_time_lbl)

	_phase_lbl = _make_label("", 24, Color(0.85, 0.85, 0.9),
			HORIZONTAL_ALIGNMENT_CENTER)
	_phase_lbl.position = Vector2(0, 390)
	_phase_lbl.size = Vector2(VP_W, 32)
	add_child(_phase_lbl)

	for t in range(2):
		var hdr := _make_label("아군" if t == 0 else "적군", 26, TEAM_COLORS[t],
				HORIZONTAL_ALIGNMENT_LEFT)
		hdr.position = Vector2(STRIP_LEFT + 6.0, STRIP_HEADER_Y[t])
		hdr.size = Vector2(STRIP_WIDTH, 30)
		add_child(hdr)

		var team_units: Array = _sim.units_of(t)
		for i in team_units.size():
			var u := team_units[i] as RealtimeEngageSim.EUnit
			var cx: float = _strip_cell_x(team_units.size(), i)
			var lbl := _make_label("", 19, TEAM_COLORS[t],
					HORIZONTAL_ALIGNMENT_CENTER)
			lbl.position = Vector2(cx - STRIP_CELL_W * 0.5,
					STRIP_ROW_Y[t] + STRIP_PORTRAIT + STRIP_HP_GAP
							+ STRIP_HP_H + 4.0)
			lbl.size = Vector2(STRIP_CELL_W, 26)
			add_child(lbl)
			_name_labels[u.pilot] = lbl


# 참가 인원이 5명 미만이면 남는 칸을 양쪽으로 나눠 가운데 정렬한다.
static func _strip_cell_x(count: int, idx: int) -> float:
	var total: float = float(count) * STRIP_CELL_W
	var x0: float = STRIP_LEFT + (STRIP_WIDTH - total) * 0.5
	return x0 + STRIP_CELL_W * (float(idx) + 0.5)


func _process(delta: float) -> void:
	if _sim == null:
		return
	_refresh_header()
	_refresh_names()
	_update_camera(delta, false)
	_drain_popups()
	_world.queue_redraw()
	_hud.queue_redraw()
	_roster.queue_redraw()


# ─── 카메라 ──────────────────────────────────────────────────────────────────
# 생존(= 미처치) 유닛 전원을 담는 바운딩 박스를 프레이밍한다. **포탑은 넣지
# 않는다** — 포탑은 무대 참가자가 아니라 배경 지형이고, 프레임에 넣으면 벨트
# 양 끝까지 담느라 배율이 떨어져 정작 싸우는 유닛이 잘게 보인다.
# 무대 밖은 보여 주지 않는다 — _clamp_cam_center 가 뷰를 stage_rect(벨트 +
# 포탑이 선 배경 지형) 안에 가둔다.
func _update_camera(delta: float, snap: bool) -> void:
	var pts := _focus_positions()
	if not pts.is_empty():
		var mn: Vector2 = pts[0]
		var mx: Vector2 = pts[0]
		for raw in pts:
			var p: Vector2 = raw
			mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
			mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
		var pad := Vector2(RealtimeEngageSim.UNIT_RADIUS + CAM_PAD_X,
				RealtimeEngageSim.UNIT_RADIUS + CAM_PAD_Y)
		mn -= pad
		mx += pad
		var span: Vector2 = mx - mn
		_cam_target_zoom = clampf(minf(
					BAND_RECT.size.x / maxf(1.0, span.x),
					BAND_RECT.size.y / maxf(1.0, span.y)),
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
	# 줌이 보간 중이어도 매 프레임 다시 가둔다 — 축소되는 동안 벨트 밖이
	# 잠깐 노출되는 것을 막는다.
	_cam_center = _clamp_cam_center(_cam_center, _cam_zoom)

	_world.scale = Vector2(_cam_zoom, _cam_zoom)
	_world.position = BAND_RECT.size * 0.5 - _cam_center * _cam_zoom


func _focus_positions() -> Array:
	var out: Array = []
	for raw in _sim.units:
		var u := raw as RealtimeEngageSim.EUnit
		if u.is_active():
			out.append(u.pos)
	return out


# 뷰가 무대 밖(= 그려진 것이 없는 곳)을 비추지 않도록 카메라 중심을 가둔다.
# 기준은 belt_rect 가 아니라 stage_rect — 벨트 위쪽으로 포탑이 선 배경 지형만큼
# 더 열려 있다. belt_rect 로 가두면 지평선 너머의 포탑이 어떤 배율에서도 화면에
# 들어오지 못한다. 뷰가 무대보다 넓은 축(= 최소 배율 근처)은 그냥 중앙에 고정한다.
static func _clamp_cam_center(c: Vector2, zoom: float) -> Vector2:
	var half: Vector2 = BAND_RECT.size / (2.0 * maxf(0.01, zoom))
	var stage := RealtimeEngageSim.stage_rect()
	var bc: Vector2 = stage.get_center()
	var bh: Vector2 = stage.size * 0.5
	var out := c
	if half.x >= bh.x:
		out.x = bc.x
	else:
		out.x = clampf(c.x, bc.x - bh.x + half.x, bc.x + bh.x - half.x)
	if half.y >= bh.y:
		out.y = bc.y
	else:
		out.y = clampf(c.y, bc.y - bh.y + half.y, bc.y + bh.y - half.y)
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
	_phase_lbl.add_theme_font_size_override("font_size", 30)
	_phase_lbl.add_theme_color_override("font_color", TITLE_COLOR)
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


func _refresh_names() -> void:
	for key in _name_labels:
		var p := key as PilotData
		var lbl := _name_labels[key] as Label
		var dead: bool = not p.alive
		lbl.text = "%s%s" % [_bs.pilot_label(p), "  (처치)" if dead else ""]
		lbl.modulate = Color(0.62, 0.48, 0.48) if dead else Color.WHITE


# 시뮬레이터가 쌓아 둔 데미지 팝업을 Label 로 꺼내 띄우고 큐를 비운다.
func _drain_popups() -> void:
	for raw in _sim.popups:
		var e: Dictionary = raw
		_spawn_popup(e["pos"], String(e["text"]), e["color"])
	_sim.popups.clear()


# 팝업은 _world 의 자식(= 벨트 좌표계)이다. 카메라를 따라 움직이고 무대 밖에서
# 잘린다. 대신 월드 스케일까지 같이 먹으므로 글자 크기가 배율에 휘둘리지
# 않도록 1/zoom 을 되먹여 화면상 크기를 고정한다.
func _spawn_popup(at: Vector2, text: String, color: Color) -> void:
	var lbl := _make_label(text, 30, color, HORIZONTAL_ALIGNMENT_CENTER)
	lbl.size = Vector2(240, 40)
	lbl.pivot_offset = lbl.size * 0.5
	lbl.scale = Vector2.ONE / maxf(0.01, _cam_zoom)
	lbl.position = Vector2(at.x - 120.0,
			at.y - UNIT_LIFT - RealtimeEngageSim.UNIT_RADIUS - 76.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(lbl)
	var rise: float = 54.0 / maxf(0.01, _cam_zoom)
	var tw := create_tween().set_parallel()
	tw.tween_property(lbl, "position:y", lbl.position.y - rise, 0.55) \
			.set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.55).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(Callable(lbl, "queue_free"))


# ─── 무대 렌더링 (벨트 좌표계 · _world 에 그린다) ────────────────────────────
func draw_world(c: CanvasItem) -> void:
	if _sim == null:
		return
	_draw_backdrop(c)
	_draw_floor(c)
	_draw_turrets(c)
	_draw_projectiles(c)
	_draw_units(c)


# 먼 배경 — 벨트 위쪽으로 BG_ABOVE 만큼 더 그려 둔다. 카메라가 위를 비출 때
# 빈칸이 생기지 않게 하는 것이 주 목적이고, 지평선 바로 위의 뒷벽 띠가
# "여기서부터 바닥"을 읽히게 한다.
func _draw_backdrop(c: CanvasItem) -> void:
	var belt := RealtimeEngageSim.belt_rect()
	var x0: float = -BG_ABOVE
	var w: float = belt.size.x + BG_ABOVE * 2.0
	_draw_vgradient(c, Rect2(x0, -BG_ABOVE, w, BG_ABOVE - BACKWALL_H),
			SKY_TOP, SKY_BOTTOM, 8)
	# 뒷벽 — 바닥보다 어둡게 깔아 대비를 만든다.
	c.draw_rect(Rect2(x0, -BACKWALL_H, w, BACKWALL_H), BACKWALL, true)
	# 뒷벽에 세로 기둥을 일정 간격으로 세워 가로 이동이 눈에 보이게 한다.
	var px: float = 0.0
	while px <= belt.size.x:
		c.draw_line(Vector2(px, -BACKWALL_H), Vector2(px, 0.0),
				Color(0.30, 0.36, 0.50, 0.20), 3.0)
		px += 155.0
	# 지평선 — 여기서부터가 바닥이다.
	c.draw_line(Vector2(x0, 0.0), Vector2(belt.size.x + BG_ABOVE, 0.0),
			HORIZON_LINE, 2.5)


# 바닥 — 위(먼 곳)에서 아래(가까운 곳)로 밝아지고, 좌우 절반에 팀색을 얹는다.
func _draw_floor(c: CanvasItem) -> void:
	var belt := RealtimeEngageSim.belt_rect()
	var w: float = belt.size.x
	var h: float = belt.size.y
	_draw_vgradient(c, Rect2(-BG_ABOVE, 0.0, w + BG_ABOVE * 2.0, h + BG_BELOW),
			GROUND_FAR, GROUND_NEAR, 12)

	# 진영 틴트 — 어느 쪽이 누구 땅인지 한눈에.
	var half := w * 0.5
	c.draw_rect(Rect2(-BG_ABOVE, 0.0, half + BG_ABOVE, h + BG_BELOW),
			Color(TEAM_COLORS[0].r, TEAM_COLORS[0].g, TEAM_COLORS[0].b,
					SIDE_TINT_A), true)
	c.draw_rect(Rect2(half, 0.0, half + BG_ABOVE, h + BG_BELOW),
			Color(TEAM_COLORS[1].r, TEAM_COLORS[1].g, TEAM_COLORS[1].b,
					SIDE_TINT_A), true)
	# 중앙선.
	c.draw_line(Vector2(half, 0.0), Vector2(half, h + BG_BELOW),
			Color(0.75, 0.80, 0.95, 0.16), 3.0)

	# 깊이감을 주는 가로선.
	var y: float = FLOOR_LINE_STEP
	while y < h + BG_BELOW:
		c.draw_line(Vector2(-BG_ABOVE, y), Vector2(w + BG_ABOVE, y),
				FLOOR_LINE_COLOR, 1.5)
		y += FLOOR_LINE_STEP


static func _draw_vgradient(c: CanvasItem, rect: Rect2, top: Color,
		bottom: Color, steps: int) -> void:
	var n: int = max(1, steps)
	var band_h: float = rect.size.y / float(n)
	for i in n:
		var f: float = float(i) / float(max(1, n - 1))
		c.draw_rect(Rect2(rect.position.x, rect.position.y + band_h * float(i),
				rect.size.x, band_h + 1.0), top.lerp(bottom, f), true)


# 참가 포탑 — **무대 참가자가 아니라 배경 지형 구조물**이다. 시뮬레이터가
# 지평선 너머(y < 0)에 세워 두고, 여기서는 유닛보다 먼저(= 뒤에) 원근감을 위해
# 축소해 그린다. 사거리원은 없다(사거리 제한 없음).
func _draw_turrets(c: CanvasItem) -> void:
	for raw in _sim.turrets:
		var t := raw as RealtimeEngageSim.ETurret
		var col: Color = TEAM_COLORS[t.team]
		var base: Vector2 = t.pos
		var s: float = TURRET_BG_SCALE
		# 지형 위 설치대 — 먼 바닥에 얹힌 납작한 받침.
		_draw_ellipse(c, base, Vector2(46.0 * s, 13.0 * s), Color(0, 0, 0, 0.34))
		_draw_ellipse(c, base + Vector2(0.0, -4.0 * s),
				Vector2(40.0 * s, 11.0 * s), Color(0.13, 0.15, 0.21, 1.0))
		# 탑신 — 아래가 넓은 사다리꼴. 먼 배경이므로 뒷벽 쪽으로 살짝 가라앉힌다.
		var h: float = TURRET_BODY_H * s
		var body := PackedVector2Array([
			base + Vector2(-34.0 * s, 0.0),
			base + Vector2(-22.0 * s, -h),
			base + Vector2(22.0 * s, -h),
			base + Vector2(34.0 * s, 0.0),
		])
		c.draw_colored_polygon(body, TURRET_BODY_COLOR)
		var outline := body.duplicate()
		outline.append(body[0])
		c.draw_polyline(outline, Color(col.r, col.g, col.b, 0.85), 3.0 * s)
		# 포신 — 적진 쪽을 향한다.
		var muzzle_dir: float = 1.0 if t.team == 0 else -1.0
		var muzzle := base + Vector2(0.0, -h)
		var tip := muzzle + Vector2(46.0 * s * muzzle_dir, 4.0 * s)
		c.draw_line(muzzle, tip, Color(col.r, col.g, col.b, 0.9), 7.0 * s)
		c.draw_circle(muzzle, 12.0 * s, Color(col.r, col.g, col.b, 0.9))
		# 사격 순간 — 총구 섬광.
		if t.fire_t > 0.0:
			var f: float = clampf(t.fire_t / 0.25, 0.0, 1.0)
			c.draw_circle(tip, 16.0 * s * f, Color(1.0, 0.85, 0.45, 0.85 * f))


func _draw_projectiles(c: CanvasItem) -> void:
	for raw in _sim.projectiles:
		var p: Dictionary = raw
		var f: float = clampf(float(p["t"]) / max(0.001, float(p["dur"])), 0.0, 1.0)
		var from: Vector2 = _shot_origin(p)
		var to: Vector2 = _shot_impact(p)
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


# 투사체 좌표는 시뮬레이터가 발밑 기준으로 넘긴다 — 그림에서는 몸통 높이로
# 띄워야 발에서 발로 날아가는 그림이 되지 않는다.
static func _shot_origin(p: Dictionary) -> Vector2:
	var from: Vector2 = p["from"]
	if bool(p["is_turret"]):
		# 배경 지형에 선 포탑의 총구 높이 — _draw_turrets 와 같은 식이라야
		# 포격선이 포신에서 출발한다.
		return from + Vector2(0.0, -TURRET_BODY_H * TURRET_BG_SCALE)
	return from + Vector2(0.0, -UNIT_LIFT)


static func _shot_impact(p: Dictionary) -> Vector2:
	return (p["to"] as Vector2) + Vector2(0.0, -UNIT_LIFT)


# 사이드뷰라 **깊이(y) 순으로 정렬**해서 그린다 — 아래쪽(가까운) 유닛이 위에
# 겹친다. 시뮬레이터의 units 배열 순서는 팀별이라 그대로 그리면 원근이 깨진다.
func _draw_units(c: CanvasItem) -> void:
	var order: Array = _sim.units.duplicate()
	order.sort_custom(func(a, b):
		return (a as RealtimeEngageSim.EUnit).pos.y \
				< (b as RealtimeEngageSim.EUnit).pos.y)
	for raw in order:
		_draw_unit(c, raw as RealtimeEngageSim.EUnit)


func _draw_unit(c: CanvasItem, u: RealtimeEngageSim.EUnit) -> void:
	var dead: bool = (u.state == RealtimeEngageSim.State.DEAD)
	var alpha: float = 0.28 if dead else 1.0
	var col: Color = TEAM_COLORS[u.team]
	var r: float = RealtimeEngageSim.UNIT_RADIUS
	var body: Vector2 = u.pos + Vector2(0.0, -UNIT_LIFT)

	# 접지 그림자 — 발밑에 납작한 타원.
	_draw_ellipse(c, u.pos, Vector2(r * 0.92, r * 0.34),
			Color(0, 0, 0, 0.34 * alpha))

	# 행동 중 강조 — ATB 가 차서 나와 있는 유닛.
	if not dead and u.is_acting():
		c.draw_arc(body, r + 10.0, 0.0, TAU, 40,
				Color(ACT_RING_COLOR.r, ACT_RING_COLOR.g, ACT_RING_COLOR.b,
						0.55), 4.0)

	# 초상.
	var portrait: Texture2D = PilotImages.circle_for(u.pilot.pilot_id)
	if portrait != null:
		c.draw_texture_rect(portrait,
				Rect2(body - Vector2(r, r), Vector2(r * 2.0, r * 2.0)),
				false, Color(1, 1, 1, alpha))
	else:
		c.draw_circle(body, r, Color(col.r, col.g, col.b, alpha))

	# 팀색 테두리 — 빈사면 붉게 맥동한다.
	var rim: Color = col
	if not dead and u.hp_ratio() < LOW_HP_RATIO:
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
		rim = col.lerp(Color(1.0, 0.35, 0.30), 0.35 + 0.45 * pulse)
	c.draw_arc(body, r + 3.0, 0.0, TAU, 40, Color(rim.r, rim.g, rim.b, alpha), 5.0)

	# 바라보는 방향 표시 — 사이드뷰에서 좌우 구분이 유일한 방향 정보다.
	if not dead:
		var tip: Vector2 = body + Vector2((r + 16.0) * u.facing_x, 0.0)
		var back: float = (r + 4.0) * u.facing_x
		c.draw_colored_polygon(PackedVector2Array([
			tip,
			body + Vector2(back, -9.0),
			body + Vector2(back, 9.0),
		]), Color(col.r, col.g, col.b, 0.85 * alpha))

	# 피격 플래시.
	if u.hit_flash > 0.0:
		var k: float = u.hit_flash / RealtimeEngageSim.KNOCK_FLASH_SEC
		c.draw_circle(body, r + 6.0, Color(1.0, 0.35, 0.35, 0.45 * k))

	# 공격 모션 — 근접은 휘두르는 호, 원거리는 총구 섬광.
	if u.swing_t > 0.0:
		var s: float = clampf(u.swing_t / 0.22, 0.0, 1.0)
		if u.is_melee:
			var a0: float = (0.0 if u.facing_x > 0.0 else PI) - 0.7
			c.draw_arc(body, r + 18.0, a0, a0 + 1.4, 18,
					Color(1.0, 0.95, 0.6, 0.85 * s), 6.0)
		else:
			c.draw_circle(body + Vector2((r + 10.0) * u.facing_x, 0.0),
					13.0 * s, Color(1.0, 0.9, 0.55, 0.8 * s))


static func _draw_ellipse(c: CanvasItem, at: Vector2, radii: Vector2,
		col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(20):
		var a: float = TAU * float(i) / 20.0
		pts.append(at + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	c.draw_colored_polygon(pts, col)


# ─── 화면 좌표계 렌더링 (_hud 에 그린다) ─────────────────────────────────────
func draw_hud(c: CanvasItem) -> void:
	if _sim == null:
		return
	# 무대 테두리 — "여기까지가 무대, 밖은 잘려 있다"를 명시한다.
	c.draw_rect(BAND_RECT.grow(2.0), Color(0.0, 0.0, 0.0, 0.55), false, 6.0)
	c.draw_rect(BAND_RECT, BAND_FRAME, false, 2.0)
	_draw_time_bar(c)


const TIME_BAR_W: float = 560.0
const TIME_BAR_H: float = 12.0
const TIME_BAR_Y: float = 368.0

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


# ─── 하단 초상화 스트립 (_roster 에 그린다) ──────────────────────────────────
# 교전 참가자 전원을 팀별로 한 줄씩. 초상화 아래에 체력 바(+보호막)가 붙는다.
func draw_roster(c: CanvasItem) -> void:
	if _sim == null:
		return
	for t in range(2):
		var team_units: Array = _sim.units_of(t)
		for i in team_units.size():
			_draw_roster_cell(c, team_units[i] as RealtimeEngageSim.EUnit,
					_strip_cell_x(team_units.size(), i), STRIP_ROW_Y[t])


func _draw_roster_cell(c: CanvasItem, u: RealtimeEngageSim.EUnit, cx: float,
		y: float) -> void:
	var p: PilotData = u.pilot
	var dead: bool = (u.state == RealtimeEngageSim.State.DEAD)
	var alpha: float = 0.35 if dead else 1.0
	var col: Color = TEAM_COLORS[u.team]
	var r: float = STRIP_PORTRAIT * 0.5
	var centre := Vector2(cx, y + r)

	# 초상 뒤판 — 죽으면 붉게 가라앉는다.
	c.draw_circle(centre, r + 4.0,
			Color(0.18, 0.09, 0.09, 0.95) if dead else Color(0.09, 0.11, 0.17, 0.95))

	var portrait: Texture2D = PilotImages.circle_for(p.pilot_id)
	if portrait != null:
		c.draw_texture_rect(portrait,
				Rect2(centre - Vector2(r, r), Vector2(r * 2.0, r * 2.0)),
				false, Color(1, 1, 1, alpha))
	else:
		c.draw_circle(centre, r, Color(col.r, col.g, col.b, alpha))

	# 테두리 — 행동 중이면 금색으로 승격된다(무대에서 나와 있는 그 유닛이다).
	var rim: Color = ACT_RING_COLOR if (not dead and u.is_acting()) else col
	c.draw_arc(centre, r + 3.0, 0.0, TAU, 44, Color(rim.r, rim.g, rim.b, alpha),
			4.0)

	# 체력 바 — 초상화 바로 아래.
	var bar_x: float = cx - STRIP_HP_W * 0.5
	var bar_y: float = y + STRIP_PORTRAIT + STRIP_HP_GAP
	c.draw_rect(Rect2(bar_x, bar_y, STRIP_HP_W, STRIP_HP_H), HP_BAR_BG, true)
	var ratio: float = u.hp_ratio()
	var fill_w: float = STRIP_HP_W * ratio
	c.draw_rect(Rect2(bar_x, bar_y, fill_w, STRIP_HP_H),
			HP_BAR_FILL if ratio >= LOW_HP_RATIO else HP_BAR_LOW, true)
	# 보호막은 남은 체력 바 오른쪽에 이어 붙인다.
	if p.shield > 0 and p.max_hp > 0:
		var shield_w: float = STRIP_HP_W * clampf(
				float(p.shield) / float(p.max_hp), 0.0, 1.0)
		c.draw_rect(Rect2(bar_x + fill_w, bar_y, shield_w, STRIP_HP_H),
				SHIELD_FILL, true)
	c.draw_rect(Rect2(bar_x, bar_y, STRIP_HP_W, STRIP_HP_H),
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
