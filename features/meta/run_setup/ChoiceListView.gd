class_name ChoiceListView
extends Control

# 런 준비의 "카드 한 장 고르기" 단계 공용 틀 — 시나리오 · 팀 단계가 이걸 잇는다.
#
#   단계 머리글 아래(`RunSetupScreen.content_top()`)부터: 안내 한 줄 → 카드 목록
#   (세로 스크롤) → 하단 바 `뒤로`(1) / `다음`(2)
#
# **모양의 정본은 `ChoiceListView.tscn`** (안내 줄 · 스크롤 목록 · 카드 간격 · 하단 바).
# 잇는 단계는 그 씬을 상속한 씬(`ScenarioStepView.tscn` · `TeamStepView.tscn` — 루트
# 스크립트만 바꾼다)이고, 카드 한 장은 단계마다의 아이템 씬(`ScenarioCard.tscn` ·
# `TeamCard.tscn`)이다. 생성은 각 단계의 `create()`.
#
# 카드는 통째로 하나의 `Button` 이다 — 누르면 고른 것이 되고(앰버 테두리),
# `다음` 은 하나를 골랐을 때만 풀린다. 카드는 `ScrollContainer` 안에 있으므로
# 씬에서 `MOUSE_FILTER_PASS` 여야 `DragScroll` 이 끌기를 판정한다(`docs/mobile_safe_area.md` §5).
# 고른 / 안 고른 판은 테마 변형 `SelectableCardButton` / `SelectableCardButtonOn` 이고,
# 상태라 코드(`_refresh`)가 변형 이름만 바꾼다.
#
# 잇는 쪽은 `_items()`(카드 데이터 배열) · `_make_card(item)`(채운 카드 버튼) ·
# `_hint_text()` 셋만 채운다. 고른 값은 `selected_id`(카드 데이터의 `id`).

signal back_requested
signal next_requested

## 고른 카드의 `id`. -1 = 아직 없음.
var selected_id: int = -1

var _cards: Dictionary = {}       # id → Button
var _built: bool = false


func _ready() -> void:
	if not _built:
		_build()
		_built = true
	if UiPreview.is_standalone(self):
		_fill_preview()


# ── 잇는 쪽이 채우는 것 ──────────────────────────────────────────────────────
func _items() -> Array:
	return []


## 카드 한 장 — 아이템 씬을 만들어 `item` 으로 채운 버튼. 트리에 넣는 것은 이쪽이 한다.
func _make_card(_item: Dictionary) -> Button:
	return null


func _hint_text() -> String:
	return ""


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	OutgameTheme.fit_bottom_bar(%Bar, %Safe)
	(%Hint as Label).text = _hint_text()
	var list: Control = %List
	# 씬의 견본 카드(에디터 미리보기용)는 지운다 — 목록은 데이터가 정한다.
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	for raw in _items():
		var item: Dictionary = raw
		var card: Button = _make_card(item)
		if card == null:
			continue
		list.add_child(card)
		card.pressed.connect(_on_card_pressed.bind(int(item["id"])))
		_cards[int(item["id"])] = card
	# 손가락 / 마우스로 끌어 굴린다 — 엔진의 터치 드래그 대신(`DragScroll`).
	DragScroll.attach(%Scroll)

	(%Back as Button).pressed.connect(func() -> void: back_requested.emit())
	(%Next as Button).pressed.connect(_on_next_pressed)
	_refresh()


# ── Interaction ──────────────────────────────────────────────────────────────
func select(id: int) -> void:
	selected_id = id if _cards.has(id) or not _built else -1
	if _built:
		_refresh()


func _on_card_pressed(id: int) -> void:
	select(id)


func _on_next_pressed() -> void:
	if selected_id < 0:
		return
	next_requested.emit()


func _refresh() -> void:
	for id in _cards.keys():
		var on: bool = int(id) == selected_id
		(_cards[id] as Button).theme_type_variation = \
				&"SelectableCardButtonOn" if on else &"SelectableCardButton"
	(%Next as Button).disabled = selected_id < 0


## F6 단독 실행 미리보기 (`resources/UiPreview.gd`) — 잇는 단계(`ScenarioStepView` ·
## `TeamStepView`)는 실제 표(`RunRules`)로 이미 찼으니 둘째 카드를 고른 상태로 둔다.
## 이 틀 씬만 띄우면 카드가 없으므로 손으로 적은 시나리오 카드 세 장을 꽂는다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(back_requested)
	UiPreview.trace(next_requested)
	if _cards.is_empty():
		(%Hint as Label).text = "카드 한 장을 고르세요 — 고르기 전에는 다음이 잠깁니다."
		var samples: Array = [
			{"id": 0, "name": "표준 시즌", "salary_cap": 260, "desc": "보통 난이도 — 스타 둘까지는 넉넉합니다."},
			{"id": 1, "name": "도전자의 시즌", "salary_cap": 240, "desc": "캡이 빠듯합니다 — 신인을 섞어야 합니다."},
			{"id": 2, "name": "언더독", "salary_cap": 220, "desc": "가장 어렵습니다 — 레벨을 낮춰 캡을 맞추세요."},
		]
		for raw in samples:
			var item: Dictionary = raw
			var card := ScenarioCard.create()
			card.fill(item)
			(%List as Control).add_child(card)
			card.pressed.connect(_on_card_pressed.bind(int(item["id"])))
			_cards[int(item["id"])] = card
	var ids: Array = _cards.keys()
	if not ids.is_empty():
		select(int(ids[mini(1, ids.size() - 1)]))
