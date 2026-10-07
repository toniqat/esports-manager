class_name MatchCheatMenu
extends CanvasLayer

# 에디터 실행 전용 치트 메뉴 — 좌측 상단의 `CHEAT` 버튼 하나, 누르면 그 아래로
# 지금 단계에서 쓸 수 있는 치트 버튼이 펼쳐진다. 무엇을 펼칠지는 이 메뉴가
# 모른다 — `MatchFlow` 가 단계가 바뀔 때마다 `set_actions()` 로 목록을 갈아
# 끼운다(빈 목록이면 메뉴째 숨는다). 내보낸 빌드에서는 `MatchFlow` 가 아예
# 만들지 않는다(`OS.has_feature("editor")`).
#
# **모양의 정본은 `MatchCheatMenu.tscn`** (레이어 50 = 상세 팝업(20)보다 위, 장면 전환
# 덮개(SceneFade 100)보다 아래 · 버튼 크기 · 간격 · `DarkButton` / `GhostButton` 변형).
# 치트 버튼 한 줄은 `MatchCheatItem.tscn`. 코드가 하는 일은 안전 영역 인셋만큼
# `%Menu` 를 미는 것과 목록 채우기뿐이다.

const SCENE_PATH: String = "res://features/match_flow/MatchCheatMenu.tscn"
const ITEM_SCENE_PATH: String = "res://features/match_flow/MatchCheatItem.tscn"

var _actions: Array = []   # Array[{label: String, call: Callable}]


## 씬을 인스턴스한다. `MatchCheatMenu.new()` 는 빈 CanvasLayer 라 쓰지 않는다.
## 목록이 비어 있는 동안은 숨는다(`set_actions`).
static func create() -> MatchCheatMenu:
	var m := (load(SCENE_PATH) as PackedScene).instantiate() as MatchCheatMenu
	m.visible = false
	return m


func _ready() -> void:
	# 씬의 여백(16)은 안전 영역 기준 — 노치 · 좌우 인셋만큼 메뉴째 민다.
	var menu: Control = %Menu
	menu.offset_left += ScreenMetrics.left_x()
	menu.offset_top += ScreenMetrics.top_y()
	%Toggle.pressed.connect(func() -> void: %List.visible = not %List.visible)
	_rebuild()
	if UiPreview.is_standalone(self):
		_fill_preview()


## 지금 단계의 치트 목록으로 갈아 끼운다. 펼쳐 둔 목록은 접힌다.
func set_actions(actions: Array) -> void:
	_actions = actions
	if is_node_ready():
		_rebuild()


func _rebuild() -> void:
	var list: Control = %List
	# queue_free 만 — 눌린 버튼 자신의 `pressed` 안에서도 불리므로 바로 떼지 않는다.
	for c in list.get_children():
		c.queue_free()
	list.visible = false
	visible = not _actions.is_empty()
	for a in _actions:
		var b := (load(ITEM_SCENE_PATH) as PackedScene).instantiate() as Button
		b.text = String(a["label"])
		var cb: Callable = a["call"]
		b.pressed.connect(func() -> void:
			# 한 번 누르면 끝 — 장면이 넘어가는 동안 두 번 눌리지 않게 잠근다.
			set_actions([])
			cb.call())
		list.add_child(b)


## F6 단독 실행 미리보기 — PREP · BAN_PICK 단계의 치트 두 줄을 넣고 목록을 펼쳐 둔다.
## 누르면 출력만 한다(장면 전환 없음).
func _fill_preview() -> void:
	UiPreview.stage(self)
	set_actions([
		{"label": "즉시 승리 (MVP 아군 탑)",
			"call": func() -> void: print("[UiPreview] cheat 즉시 승리")},
		{"label": "즉시 패배 (MVP 상대 탑)",
			"call": func() -> void: print("[UiPreview] cheat 즉시 패배")},
	])
	(%Toggle as Button).pressed.emit()
