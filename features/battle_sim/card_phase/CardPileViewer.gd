class_name CardPileViewer
extends Node

# Deck / Discard 목록 열람 오버레이 (읽기 전용).
#
# 핸드 행 양옆의 "Deck n" / "Discard n" 카운터를 누르면 열린다 — 찾기(search)
# 오버레이와 같은 5열 그리드로 해당 더미의 카드를 전부 펼쳐 보여 주고, 고를 수
# 있는 것은 아무것도 없다. 카드 순서는 **이름 오름차순**으로 정렬해 실제 덱
# 순서(= 다음에 뽑을 카드)를 노출하지 않는다.
#
# 열 수 있는 시점은 작전 단계뿐 — 게이트는 CardPhaseManager.can_browse_piles().
# 열려 있는 동안에는 핸드 입력 / 턴 넘기기 / 도넛 플립이 모두 잠긴다
# (CardPhaseManager._is_player_input_blocked / can_end_card_phase,
#  HudBuilder._update_cost_donuts 가 is_active() 를 읽는다).

enum Pile { NONE, DECK, DISCARD }

# 버리기(10) / 대상 지정(11) 오버레이보다 위. 열람 중에는 그 둘이 화면에
# 남아 있어도 전부 딤 아래로 들어간다.
const OVERLAY_LAYER      := 12
const DIM_COLOR          := Color(0.0, 0.0, 0.0, 0.72)
const TITLE_Y            := 132.0
const TITLE_H            := 52.0
const TITLE_FONT         := 34
const TITLE_COLOR        := Color(0.92, 0.92, 0.96)
const GRID_TOP_Y         := 208.0
const GRID_BOTTOM_Y      := 1400.0
const GRID_SIDE_PAD      := 90.0
const COL_COUNT          := 5
const COL_GAP            := 12.0
const ROW_GAP            := 18.0
const EMPTY_FONT         := 28
const EMPTY_COLOR        := Color(0.72, 0.72, 0.78)
# 닫기 버튼은 CardSelectOverlay / CardTargetingOverlay 의 확인·취소와 같은
# 밴드(핸드 행 바로 위 우측)에 앉는다.
const BTN_W              := 180.0
const BTN_H              := 56.0
const BTN_HAND_GAP       := 10.0
const BTN_SIDE_MARGIN    := 24.0

var _bs: BattleSim = null

var pile: int = Pile.NONE

var _overlay_layer: CanvasLayer = null
var _dim:           ColorRect   = null
var _title:         Label       = null
var _scroll_root:   ScrollContainer = null
var _btn_close:     Button      = null
var _card_nodes:    Array       = []   # Array<Card> — grid 안의 시각 노드


func _ready() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = OVERLAY_LAYER
	add_child(_overlay_layer)


# CardSelectOverlay 와 같은 패턴 — BattleSim._ready 가 add_child 직후 호출한다.
func bind(bs: BattleSim) -> void:
	_bs = bs


func is_active() -> bool:
	return pile != Pile.NONE


# ─── Open / close ────────────────────────────────────────────────────────────
func open(which: int) -> void:
	if which != Pile.DECK and which != Pile.DISCARD:
		return
	if is_active():
		_teardown()
	pile = which
	_build_ui()
	_refresh_dependents()


func close() -> void:
	if not is_active():
		return
	_teardown()
	pile = Pile.NONE
	_refresh_dependents()


# 핸드 딤 / 턴 넘기기 / 도넛 플립은 전부 is_active() 를 읽으므로, 열고 닫을
# 때마다 한 번씩 다시 계산해 준다.
func _refresh_dependents() -> void:
	if _bs == null:
		return
	if _bs.card_phase != null:
		_bs.card_phase.highlight_affordable_cards()   # tail-calls _apply_hand_dim_state()
	if _bs.hud != null:
		_bs.hud.update_hud()


# ─── UI construction ─────────────────────────────────────────────────────────
func _build_ui() -> void:
	var screen := _screen_size()
	_dim = ColorRect.new()
	_dim.color = DIM_COLOR
	_dim.position = Vector2.ZERO
	_dim.size = screen
	# STOP so nothing underneath (핸드 히트 레이어 / 확인·취소 / 전장) reacts
	# while the list is up; the press itself closes the viewer.
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_gui_input)
	_overlay_layer.add_child(_dim)

	var cards := _sorted_cards()
	_title = Label.new()
	_title.text = "%s — %d장" % [_pile_label(), cards.size()]
	_title.add_theme_font_size_override("font_size", TITLE_FONT)
	_title.add_theme_color_override("font_color", TITLE_COLOR)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.position = Vector2(0.0, TITLE_Y)
	_title.size = Vector2(screen.x, TITLE_H)
	_overlay_layer.add_child(_title)

	if cards.is_empty():
		_build_empty_notice(screen)
	else:
		_build_grid(cards, screen)

	_btn_close = Button.new()
	_btn_close.text = "닫기"
	_btn_close.add_theme_font_size_override("font_size", 22)
	_btn_close.size = Vector2(BTN_W, BTN_H)
	_btn_close.position = Vector2(
			screen.x - BTN_SIDE_MARGIN - BTN_W,
			_bs.BS_HAND_CENTER.y - BTN_HAND_GAP - BTN_H)
	_btn_close.pressed.connect(close)
	_overlay_layer.add_child(_btn_close)


func _build_empty_notice(screen: Vector2) -> void:
	var lbl := Label.new()
	lbl.text = "비어 있음"
	lbl.add_theme_font_size_override("font_size", EMPTY_FONT)
	lbl.add_theme_color_override("font_color", EMPTY_COLOR)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.position = Vector2(0.0, GRID_TOP_Y)
	lbl.size = Vector2(screen.x, 120.0)
	_overlay_layer.add_child(lbl)


# 찾기 그리드와 같은 5열 스크롤 레이아웃. 다른 점은 클릭 오버레이가 붙지
# 않는다는 것뿐 — 열람 전용이라 고를 수 있는 카드가 없다.
func _build_grid(cards: Array, screen: Vector2) -> void:
	var grid_w: float = screen.x - 2.0 * GRID_SIDE_PAD
	var grid_h: float = GRID_BOTTOM_Y - GRID_TOP_Y

	_scroll_root = ScrollContainer.new()
	_scroll_root.position = Vector2(GRID_SIDE_PAD, GRID_TOP_Y)
	_scroll_root.size = Vector2(grid_w, grid_h)
	_scroll_root.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_overlay_layer.add_child(_scroll_root)

	var inner := Control.new()
	var rows: int = int(ceil(float(cards.size()) / float(COL_COUNT)))
	var inner_h: float = float(rows) * Card.CARD_H \
			+ float(max(rows - 1, 0)) * ROW_GAP
	inner.custom_minimum_size = Vector2(grid_w, inner_h)
	inner.size = inner.custom_minimum_size
	_scroll_root.add_child(inner)

	var col_w: float = (grid_w - float(COL_COUNT - 1) * COL_GAP) / float(COL_COUNT)
	for i in cards.size():
		var cd := cards[i] as CardData
		var node := _bs.CARD_SCENE.instantiate() as Card
		# add_child BEFORE setup — Card.gd 의 @onready 참조가 트리 진입 후에야
		# 풀린다 (CardSelectOverlay._build_search_grid 와 동일).
		inner.add_child(node)
		# is_player_card=false → 호버 브라이튼 / 그림자가 붙지 않는다.
		node.setup(cd, false, true)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col: int = i % COL_COUNT
		@warning_ignore("integer_division")
		var row: int = i / COL_COUNT
		node.position = Vector2(
				float(col) * (col_w + COL_GAP) + (col_w - Card.CARD_W) * 0.5,
				float(row) * (Card.CARD_H + ROW_GAP))
		_card_nodes.append(node)


# ─── Data ────────────────────────────────────────────────────────────────────
# 이름 오름차순. 실제 배열 순서를 그대로 보여 주면 덱 위쪽(= 다음 드로우)이
# 그대로 읽히므로 정렬본을 만들어 쓴다 — 원본 배열은 건드리지 않는다.
# 같은 이름이면 비용 순으로 안정화해 카드 순서가 열 때마다 흔들리지 않게 한다.
func _sorted_cards() -> Array:
	var src: Array = _pile_array()
	var out: Array = src.duplicate()
	out.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.card_name == b.card_name:
			return a.cost < b.cost
		return a.card_name.naturalnocasecmp_to(b.card_name) < 0)
	return out


func _pile_array() -> Array:
	if _bs == null:
		return []
	return _bs.player_deck if pile == Pile.DECK else _bs.player_discard


func _pile_label() -> String:
	return "덱" if pile == Pile.DECK else "버린 카드"


func _screen_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return ScreenMetrics.viewport_size()
	return vp.get_visible_rect().size


# ─── Input ───────────────────────────────────────────────────────────────────
func _on_dim_gui_input(event: InputEvent) -> void:
	var pressed: bool = false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pressed = true
	elif event is InputEventScreenTouch and event.pressed:
		pressed = true
	if pressed:
		_dim.accept_event()
		close()


# ─── Teardown ────────────────────────────────────────────────────────────────
func _teardown() -> void:
	for raw in _card_nodes:
		var node := raw as Card
		if is_instance_valid(node):
			node.queue_free()
	_card_nodes.clear()
	for child in _overlay_layer.get_children():
		child.queue_free()
	_dim = null
	_title = null
	_scroll_root = null
	_btn_close = null
