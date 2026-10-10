class_name ChoiceListView
extends Control

# 런 준비의 "카드 한 장 고르기" 단계 공용 틀 — 팀 단계(`TeamStepView`)가 이걸 잇는다.
#
#   단계 머리글 아래(`RunSetupScreen.content_top()`)부터: 안내 한 줄 → 카드 목록
#   (세로 스크롤) → 하단 바 `뒤로`(1) / `다음`(2)
#
# **모양의 정본은 `UI_View_ChoiceListView.tscn`** (안내 줄 · 스크롤 목록 · 카드 간격 · 하단 바).
# 잇는 단계는 그 씬을 상속한 씬(`UI_View_TeamStepView.tscn` — 루트 스크립트만 바꾼다)이고,
# 카드 한 장은 단계마다의 아이템 씬(`UI_Comp_TeamCard.tscn`)이다. 생성은 각 단계의 `create()`.
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
	# The list runs to the screen bottom under the capsules (visible, not tappable).
	OutgameTheme.fit_bar_shield(%BarShield)
	(%Scroll as Control).offset_bottom = OutgameTheme.bottom_inset()
	(%ListPad as MarginContainer).add_theme_constant_override("margin_bottom",
			int(OutgameTheme.bar_scroll_pad()))
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
	# The scroll bar stops a little above the capsule row instead of running behind it.
	OutgameTheme.fit_bar_scroll(%Scroll)

	(%FloatingBarButton_Back as Button).pressed.connect(func() -> void: back_requested.emit())
	(%FloatingBarButton_Next as Button).pressed.connect(_on_next_pressed)
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
	(%FloatingBarButton_Next as Button).disabled = selected_id < 0


## F6 단독 실행 미리보기 (`resources/UiPreview.gd`) — 잇는 단계(`TeamStepView`)는 실제 표
## (`RunRules`)로 이미 찼으니 둘째 카드를 고른 상태로 둔다. 이 틀 씬만 띄우면 카드가 없으므로
## 실제 팀 표의 앞 세 장을 꽂는다(안내 줄은 더미 글 — l10n 제외).
func _fill_preview() -> void:  # l10n-ignore
	UiPreview.stage(self)
	UiPreview.trace(back_requested)
	UiPreview.trace(next_requested)
	if _cards.is_empty():
		(%Hint as Label).text = "카드 한 장을 고르세요 — 고르기 전에는 다음이 잠깁니다."
		var teams: Array = RunRules.team_packages()
		var max_budget: int = 1
		for raw in teams:
			max_budget = maxi(max_budget, int((raw as Dictionary).get("budget", 0)))
		for raw in teams.slice(0, 3):
			var item: Dictionary = raw
			var card := TeamCard.create()
			card.fill(item, max_budget)
			(%List as Control).add_child(card)
			card.pressed.connect(_on_card_pressed.bind(int(item["id"])))
			_cards[int(item["id"])] = card
	var ids: Array = _cards.keys()
	if not ids.is_empty():
		select(int(ids[mini(1, ids.size() - 1)]))
