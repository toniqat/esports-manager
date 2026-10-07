class_name JungleStartOverlay
extends Node

## 플레이어가 "전투 시작"을 눌렀다. `GambitPhaseManager` 가 받아 고른 칸을
## 정글러에게 새기고(`commit()`) 전장을 개시한다 — 이 모듈은 무엇을 골랐는지만
## 알지, 그 다음에 무엇이 일어나는지는 모른다.
signal start_pressed

# 정글 시작 칸 — **전장 위의 정글러를 직접 끌어다 놓는다.**
#
# 개시 직전(`game_phase == GAMBIT`) 한 번 열리는 화면이다. 전장은 이미 다 서
# 있고(파일럿 · 포탑 · 정글 소유 · 캠프), HUD 에서 **지금 쓸 수 없는 것들만
# 숨는다** — 손패 자리의 덱 / 버린 더미 뭉치, 전략 포인트 도넛 둘, 상단의
# 오브젝트 등장 시계 둘.
#
# **옮기는 것은 전장에 서 있는 그 정글러 마커다.** HQ 에 서 있는 아군 정글러
# 초상(이 화면 동안은 말풍선 꼬리 없이 그려진다)을 집어 **우리 정글 / 아직 아무도
# 안 잡은 중립 칸** 중 하나에 놓는다. 상대 소유 정글 칸은 딤드된 채 받지 않는다.
# 놓을 칸 위를 지나는 동안 HQ 에서 그 칸까지 정글러가 걸어갈 길과 **도착한 뒤
# `AFTER_TURNS`(6)턴의 걸음**이 함께 그려지고(도착 2턴이면 8턴까지) 칸마다 몇
# 턴째인지가 찍힌다.
#
# 드롭은 선택일 뿐 개시가 아니다 — 마커가 그 칸에 앉고 손패 자리에 "전투 시작"이
# 뜬다. 확정하면 정글러는 **HQ 에서 출발해** 그 칸을 첫 목표로 걷는다
# (`PilotData.jungle_start_cell` → `SimulationCore._jungle_goal_for`). 화면이 그린
# 경로는 그 걸음과 같은 목표 선택 · 같은 한 걸음(`SimulationCore.jungle_step` —
# 같은 거리면 상대 정글을 피한다)을 앞으로 굴린 것이다.
#
# 예전에는 손패 자리에 **따로 세운 원형 초상화**를 좌 / 우 정글 **무리**로
# 끌어다 놓았다 — 방향 하나만 골랐고, 전장의 정글러와 끌고 있는 그림이 둘로
# 갈려 있었다. 그보다 더 예전에는 `features/match_flow/jungle_start/` 의 별도
# 화면이 "← LEFT / RIGHT →" 두 버튼만 세웠다.

## 좌 / 우 정글 한 무리. 드롭 대상은 이제 칸 하나지만, 고른 칸이 어느 쪽인지가
## `jungle_start_pref`(첫 목표를 지난 뒤 중립 칸을 도는 순서)로 남는다.
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

## 시작 칸에 **도착한 뒤** 몇 턴의 걸음까지 그리는가. 시작 칸까지의 턴 수는
## 칸마다 다르므로 그린 경로의 총 턴은 "도착 턴 + 6" 이다.
const AFTER_TURNS: int = 6
## 예측을 굴리는 상한 — 도착이 이보다 늦으면(지금 지도에선 없다) 거기서 끊는다.
const MAX_PREDICT_TURNS: int = 30

## 마커를 집는 반경 — 그려진 반지름의 배수. 손가락으로 집는 물건이라 얼굴
## 테두리보다 조금 넓게 받는다.
const GRAB_RADIUS_MULT: float = 1.35

## 안내문 / 확정 버튼이 서는 띠 — 비워진 손패 자리. 둘은 같은 자리를 나눠
## 쓴다(고르기 전에는 안내문, 고른 뒤에는 버튼).
const BAND_H: float = 96.0
const BTN_W: float = 440.0

const HINT_FONT: int = 30
const HINT_COLOR := Color(0.86, 0.90, 0.98)

## 놓을 수 있는 칸 — 평소 채움 / 마커가 올라온(또는 고른) 칸 채움 / 테두리.
const ZONE_FILL      := Color(0.30, 0.85, 0.45, 0.16)
const ZONE_FILL_HOT  := Color(0.30, 0.85, 0.45, 0.34)
const ZONE_LINE      := Color(0.34, 0.95, 0.52, 0.85)
const ZONE_LINE_HOT  := Color(1.00, 0.90, 0.35, 0.98)
## 경로 — 시작 칸까지의 선 / 도착 뒤의 선 / 턴 번호 원 / 번호.
const PATH_LINE      := Color(1.00, 0.90, 0.35, 0.95)
const PATH_LINE_AFTER := Color(0.55, 0.88, 1.00, 0.90)
const PATH_DOT       := Color(0.10, 0.10, 0.14, 0.92)
const PATH_TEXT      := Color(1.00, 0.92, 0.50)

const NO_CELL := Vector2i(-1, -1)

var _bs: BattleSim = null

var _root: Control = null
var _hint: Label = null
var _confirm: Button = null

var _jungler: PilotData = null
var _dragging: bool = false
## 끄는 동안 마커 중심의 화면 좌표, 그리고 집은 지점에서 마커 중심까지의 차이
## (집는 순간 얼굴이 손가락 밑으로 튀지 않게).
var _drag_pos: Vector2 = Vector2.ZERO
var _grab_offset: Vector2 = Vector2.ZERO
## 지금 마커가 올라와 있는 놓을 수 있는 칸. 끄는 동안에만 답이 있다.
var _hover_cell: Vector2i = NO_CELL
## 확정 대기 중인 칸. NO_CELL 이면 아직 아무것도 안 골랐다.
var _picked_cell: Vector2i = NO_CELL
## `path_cells()` 캐시 — 마지막으로 예측한 칸과 그 결과.
var _path_cache_cell: Vector2i = NO_CELL
var _path_cache: Array = []


func bind(bs: BattleSim) -> void:
	_bs = bs


# ── 상태 질의 (렌더러가 읽는다) ──────────────────────────────────────────────
func is_active() -> bool:
	return _root != null and is_instance_valid(_root)


## 이 화면이 옮기고 있는 아군 정글러. 선택하는 동안 **전장에는 이 한 사람만
## 남고**(`BattleRenderer._hidden_during_jungle_pick`) 말풍선 꼬리 없이 그려진다.
func jungler() -> PilotData:
	return _jungler


## 렌더러가 정글러 마커를 그릴 자리. 끄는 중이면 손가락 밑, 고른 칸이 있으면 그
## 칸 한가운데, 아니면 평소 자리(`default_pos`, HQ 의 슬롯) 그대로.
func marker_pos(default_pos: Vector2) -> Vector2:
	if _dragging:
		return _drag_pos
	if _picked_cell != NO_CELL:
		return _bs.cell_center(_picked_cell)
	return default_pos


## 지금 밝혀야 할 칸. 끄는 중이면 마커 밑의 것, 아니면 고른 것.
func highlight_cell() -> Vector2i:
	return _hover_cell if _dragging else _picked_cell


## 고른 칸. 아무것도 안 골랐으면 NO_CELL.
func picked_cell() -> Vector2i:
	return _picked_cell


## 놓을 수 있는 칸 — 정글 / 중립 칸 중 **우리 팀 소유이거나 아직 아무도 안 잡은**
## 칸. 상대 소유 정글은 빠진다. 딤(밝게 남는 칸)과 드롭 판정이 이 목록 하나를
## 읽는다 — 놓을 수 있는 칸과 밝은 칸이 갈릴 수 없다.
func active_cells() -> Dictionary:
	var out: Dictionary = {}
	if _jungler == null:
		return out
	for raw in _bs.neutral_zone_cells.keys():
		var owner_id: int = int(_bs.neutral_zone_cells[raw])
		if owner_id == _jungler.team or owner_id == -1:
			out[raw as Vector2i] = true
	return out


## 정글러가 밟을 칸들 — **HQ 에서 밝힌 칸까지 + 도착한 뒤 `AFTER_TURNS` 턴.**
## 도착에 2턴이 걸리면 8턴까지다. 출발 칸은 넣지 않는다. 원소는
## `{cell, turn, after}` — `after` 는 도착한 뒤의 걸음이다(렌더러가 색을 가른다).
##
## **예측은 시뮬레이터 자신이 한다**(`SimulationCore.predict_jungle_path`). 시작
## 칸을 정글러에게 잠깐 새겨 두고 진짜 `_jungle_goal_for` 를 앞으로 굴리므로,
## 도착 뒤의 걸음(중립 점령 → 캠프 순회)까지 실제 규칙 그대로 나온다. **단순
## 예상 루트다** — 상대 정글러와의 충돌(중립 선점 · 교전)은 계산하지 않는다.
## 제자리에 머문 턴도 원소 하나다(같은 칸에 번호가 여럿). 같은 칸을 여러 번 그리는
## 동안 다시 굴리지 않게 칸 하나 단위로 캐시한다(정글 소유 · 캠프는 이 화면 동안 바뀌지 않는다).
func path_cells() -> Array:
	var target: Vector2i = highlight_cell()
	if _jungler == null or target == NO_CELL:
		return []
	if target == _path_cache_cell:
		return _path_cache
	var keep: Vector2i = _jungler.jungle_start_cell
	_jungler.jungle_start_cell = target
	var steps: Array = _bs.sim_core.predict_jungle_path(_jungler, MAX_PREDICT_TURNS)
	_jungler.jungle_start_cell = keep
	var arrive: int = -1
	var out: Array = []
	for raw in steps:
		var st: Dictionary = raw
		var t: int = int(st["turn"])
		if arrive >= 0 and t > arrive + AFTER_TURNS:
			break
		out.append({"cell": st["cell"], "turn": t, "after": arrive >= 0 and t > arrive})
		if arrive < 0 and st["cell"] == target:
			arrive = t
	_path_cache_cell = target
	_path_cache = out
	return out


static func side_of(cell: Vector2i) -> int:
	return GameEnums.JungleStartDir.RIGHT if RIGHT_CELLS.has(cell) \
			else GameEnums.JungleStartDir.LEFT


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
	_picked_cell = NO_CELL
	_hover_cell = NO_CELL
	_path_cache_cell = NO_CELL
	_dragging = false
	_bs.hud.set_pregame_chrome_visible(false)
	_build()
	return true


## 고른 칸을 정글러에게 새기고 화면을 걷는다. 반환값은 그 칸이 속한 쪽 정글의
## 방향이다(`match_ctx.jungle_start_dir` 이 읽는다).
func commit() -> int:
	var dir: int = side_of(_picked_cell)
	if _jungler != null:
		_jungler.jungle_start_pref = dir
		_jungler.jungle_start_cell = _picked_cell
	close()
	return dir


func close() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_hint = null
	_confirm = null
	_dragging = false
	_hover_cell = NO_CELL
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
	# 화면 전체가 드래그 판이다 — 잡는 것은 정글러 마커 하나뿐이지만 놓는 자리는
	# 전장 어디든이라 릴리스를 끝까지 받아야 한다. 누른 Control 이 마우스
	# 포커스를 유지하므로 커서가 어디로 나가도 motion / release 가 이쪽으로 온다.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_input)
	_bs.canvas.add_child(_root)

	# 띠는 비워진 손패 자리 한가운데다 — 전장 아래끝(우리 HQ 의 초상화가 타일
	# 밑으로 내려오는 자리)과 아군 스트립 사이.
	var band_y: float = _bs.BS_HAND_CENTER.y + Card.CARD_H * 0.5 - BAND_H * 0.5
	_hint = UiHelpers.mk_label(_root, Loc.t(L.BATTLE_JUNGLE_START_HINT), HINT_FONT, HINT_COLOR,
			Vector2(0.0, band_y + (BAND_H - 40.0) * 0.5), Vector2(vp.x, 40.0),
			HORIZONTAL_ALIGNMENT_CENTER)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_confirm = Button.new()
	_confirm.text = Loc.t(L.BATTLE_JUNGLE_START_START)
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.add_theme_font_size_override("font_size", 34)
	_confirm.position = Vector2((vp.x - BTN_W) * 0.5, band_y)
	_confirm.size = Vector2(BTN_W, BAND_H)
	_confirm.visible = false
	_confirm.pressed.connect(_on_confirm_pressed)
	_root.add_child(_confirm)


## 지금 화면에 그려진 정글러 마커의 중심 — 렌더러가 쓰는 표에 같은 덮어쓰기를
## 얹은 값이라 집는 자리와 보이는 자리가 갈리지 않는다.
func _shown_marker_pos() -> Vector2:
	var layout: Dictionary = _bs.renderer.pilot_marker_positions()
	var base: Vector2 = layout.get(_jungler, _bs.cell_center(_jungler.grid_pos))
	return marker_pos(base)


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
		var centre: Vector2 = _shown_marker_pos()
		var grab_r: float = _bs.renderer.pilot_marker_radius(_jungler) * GRAB_RADIUS_MULT
		if p.distance_to(centre) <= grab_r:
			_dragging = true
			_grab_offset = centre - p
			_drag_pos = centre
			_hover_cell = _cell_under(_drag_pos)
			Haptics.play(Haptics.Kind.SELECT)
			_bs.renderer.queue_redraw()
		_root.accept_event()
		return
	if released:
		if _dragging:
			_drop()
		_root.accept_event()
		return
	if _dragging:
		_drag_pos = p + _grab_offset
		var was: Vector2i = _hover_cell
		_hover_cell = _cell_under(_drag_pos)
		if was != _hover_cell and _hover_cell != NO_CELL:
			# 칸 단위로 스냅하는 판이라 **놓을 수 있는 칸에 들어설 때마다** 운다 —
			# 경로가 칸마다 새로 그려지므로 한 톡이 곧 "다른 칸으로 넘어갔다"이다.
			# 벗어나는 쪽은 조용하다.
			Haptics.play(Haptics.Kind.LIGHT)
		_bs.renderer.queue_redraw()


## 드롭. 놓을 수 있는 칸 위면 그 칸이 선택되고 마커가 그 칸에 앉는다. 빗나가면
## 있던 자리로 돌아간다 — 이미 고른 칸이 있으면 그 칸으로, 아니면 HQ 로.
func _drop() -> void:
	_dragging = false
	if _hover_cell != NO_CELL:
		_picked_cell = _hover_cell
		# 칸이 정해졌다 — 아직 개시는 아니지만(확정 버튼이 따로 있다) 선택은
		# 여기서 끝난다.
		Haptics.play(Haptics.Kind.MEDIUM)
	_hover_cell = NO_CELL
	var chose: bool = _picked_cell != NO_CELL
	_hint.visible = not chose
	_confirm.visible = chose
	_bs.renderer.queue_redraw()


## 이 좌표 밑의 **놓을 수 있는** 칸. 칸 중심에서 한 칸 반지름 안이면 그 칸이고,
## 둘 이상 걸리면 가까운 쪽.
func _cell_under(p: Vector2) -> Vector2i:
	var hex_size: float = (_bs.hex_grid as HexGrid).hex_size
	var best: Vector2i = NO_CELL
	var best_d: float = hex_size
	for raw in active_cells().keys():
		var c := raw as Vector2i
		var d: float = _bs.cell_center(c).distance_to(p)
		if d <= best_d:
			best_d = d
			best = c
	return best


func _on_confirm_pressed() -> void:
	if _picked_cell == NO_CELL:
		return
	start_pressed.emit()
