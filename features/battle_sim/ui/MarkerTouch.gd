class_name MarkerTouch
extends Node

# 전장 초상 누르기 — **누르면 커지고 맨 위로, 꾹 누르면 상세 패널.**
#
#   누름   → `BattleRenderer.press_marker` : 그 초상이 `PRESS_SCALE` 로 커지고
#            맨 위로 올라온다. 이웃 칸 마커에 가려져 있던 얼굴을 꺼내 보는 조작이다.
#   뗌     → `release_marker` : 크기만 돌아오고 **맨 위 순서는 남는다**(다른 초상을
#            누를 때까지).
#   꾹 누름 → `LONG_PRESS_SEC` 동안 `MOVE_CANCEL_PX` 안에 머물면 `PilotDetailPanel`
#            을 연다(하단 스트립을 누른 것과 같은 패널, 같은 게이트 `can_open`).
#
# `_unhandled_input` 이라 손패 · 스트립 · 버튼 같은 GUI 가 먼저 먹은 입력은 오지
# 않는다 — 여기 오는 것은 전장 빈 곳을 누른 것뿐이다. 카드를 들고 있거나(대상 지정)
# 다른 모달이 떠 있는 동안은 손대지 않는다(`_accepting`).
#
# 터치는 마우스로도 에뮬레이트되어 한 번의 누름이 두 이벤트로 온다 — 누름 / 뗌을
# 상태 전이로만 처리하므로 두 번째는 아무 일도 하지 않는다.

const LONG_PRESS_SEC: float = 0.45
## 이만큼 움직이면 꾹 누르기를 취소한다(스크롤 · 헛누름).
const MOVE_CANCEL_PX: float = 28.0

var _bs: BattleSim = null
var _pressed: PilotData = null
var _press_pos: Vector2 = Vector2.ZERO
var _held_t: float = 0.0


func bind(bs: BattleSim) -> void:
	_bs = bs


func _unhandled_input(event: InputEvent) -> void:
	var down: bool = false
	var up: bool = false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		down = mb.pressed
		up = not mb.pressed
		pos = mb.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		down = st.pressed
		up = not st.pressed
		pos = st.position
	elif event is InputEventMouseMotion:
		_check_moved((event as InputEventMouseMotion).position)
		return
	elif event is InputEventScreenDrag:
		_check_moved((event as InputEventScreenDrag).position)
		return
	else:
		return
	if up:
		_release()
		return
	if not down or _pressed != null or not _accepting():
		return
	var p: PilotData = _bs.renderer.marker_at(pos)
	if p == null:
		return
	_pressed = p
	_press_pos = pos
	_held_t = 0.0
	_bs.renderer.press_marker(p)
	Haptics.play(Haptics.Kind.SELECT)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _pressed == null:
		return
	if not _accepting() or not _pressed.alive:
		_release()
		return
	_held_t += delta
	if _held_t < LONG_PRESS_SEC:
		return
	var p := _pressed
	_release()
	if _bs.pilot_detail != null and _bs.pilot_detail.can_open():
		Haptics.play(Haptics.Kind.MEDIUM)
		_bs.pilot_detail.open(p)


func _check_moved(pos: Vector2) -> void:
	if _pressed != null and pos.distance_to(_press_pos) > MOVE_CANCEL_PX:
		_release()


func _release() -> void:
	if _pressed == null:
		return
	_pressed = null
	_bs.renderer.release_marker()


## 전장 초상을 누를 수 있는 상태인가. 카드가 들려 대상 지정 중이거나, 다른
## 오버레이(상세 패널 · 카드 선택 · 더미 열람 · 정글 시작 · 교전 무대)가 떠 있으면
## 전장은 그쪽 조작의 배경이다.
func _accepting() -> bool:
	if _bs == null or _bs.renderer == null or not _bs.field_ready or _bs.game_over:
		return false
	if _bs.targeting_overlay != null and _bs.targeting_overlay.is_visualizing():
		return false
	if _bs.pilot_detail != null and _bs.pilot_detail.is_active():
		return false
	if _bs.card_select_overlay != null and _bs.card_select_overlay.is_active():
		return false
	if _bs.card_pile_viewer != null and _bs.card_pile_viewer.is_active():
		return false
	if _bs.jungle_pick != null and _bs.jungle_pick.is_active():
		return false
	if _bs.engage_phase != null and _bs.engage_phase.is_active():
		return false
	return true
