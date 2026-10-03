class_name DragScroll
extends Node

# ── 손가락(마우스) 드래그로 `ScrollContainer` 를 굴린다 ─────────────────────
#
# 엔진의 드래그 스크롤은 `DisplayServer.is_touchscreen_available()` 일 때만
# 켜지고, 그 판정이 스크롤 영역 위의 탭 대상과 엇갈리면 아예 시작조차 못 한다
# (`docs/mobile_safe_area.md` §5). 그래서 **엔진 경로를 끄고 이 노드가 대신
# 굴린다** — 마우스와 (마우스로 에뮬레이트된) 터치가 같은 코드를 지나므로
# 데스크톱에서 마우스로 끌어 본 결과가 곧 폰의 결과다.
#
# 붙이는 법: `DragScroll.attach(scroll)` 한 줄. 이 노드는 스크롤의 자식으로
# 산다(Control 이 아니라 ScrollContainer 의 내용 계산에 끼지 않는다).
#
# ── 한 제스처의 일생 ─────────────────────────────────────────────────────────
#   PENDING  스크롤 영역 안에서 눌렸다. `THRESHOLD_PX` 안의 흔들림은 삼킨다 —
#            탭이 탭으로 남아야 하고, 내장 드래그(`set_drag_forwarding`)가
#            작은 흔들림에 먼저 시작돼 버리면 안 된다.
#   SCROLL   문턱을 넘었고 스크롤 축 방향이다. 그 순간 **눌려 있던 버튼의
#            눌림을 취소**하고(`_cancel_pressed_buttons`) 이후의 이동은 전부
#            스크롤이 먹는다. 손을 떼면 그 속도로 관성이 이어진다.
#   CROSS    문턱을 넘었는데 **스크롤 축을 가로지르는** 방향이다
#            (`cross_axis_releases` 가 켜진 경우만). `cross_drag_started` 를
#            쏘고 이후의 이동은 손대지 않는다 — 화면이 그 신호로 자기 드래그
#            (훈련 타일 집기)를 연다. 꺼져 있으면 어느 방향이든 SCROLL 이다.
#
# **눌림이 "스크롤 안에서 일어났는가"는 GUI 가 판정한다** — 스크롤 노드의
# `gui_input` 시그널로 받는다. `_input` 에서 사각형만 재면 그 위를 덮은 팝업
# (상세 패널 · 정보 팝오버)의 탭까지 스크롤 제스처로 잡힌다. 대신 내용물이
# 눌림을 부모로 넘겨야 하므로 스크롤 아래의 `MOUSE_FILTER_STOP` 은 전부
# `PASS` 로 내린다(`_sweep_filters`, 노드가 들어올 때마다 다시 돈다). PASS 는
# 자기도 이벤트를 받으므로 탭은 그대로다.

## 스크롤 축과 수직인 방향으로 문턱을 넘었다. `press_pos` 는 눌린 자리(뷰포트 좌표).
signal cross_drag_started(press_pos: Vector2)

## 탭 허용 오차. 이 안에서 손가락이 흔들리는 것은 탭이다.
const THRESHOLD_PX: float = 14.0
## 관성 — 초당 감쇠율(지수)과 멈추는 속도.
const FLING_DECAY: float = 5.0
const FLING_STOP: float = 40.0
## 손을 떼기 직전 이 시간보다 오래 멈춰 있었으면 관성을 주지 않는다.
const FLING_IDLE_MS: int = 80

enum State { IDLE, PENDING, SCROLL, CROSS }

var horizontal: bool = false
var cross_axis_releases: bool = false

## 마지막(또는 지금) 제스처가 탭이 아니게 됐는가 — 스크롤했거나 가로질렀다.
## 버튼이 아닌 탭 대상(`gui_input` 으로 떼기를 받는 패널)은 이 값을 보고
## 떼기를 무시한다. 다음 누름에서 다시 false 가 된다.
var moved: bool = false

var _scroll: ScrollContainer
var _state: int = State.IDLE
var _press_pos: Vector2 = Vector2.ZERO
var _anchor_along: float = 0.0
var _anchor_value: float = 0.0
var _vel: float = 0.0
var _last_along: float = 0.0
var _last_ms: int = 0
var _fling: float = 0.0
var _sweep_queued: bool = false


static func attach(scroll: ScrollContainer, is_horizontal: bool = false,
		releases_cross: bool = false) -> DragScroll:
	var d := DragScroll.new()
	d.name = "DragScroll"
	d.horizontal = is_horizontal
	d.cross_axis_releases = releases_cross
	scroll.add_child(d)
	return d


func _ready() -> void:
	_scroll = get_parent() as ScrollContainer
	if _scroll == null:
		push_error("DragScroll: parent must be a ScrollContainer")
		return
	_scroll.gui_input.connect(_on_scroll_gui_input)
	get_tree().node_added.connect(_on_node_added)
	set_process(false)
	_queue_sweep()


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func is_scrolling() -> bool:
	return _state == State.SCROLL


# ── 입력 ─────────────────────────────────────────────────────────────────────
## 스크롤 안에서 눌렸다. **그 누름을 여기서 받아 두면** 엔진의 터치 드래그가
## 시작되지 않는다 — 둘이 함께 돌면 한 손가락에 스크롤이 두 배로 간다.
func _on_scroll_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	_state = State.PENDING
	_press_pos = mb.global_position
	moved = false
	_fling = 0.0
	set_process(false)
	_scroll.accept_event()


func _input(event: InputEvent) -> void:
	if _state == State.IDLE:
		return
	if not _scroll.is_visible_in_tree():
		_state = State.IDLE
		return

	var mm := event as InputEventMouseMotion
	if mm != null:
		match _state:
			State.PENDING:
				var d: Vector2 = mm.position - _press_pos
				if d.length() < THRESHOLD_PX:
					get_viewport().set_input_as_handled()
					return
				var along: float = d.x if horizontal else d.y
				var cross: float = d.y if horizontal else d.x
				moved = true
				if cross_axis_releases and absf(cross) > absf(along):
					_state = State.CROSS
					cross_drag_started.emit(_press_pos)
					return
				_state = State.SCROLL
				_cancel_pressed_buttons()
				_anchor_along = _along(mm.position)
				_anchor_value = _bar().value
				_vel = 0.0
				_last_along = _anchor_along
				_last_ms = Time.get_ticks_msec()
				get_viewport().set_input_as_handled()
			State.SCROLL:
				var a: float = _along(mm.position)
				_bar().value = _anchor_value - (a - _anchor_along)
				var now: int = Time.get_ticks_msec()
				var dt: float = maxf(0.001, float(now - _last_ms) / 1000.0)
				# 손가락 속도를 부드럽게 따라간다 — 한 프레임의 튐이 관성을
				# 통째로 정하지 않게.
				_vel = lerpf(_vel, -(a - _last_along) / dt, 0.4)
				_last_along = a
				_last_ms = now
				get_viewport().set_input_as_handled()
		return

	var rb := event as InputEventMouseButton
	if rb != null and rb.button_index == MOUSE_BUTTON_LEFT and not rb.pressed:
		if _state == State.SCROLL and Time.get_ticks_msec() - _last_ms < FLING_IDLE_MS:
			_fling = _vel
			set_process(absf(_fling) > FLING_STOP)
		_state = State.IDLE
		# 떼기는 삼키지 않는다 — GUI 가 눌림 상태를 정리해야 다음 누름이
		# 엉뚱한 노드로 가지 않는다(버튼의 눌림은 이미 취소돼 있다).


func _process(delta: float) -> void:
	var bar: ScrollBar = _bar()
	var before: float = bar.value
	bar.value = before + _fling * delta
	_fling *= exp(-FLING_DECAY * delta)
	# 끝에 닿았으면(값이 더 안 움직이면) 거기서 멈춘다.
	if absf(_fling) < FLING_STOP or is_equal_approx(bar.value, before):
		_fling = 0.0
		set_process(false)


func _along(p: Vector2) -> float:
	return p.x if horizontal else p.y


func _bar() -> ScrollBar:
	return _scroll.get_h_scroll_bar() if horizontal else _scroll.get_v_scroll_bar()


## 스크롤이 시작된 순간 눌려 있던 버튼의 눌림을 무른다. `disabled` 를 한 번
## 켰다 끄면 엔진이 눌림 상태(press_attempt)를 비운다 — 그러면 손을 뗐을 때
## `pressed` 가 오지 않아 스크롤하려던 손가락이 카드를 고르지 않는다.
func _cancel_pressed_buttons() -> void:
	var stack: Array = [_scroll]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			var b := c as BaseButton
			if b != null and not b.toggle_mode and not b.disabled and b.is_pressed():
				b.disabled = true
				b.disabled = false


# ── 마우스 필터 ──────────────────────────────────────────────────────────────
func _on_node_added(n: Node) -> void:
	if _scroll != null and n is Control and _scroll.is_ancestor_of(n):
		_queue_sweep()


func _queue_sweep() -> void:
	if _sweep_queued:
		return
	_sweep_queued = true
	_sweep_filters.call_deferred()


## 스크롤 아래의 STOP 을 PASS 로 내린다 — 내용물이 눌림을 부모로 넘겨야 스크롤이
## 그 눌림을 본다. 스크롤바는 내부 자식이라 `get_children()` 에 안 잡혀 그대로
## STOP 으로 남는다(스크롤바를 직접 끄는 것은 엔진이 맡는다).
func _sweep_filters() -> void:
	_sweep_queued = false
	if _scroll == null:
		return
	var stack: Array = _scroll.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var c := n as Control
		if c != null and c.mouse_filter == Control.MOUSE_FILTER_STOP:
			c.mouse_filter = Control.MOUSE_FILTER_PASS
		stack.append_array(n.get_children())
