class_name JungleStartOverlay
extends Node

## 플레이어가 "전투 시작"을 눌렀다. `GambitPhaseManager` 가 받아 방향을
## 정글러에게 새기고(`commit()`) 전장을 개시한다 — 이 모듈은 무엇을 골랐는지만
## 알지, 그 다음에 무엇이 일어나는지는 모른다.
signal start_pressed

# 정글 시작 방향 — **전장 위에서 고른다.**
#
# 개시 직전(`game_phase == GAMBIT`) 한 번 열리는 화면이다. 전장은 이미 다 서
# 있고(파일럿 · 포탑 · 정글 소유 · 캠프), HUD 에서 **지금 쓸 수 없는 것들만
# 숨는다** — 손패 자리의 덱 / 버린 더미 뭉치, 전략 포인트 도넛 둘, 상단의
# 오브젝트 등장 시계 둘. 아직 카드도 점수도 오브젝트도 없는 시점이라 그 셋은
# 숫자 0 을 보여 주는 것 말고 하는 일이 없다.
#
# 비워진 **손패 자리에 아군 정글러의 원형 초상화**가 놓인다 — 전장 마커와
# 같은 `circle` 컷이라 "지금 옮기려는 것이 저 사람"이 그림 하나로 읽힌다.
# 그걸 끌어다 **좌측 정글 / 우측 정글** 중 한쪽에 놓으면 그 방향이 선택되고,
# 초상화가 그 정글 한가운데에 앉는다. 확정은 그 아래 "전투 시작" 버튼이다 —
# 드롭 하나로 곧장 개시하면 잘못 놓은 손가락이 경기를 시작해 버린다.
#
# **드롭 대상은 칸이 아니라 무리다.** 좌측 정글 일곱 칸(팀0 셋 + 팀1 셋 +
# 중립 하나)이 통째로 한 덩어리이고 우측도 같다 — 정글러가 어느 칸부터 도는지는
# `SimulationCore._nearest_uncaptured_neutral` 이 정하는 일이고, 여기서 정하는
# 것은 "어느 쪽 정글에서 시작하는가" 하나다.
#
# 예전에는 이 선택이 `features/match_flow/jungle_start/` 의 **별도 화면**이었다.
# 전장을 못 본 채 "← LEFT / RIGHT →" 두 버튼 중 하나를 고르게 했는데, 좌우
# 정글이 무엇을 끼고 있고 우리 정글러가 어디에 서 있는지가 화면에 없으면 그
# 선택은 동전 던지기와 다르지 않았다. 그 폴더는 삭제됐다.

## 좌 / 우 정글 한 무리. 팀0 · 팀1 의 같은 쪽 정글과 그 사이의 중립 칸까지가
## 한 덩어리다 — 중립 칸은 평범한 정글 칸이고(`SimulationCore` 참고) 정글러의
## 첫 목표가 되는 자리이므로 무리에서 빠질 이유가 없다.
const LEFT_CELLS: Array = [
	Vector2i(-2,  0), Vector2i(-2, -1), Vector2i(-3,  0),
	Vector2i(-2, -3), Vector2i(-2, -2), Vector2i(-3, -2),
	Vector2i(-3, -1),
]
const RIGHT_CELLS: Array = [
	Vector2i( 0,  0), Vector2i( 0, -1), Vector2i( 1,  0),
	Vector2i( 0, -3), Vector2i( 0, -2), Vector2i( 1, -2),
	Vector2i( 1, -1),
]

## 원형 초상화의 지름. 전장 마커(≈85px)보다 크다 — 손가락으로 집는 물건이라
## 마커와 같은 크기면 잡기가 어렵고, 어차피 지금 화면에서 끌 수 있는 것은
## 이 하나뿐이라 크다고 헷갈릴 것도 없다.
const PORTRAIT_D: float = 150.0
const PORTRAIT_RING := Color(1.0, 0.85, 0.30)
const PORTRAIT_BACK := Color(0.96, 0.97, 1.00)

## 안내문 / 확정 버튼이 서는 띠 — 손패 행 **바로 위**다. 둘은 같은 자리를
## 나눠 쓴다(고르기 전에는 안내문, 고른 뒤에는 버튼): 한 번에 하나만 할 말이
## 있는 자리라 둘을 나란히 세우면 화면이 무엇을 묻는지가 흐려진다.
const BAND_H: float = 96.0
const BAND_GAP: float = 12.0
const BTN_W: float = 440.0

const HINT_TEXT: String = "정글러를 끌어다 시작할 정글에 놓는다"
const HINT_FONT: int = 30
const HINT_COLOR := Color(0.86, 0.90, 0.98)

## 정글 무리 강조 — 평소 채움 / 커서가 올라온(또는 고른) 쪽 채움 / 테두리.
const ZONE_FILL      := Color(0.30, 0.85, 0.45, 0.16)
const ZONE_FILL_HOT  := Color(0.30, 0.85, 0.45, 0.34)
const ZONE_LINE      := Color(0.34, 0.95, 0.52, 0.85)
const ZONE_LINE_HOT  := Color(1.00, 0.90, 0.35, 0.98)

var _bs: BattleSim = null

var _root: Control = null
var _portrait: Panel = null
var _hint: Label = null
var _confirm: Button = null

var _jungler: PilotData = null
var _home: Vector2 = Vector2.ZERO
var _dragging: bool = false
## 지금 커서가 올라와 있는 정글 무리. 끄는 동안에만 답이 있는 질문이라
## 드래그가 끝나면 -1 로 돌아간다.
var _hover_dir: int = -1
## 확정 대기 중인 방향. -1 이면 아직 아무것도 안 골랐다.
var _picked_dir: int = -1


func bind(bs: BattleSim) -> void:
	_bs = bs


# ── 상태 질의 (렌더러가 읽는다) ──────────────────────────────────────────────
func is_active() -> bool:
	return _root != null and is_instance_valid(_root)


## 이 화면이 옮기고 있는 아군 정글러. 렌더러가 읽는다 — 선택하는 동안
## **전장에는 이 한 사람만 남고** 나머지 아홉은 치워진다
## (`BattleRenderer._hidden_during_jungle_pick`).
func jungler() -> PilotData:
	return _jungler


## 지금 밝혀야 할 정글 무리. 끄는 중이면 커서 밑의 것, 아니면 고른 것.
func highlight_dir() -> int:
	return _hover_dir if _dragging else _picked_dir


static func cells_for(dir: int) -> Array:
	return RIGHT_CELLS if dir == GameEnums.JungleStartDir.RIGHT else LEFT_CELLS


# ── 열기 / 닫기 ──────────────────────────────────────────────────────────────
## 아군 정글러를 찾아 화면을 세운다. 정글러가 없으면(스폰이 어긋난 경우)
## 아무것도 하지 않고 false 를 돌려준다 — 그때는 부르는 쪽이 곧장 개시한다.
func open() -> bool:
	if _bs == null or _bs.canvas == null:
		return false
	# 재시작 경로가 같은 오버레이를 두 번 열 수 있다 — 앞엣것을 먼저 걷는다.
	close()
	_jungler = _find_player_jungler()
	if _jungler == null:
		return false
	_picked_dir = -1
	_hover_dir = -1
	_dragging = false
	_bs.hud.set_pregame_chrome_visible(false)
	_build()
	return true


## 고른 방향을 정글러에게 새기고 화면을 걷는다. 반환값은 그 방향이다.
func commit() -> int:
	var dir: int = _picked_dir if _picked_dir >= 0 else GameEnums.JungleStartDir.LEFT
	if _jungler != null:
		_jungler.jungle_start_pref = dir
	close()
	return dir


func close() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_portrait = null
	_hint = null
	_confirm = null
	_dragging = false
	_hover_dir = -1
	if _bs != null and _bs.hud != null:
		_bs.hud.set_pregame_chrome_visible(true)
	if _bs != null and _bs.renderer != null:
		_bs.renderer.queue_redraw()


func _find_player_jungler() -> PilotData:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.team == 0 and p.is_guerrilla:
			return p
	return null


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	var vp := ScreenMetrics.viewport_size()
	_root = Control.new()
	_root.name = "JungleStartOverlay"
	_root.position = Vector2.ZERO
	_root.size = vp
	# 화면 전체가 드래그 판이다 — 잡는 것은 초상화 하나뿐이지만, 놓는 자리는
	# 전장 어디든이라 릴리스를 끝까지 받아야 한다. 누른 Control 이 마우스
	# 포커스를 유지하므로 커서가 전장으로 나가도 motion / release 가 계속
	# 이쪽으로 들어온다.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_input)
	_bs.canvas.add_child(_root)

	# 띠는 **초상화 아래**다. 위에 두면 전장을 덮는다 — 우리 팀 HQ 는 격자의
	# 맨 아래 칸이고 그 칸의 초상화 무리는 타일 **밑**에 앉으므로, 전장 픽셀
	# 아래끝(1351)보다 더 내려와 손패 행 윗선까지 밀고 들어온다(실측).
	# 아래로 내리면 초상화와 아군 스트립(1766) 사이에 정확히 들어간다.
	_home = Vector2(vp.x * 0.5, _bs.BS_HAND_CENTER.y + Card.CARD_H * 0.5)
	var band_y: float = _home.y + PORTRAIT_D * 0.5 + BAND_GAP
	_hint = UiHelpers.mk_label(_root, HINT_TEXT, HINT_FONT, HINT_COLOR,
			Vector2(0.0, band_y + (BAND_H - 40.0) * 0.5), Vector2(vp.x, 40.0),
			HORIZONTAL_ALIGNMENT_CENTER)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_confirm = Button.new()
	_confirm.text = "전투 시작"
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.add_theme_font_size_override("font_size", 34)
	_confirm.position = Vector2((vp.x - BTN_W) * 0.5, band_y)
	_confirm.size = Vector2(BTN_W, BAND_H)
	_confirm.visible = false
	_confirm.pressed.connect(_on_confirm_pressed)
	_root.add_child(_confirm)

	_build_portrait()
	_move_portrait(_home)


func _build_portrait() -> void:
	_portrait = Panel.new()
	_portrait.size = Vector2(PORTRAIT_D, PORTRAIT_D)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	# `circle` 컷은 정사각형에 **내접한 원** 그림이고 그 안쪽에도 알파 구멍이
	# 있다 — 전장 마커가 초상 뒤에 흰 원을 까는 것과 같은 이유로 여기도 불투명
	# 바탕을 깐다(안 깔면 전장 타일이 얼굴을 뚫고 비친다).
	sb.bg_color = PORTRAIT_BACK
	sb.border_color = PORTRAIT_RING
	sb.border_width_top = 4
	sb.border_width_bottom = 4
	sb.border_width_left = 4
	sb.border_width_right = 4
	var r: int = int(PORTRAIT_D * 0.5)
	sb.corner_radius_top_left     = r
	sb.corner_radius_top_right    = r
	sb.corner_radius_bottom_left  = r
	sb.corner_radius_bottom_right = r
	_portrait.add_theme_stylebox_override("panel", sb)
	_root.add_child(_portrait)

	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = PilotImages.circle_for(_jungler.pilot_id)
	art.position = Vector2(4.0, 4.0)
	art.size = Vector2(PORTRAIT_D - 8.0, PORTRAIT_D - 8.0)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.add_child(art)


func _move_portrait(centre: Vector2) -> void:
	if _portrait != null:
		_portrait.position = centre - _portrait.size * 0.5


func _portrait_centre() -> Vector2:
	return _portrait.position + _portrait.size * 0.5


# ── 드래그 ───────────────────────────────────────────────────────────────────
func _on_root_input(event: InputEvent) -> void:
	var local: Vector2
	if event is InputEventMouse:
		local = (event as InputEventMouse).position
	elif event is InputEventScreenTouch:
		local = (event as InputEventScreenTouch).position
	elif event is InputEventScreenDrag:
		local = (event as InputEventScreenDrag).position
	else:
		return
	# 손패 드래그와 **같은 변환**이다 — 이 좌표는 곧 뷰포트 좌표이고,
	# `BattleSim.cell_center()` 가 돌려주는 전장 좌표와 같은 공간에 산다
	# (BattleSim / BattleRenderer 가 원점의 Node2D 이고 카메라가 없다).
	var p: Vector2 = _root.get_global_transform_with_canvas() * local

	var pressed: bool = false
	var released: bool = false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			pressed  = mb.pressed
			released = not mb.pressed
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		pressed  = st.pressed
		released = not st.pressed

	if pressed:
		if p.distance_to(_portrait_centre()) <= PORTRAIT_D * 0.5:
			_dragging = true
			_hover_dir = _dir_under(p)
			_bs.renderer.queue_redraw()
		_root.accept_event()
		return
	if released:
		if _dragging:
			_drop_at(p)
		_root.accept_event()
		return
	if _dragging:
		_move_portrait(p)
		var was: int = _hover_dir
		_hover_dir = _dir_under(p)
		if was != _hover_dir:
			_bs.renderer.queue_redraw()


## 드롭. 정글 무리 위면 그 방향이 선택되고 초상화가 그 무리 한가운데에 앉는다.
## 빗나가면 있던 자리로 돌아간다 — 이미 고른 것이 있으면 그 정글로, 아니면
## 원래 손패 자리로.
func _drop_at(p: Vector2) -> void:
	_dragging = false
	var dir: int = _dir_under(p)
	if dir >= 0:
		_picked_dir = dir
	_hover_dir = -1
	_snap_to_state()
	_bs.renderer.queue_redraw()


func _snap_to_state() -> void:
	if _picked_dir >= 0:
		_move_portrait(_zone_centre(_picked_dir))
	else:
		_move_portrait(_home)
	var chose: bool = _picked_dir >= 0
	_hint.visible = not chose
	_confirm.visible = chose


## 이 좌표가 어느 정글 무리 위인가. 무리의 어느 칸 중심에서든 한 칸 반지름
## 안이면 그 무리다 — 칸 하나를 정확히 겨누게 하는 화면이 아니다.
func _dir_under(p: Vector2) -> int:
	var hex_size: float = (_bs.hex_grid as HexGrid).hex_size
	for dir in [GameEnums.JungleStartDir.LEFT, GameEnums.JungleStartDir.RIGHT]:
		for c_raw in cells_for(dir):
			if _bs.cell_center(c_raw as Vector2i).distance_to(p) <= hex_size:
				return dir
	return -1


func _zone_centre(dir: int) -> Vector2:
	var sum := Vector2.ZERO
	var cells: Array = cells_for(dir)
	for c_raw in cells:
		sum += _bs.cell_center(c_raw as Vector2i)
	return sum / float(maxi(1, cells.size()))


func _on_confirm_pressed() -> void:
	if _picked_dir < 0:
		return
	start_pressed.emit()
