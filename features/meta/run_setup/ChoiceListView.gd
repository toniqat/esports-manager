class_name ChoiceListView
extends Control

# 런 준비의 "카드 한 장 고르기" 단계 공용 틀 — 시나리오 · 팀 단계가 이걸 잇는다.
#
#   단계 머리글 아래(`RunSetupScreen.content_top()`)부터: 안내 한 줄 → 카드 목록
#   (세로 스크롤) → 하단 바 `뒤로`(1) / `다음`(2)
#
# 카드는 통째로 하나의 `Button` 이다 — 누르면 고른 것이 되고(앰버 테두리),
# `다음` 은 하나를 골랐을 때만 풀린다. 카드는 `ScrollContainer` 안에 있으므로
# `MOUSE_FILTER_PASS` 여야 `DragScroll` 이 끌기를 판정한다(`docs/mobile_safe_area.md` §5).
#
# 잇는 쪽은 `_items()`(카드 데이터 배열) · `_card_h(item)` · `_fill_card(card, item, w)`
# · `_hint_text()` 넷만 채운다. 고른 값은 `selected_id`(카드 데이터의 `id`).

signal back_requested
signal next_requested

const LIST_X: float = 24.0
const LIST_W: float = 1032.0
const HINT_H: float = 44.0
const CARD_GAP: float = 20.0
const CARD_PAD: float = 32.0
const CARD_RADIUS: int = 20
const LIST_BAR_GAP: float = 16.0

## 고른 카드의 `id`. -1 = 아직 없음.
var selected_id: int = -1

var _cards: Dictionary = {}       # id → Button
var _next_btn: Button
var _built: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	if not _built:
		_build()
		_built = true


# ── 잇는 쪽이 채우는 것 ──────────────────────────────────────────────────────
func _items() -> Array:
	return []


func _card_h(_item: Dictionary) -> float:
	return 200.0


func _fill_card(_card: Control, _item: Dictionary, _w: float) -> void:
	pass


func _hint_text() -> String:
	return ""


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	var top: float = RunSetupScreen.content_top()
	var hint := UiHelpers.mk_label(self, _hint_text(), 24, OutgameTheme.TEXT_SUB,
			Vector2(LIST_X + 8.0, top), Vector2(LIST_W - 16.0, HINT_H))
	hint.clip_text = true

	var list_y: float = top + HINT_H + 8.0
	var list_h: float = OutgameTheme.bottom_bar_top() - LIST_BAR_GAP - list_y
	var sv: Dictionary = OutgameTheme.add_vscroll(self,
			Vector2(LIST_X, list_y), Vector2(LIST_W, list_h))
	var body: Control = sv["body"]
	body.mouse_filter = Control.MOUSE_FILTER_PASS

	var y: float = 0.0
	for raw in _items():
		var item: Dictionary = raw
		var h: float = _card_h(item)
		var card := Button.new()
		card.text = ""
		card.focus_mode = Control.FOCUS_NONE
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		card.position = Vector2(0.0, y)
		card.size = Vector2(LIST_W, h)
		card.pressed.connect(_on_card_pressed.bind(int(item["id"])))
		body.add_child(card)
		_fill_card(card, item, LIST_W - CARD_PAD * 2.0)
		_cards[int(item["id"])] = card
		y += h + CARD_GAP
	body.custom_minimum_size = Vector2(LIST_W, maxf(0.0, y - CARD_GAP))

	var bar: Array = OutgameTheme.add_bottom_bar(self, [
		{"text": "뒤로", "style": "ghost",   "font": 30, "weight": 1.0},
		{"text": "다음", "style": "primary", "font": 38, "weight": 2.0},
	])
	(bar[0] as Button).pressed.connect(func() -> void: back_requested.emit())
	_next_btn = bar[1]
	_next_btn.pressed.connect(_on_next_pressed)
	_refresh()


## 카드 안의 글자 한 줄. 카드가 버튼이라 글자는 입력을 막지 않게 IGNORE.
func add_text(card: Control, text: String, font: int, color: Color,
		pos: Vector2, sz: Vector2, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiHelpers.mk_label(card, text, font, color, pos, sz, align)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	return l


## 줄바꿈되는 설명 문단. 높이는 카드가 정한 고정값 — 트리에 들기 전의
## 자동 줄바꿈 Label 은 높이를 0 으로 잰다.
func add_para(card: Control, text: String, font: int, color: Color,
		pos: Vector2, sz: Vector2) -> Label:
	var l := UiHelpers.mk_label(card, text, font, color, pos, sz)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.clip_text = true
	return l


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
		var sty := OutgameTheme.flat_style(
				OutgameTheme.ACCENT_DIM if on else OutgameTheme.SURFACE, CARD_RADIUS,
				OutgameTheme.ACCENT if on else OutgameTheme.BORDER, 4 if on else 2)
		var card: Button = _cards[id]
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			card.add_theme_stylebox_override(st, sty)
	_next_btn.disabled = selected_id < 0
