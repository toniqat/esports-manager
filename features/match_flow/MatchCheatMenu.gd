class_name MatchCheatMenu
extends CanvasLayer

# 에디터 실행 전용 치트 메뉴 — 좌측 상단의 `CHEAT` 버튼 하나, 누르면 그 아래로
# 지금 단계에서 쓸 수 있는 치트 버튼이 펼쳐진다. 무엇을 펼칠지는 이 메뉴가
# 모른다 — `MatchFlow` 가 단계가 바뀔 때마다 `set_actions()` 로 목록을 갈아
# 끼운다(빈 목록이면 메뉴째 숨는다). 내보낸 빌드에서는 `MatchFlow` 가 아예
# 만들지 않는다(`OS.has_feature("editor")`).

## 상세 팝업(20)보다 위, 장면 전환 덮개(SceneFade 100)보다 아래.
const LAYER: int = 50
const MARGIN: float = 16.0
const TOGGLE_SIZE := Vector2(150, 64)
const ITEM_SIZE := Vector2(300, 72)
const GAP: float = 10.0

var _toggle: Button
var _list: VBoxContainer
var _actions: Array = []   # Array[{label: String, call: Callable}]


func _ready() -> void:
	layer = LAYER
	var origin := Vector2(ScreenMetrics.left_x() + MARGIN, ScreenMetrics.top_y() + MARGIN)

	_toggle = Button.new()
	_toggle.text = "CHEAT"
	_toggle.position = origin
	_toggle.size = TOGGLE_SIZE
	OutgameTheme.style_dark_button(_toggle, 24)
	_toggle.modulate = Color(1, 1, 1, 0.85)
	_toggle.pressed.connect(func() -> void: _list.visible = not _list.visible)
	add_child(_toggle)

	_list = VBoxContainer.new()
	_list.position = origin + Vector2(0, TOGGLE_SIZE.y + GAP)
	_list.add_theme_constant_override("separation", int(GAP))
	_list.visible = false
	add_child(_list)
	_rebuild()


## 지금 단계의 치트 목록으로 갈아 끼운다. 펼쳐 둔 목록은 접힌다.
func set_actions(actions: Array) -> void:
	_actions = actions
	if is_node_ready():
		_rebuild()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_list.visible = false
	visible = not _actions.is_empty()
	for a in _actions:
		var b := Button.new()
		b.text = String(a["label"])
		b.custom_minimum_size = ITEM_SIZE
		OutgameTheme.style_ghost_button(b, 26)
		var cb: Callable = a["call"]
		b.pressed.connect(func() -> void:
			# 한 번 누르면 끝 — 장면이 넘어가는 동안 두 번 눌리지 않게 잠근다.
			set_actions([])
			cb.call())
		_list.add_child(b)
