class_name CardSelectOverlay
extends Node

# Modal UI used by 버리기:N (discard), 찾기:N (search/tutor) and 보존:N
# (preserve) card effects. Owns a high-priority CanvasLayer and an ad-hoc set of
# Buttons / ColorRects that get rebuilt every time start_*() is called and freed
# in _teardown(). CardPhaseManager pauses its effect-chain processing while
# is_active() is true; the configured callbacks resume or revert the chain.
#
# Two UIs:
#   • **손패 픽** (DISCARD / PRESERVE) — the hand stays live; dragging a card onto
#     the centre drop zone pulls it out of the hand into a fan, tapping it there
#     sends it back. DISCARD throws the picks away on 확인; PRESERVE puts them
#     back into their hand slots on 확인 (or 보존 취소) and the caller only marks
#     them.
#   • **그리드** (SEARCH / CHOICE) — a full-screen scroll grid of a pile (or of
#     caller-built option cards). Neither mutates a pile itself.

var _bs: BattleSim = null

# CHOICE 는 카드를 고르는 것이 아니라 **선택지를 고르는** 모드다(단계 C 의
# 강화 3택). 그리드도 픽 규칙도 SEARCH 와 같고, 다른 것은 셋뿐이다 — 펼치는
# 것이 더미가 아니라 호출 측이 만든 표시용 카드이고, 이름순 정렬을 하지 않으며
# (알파 · 베타 · 감마의 순서 자체가 정보다), 취소 버튼이 없다.
enum Mode { NONE, DISCARD, SEARCH, PRESERVE, CHOICE }

const DIM_COLOR             := Color(0.0, 0.0, 0.0, 0.55)
const SEARCH_GRID_TOP_Y     := 220.0
# Bottom of the search grid sits above where the 확인 / 취소 buttons land
# (top-of-hand area). Keeps the deck-pick scroll list from sliding under the
# action buttons even at full scroll.
const SEARCH_GRID_BOTTOM_Y  := 1400.0
const SEARCH_COL_COUNT      := 5
const SEARCH_COL_GAP        := 12.0
const SEARCH_ROW_GAP        := 18.0
const SEARCH_GRID_SIDE_PAD  := 90.0
const BTN_W                 := 180.0
const BTN_H                 := 56.0
# 숨김 버튼이 **안전선에서 물러나는 양**. 예전에는 `BTN_BOTTOM_Y = 1830` 절대
# 좌표였는데, 디자인 화면 기준으로도 아래끝이 1886 이라 아이폰 홈 인디케이터
# 구간(대략 y ≥ 1845)에 걸쳐 있었다 — 화면에 보이지만 **눌리지 않는** 버튼이다.
# 지금은 실제 안전선에서 역산한다(1920 · 인셋 0 이면 예전과 같은 1830).
const BTN_BOTTOM_GAP        := 34.0
# Top-of-hand anchor for 확인 / 취소 buttons. Mirrors CardTargetingOverlay.
const BTN_HAND_GAP          := 10.0
const BTN_SIDE_MARGIN       := 24.0
const CONFIRM_BTN_GAP       := 12.0
const SELECTED_TINT         := Color(1.6, 1.6, 0.55, 1.0)
const GRID_DESC_W           := 560.0

# ─── State ────────────────────────────────────────────────────────────────────
var mode: int = Mode.NONE
var hidden_state: bool = false
var target_count: int = 0

# 손패 픽 (discard / preserve) — 골라 둔 카드 줄. 이름은 버리기 시절 그대로다.
var to_discard_cards: Array = []   # CardData refs in the order they were picked
var to_discard_nodes: Array = []   # Card visual nodes (live in _bs.canvas)
## 각 픽이 손패에서 떠나올 때 앉아 있던 자리. 되돌릴 때 그 자리로 다시 꽂는다 —
## 뒤에 붙이면 골랐다 무른 카드가 손패 오른쪽 끝으로 순간이동해 "무른 것"이
## 아니라 "새로 뽑은 것"처럼 읽힌다.
var _to_discard_slots: Array = []  # int

# Search / choice mode (shared grid state)
var search_selected: Array = []    # CardData refs (deck picks / option picks)
var search_grid_nodes: Array = []  # Card visual nodes inside the scroll grid

# Callbacks (CardPhaseManager binds these to its resume / cancel handlers).
var _on_complete: Callable = Callable()
var _on_cancel:   Callable = Callable()

# UI refs
var _overlay_layer: CanvasLayer = null
var _battle_dim:    ColorRect   = null   # discard mode (lives in _bs.canvas)
var _full_dim:      ColorRect   = null   # search mode (lives in _overlay_layer)
var _scroll_root:   ScrollContainer = null
var _btn_hide:      Button      = null
var _btn_cancel:    Button      = null
var _btn_confirm:   Button      = null
## 격자에서 가리키거나 누른 카드의 설명판(`CardDescBox`) — 카드 앞면에 설명문이
## 없으므로 찾기 · 선택 그리드에서는 이 판이 그 글을 든다. 한 번에 하나다.
var _desc_box:      Panel       = null


func _ready() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 10
	add_child(_overlay_layer)


# Binding step so the overlay doesn't depend on parent type at construction time.
# CardPhaseManager calls this right after `add_child(overlay)`.
func bind(bs: BattleSim) -> void:
	_bs = bs


# ─── Public state accessors ──────────────────────────────────────────────────
func is_active() -> bool:
	return mode != Mode.NONE


func is_hidden() -> bool:
	return hidden_state


## 손패에서 카드를 끌어 골라내는 모드인가 — 버리기 · 보존. 이 동안 손패는 살아
## 있고, 카드를 중앙 구역에 놓는 것이 카드가 할 수 있는 유일한 일이다.
## 숨김 중에도 참이다(픽만 `can_pick_from_hand` 가 막는다).
func is_hand_pick_mode() -> bool:
	return mode == Mode.DISCARD or mode == Mode.PRESERVE


func is_preserve_mode() -> bool:
	return mode == Mode.PRESERVE


# Tighter gate for actually accepting a pick: hand-pick mode, not hidden, and
# the picked list isn't already full.
func can_pick_from_hand() -> bool:
	return is_hand_pick_mode() and not hidden_state \
			and to_discard_cards.size() < target_count


## 지금 손패에서 실제로 버릴 수 있는 카드 수 — `보존` 키워드 카드는 빠진다.
func _discardable_hand_count() -> int:
	var n: int = 0
	for raw in _bs.player_hand:
		var cd := raw as CardData
		if cd != null and cd.is_preserved_by_keyword():
			continue
		n += 1
	return n


# ─── Entry points ────────────────────────────────────────────────────────────
func start_discard(n: int, on_complete: Callable, on_cancel: Callable) -> void:
	mode = Mode.DISCARD
	# 상한은 손패 크기가 아니라 **버릴 수 있는 카드 수**다. `보존` 키워드 카드는
	# 고를 수 없으므로(add_card_to_pick 이 거부한다) 손패 크기로 잡으면
	# 확인 버튼이 영원히 잠긴 모달이 만들어진다.
	target_count = max(0, min(n, _discardable_hand_count()))
	hidden_state = false
	to_discard_cards.clear()
	to_discard_nodes.clear()
	_to_discard_slots.clear()
	_on_complete = on_complete
	_on_cancel = on_cancel
	if target_count <= 0:
		# Nothing to discard — finish immediately.
		_finish_with_picks([])
		return
	_build_battle_dim()
	_build_buttons(true)
	_update_confirm_button()
	_refresh_visibility()


## `pile` 은 **어느 더미를 펼치는가**. 비워 두면 덱(찾기), 버린 더미를 넘기면
## 묘지 탐색(스캐빈저 · 변덕)이 된다 — 그리드도 픽 규칙도 완전히 같고 다른
## 것은 카드가 어디서 오느냐 하나뿐이라, 모드를 새로 만들지 않고 인자로 받는다.
## 고른 카드를 어느 더미에서 빼는지는 호출 측(`CardPhaseManager`)이 정한다.
func start_search(n: int, on_complete: Callable, on_cancel: Callable,
		pile: Array = []) -> void:
	mode = Mode.SEARCH
	var src: Array = pile if not pile.is_empty() else _bs.player_deck
	target_count = max(0, min(n, src.size()))
	hidden_state = false
	search_selected.clear()
	_on_complete = on_complete
	_on_cancel = on_cancel
	if target_count <= 0:
		_finish_with_picks([])
		return
	_build_full_dim()
	_build_search_grid(src)
	_build_buttons(false)
	_refresh_visibility()
	_update_confirm_button()


## 계획 중시 (`preserve:N`) · 계략 — **버리기와 같은 손패 픽**이다. 카드를 중앙
## 구역에 끌어다 놓으면 골라 둔 줄로 빠지고, 누르면 손패 원래 자리로 돌아간다.
## 확인을 누르면 골라 둔 카드가 **손패의 원래 자리로 돌아가고**, 보존 목록 등록은
## 콜백(`CardPhaseManager._on_preserve_overlay_complete` 등)이 한다. 버리기와
## 달리 **보존 취소**가 있다(카드 사용 전액 환불 / 계략은 아무것도 안 건다).
##
## (예전에는 손패를 찾기 그리드로 한 벌 더 펼쳐 골랐다 — 손에 든 카드를 고르는데
## 화면 전체가 다른 목록으로 덮였다.)
func start_preserve(n: int, on_complete: Callable, on_cancel: Callable) -> void:
	mode = Mode.PRESERVE
	target_count = max(0, min(n, _bs.player_hand.size()))
	hidden_state = false
	to_discard_cards.clear()
	to_discard_nodes.clear()
	_to_discard_slots.clear()
	_on_complete = on_complete
	_on_cancel = on_cancel
	if target_count <= 0:
		_finish_with_picks([])
		return
	_build_battle_dim()
	_build_buttons(false)
	_update_confirm_button()
	_refresh_visibility()


## 단계 C 의 강화 3택 — `options`(표시용 CardData 배열)를 찾기와 같은 그리드로
## 펼쳐 **하나**를 고르게 한다. 고른 카드는 어느 더미에도 들어가지 않는다:
## 이 오버레이는 픽만 돌려주고 그 뜻을 읽는 것은 `CardPhaseManager` 다.
##
## **취소가 없다.** 여기까지 온 시점에 카드는 이미 나갔고 앞선 절도 이미 돌았다 —
## 무를 것이 남아 있지 않으므로, 취소 버튼을 놓으면 되돌아갈 곳 없는 취소가 된다.
func start_choice(options: Array, on_complete: Callable) -> void:
	mode = Mode.CHOICE
	target_count = 1
	hidden_state = false
	search_selected.clear()
	_on_complete = on_complete
	_on_cancel = Callable()
	if options.is_empty():
		_finish_with_picks([])
		return
	_build_full_dim()
	_build_search_grid(options, false)
	_build_buttons(false)
	_refresh_visibility()
	_update_confirm_button()


# ─── Player interactions ─────────────────────────────────────────────────────
# Called from CardPhaseManager when a hand card is dropped on the centre zone
# in 버리기 / 보존 픽. The card is removed from the live hand and parked in the
# centered picked row until the player presses 확인 (enabled once exactly
# target_count cards have been picked).
func add_card_to_pick(node: Card) -> void:
	if not can_pick_from_hand():
		return
	if not _bs.player_card_nodes.has(node):
		return
	var cd: CardData = node.data
	# `보존` 키워드 카드는 버릴 수 없다 — 오브젝트 보상처럼 한 매치에 한 장
	# 나오는 카드가 버리기:N 한 번에 사라지면 안 된다. `target_count` 도 같은
	# 규칙으로 잡혀 있으므로 고를 카드가 모자라는 일은 없다.
	if mode == Mode.DISCARD and cd != null and cd.is_preserved_by_keyword():
		return
	var slot: int = _bs.player_hand.find(cd)
	_bs.player_card_nodes.erase(node)
	_bs.player_hand.erase(cd)
	to_discard_cards.append(cd)
	to_discard_nodes.append(node)
	_to_discard_slots.append(maxi(0, slot))
	# **골라 둔 카드를 누르면 손패로 돌아간다.** 카드 자신은 손패에서와 같이
	# 마우스를 잡지 않으므로(`_set_subtree_mouse_ignore`), 손패 히트 레이어가
	# 하던 일을 여기서는 카드 위에 얹는 투명 버튼 하나가 대신한다 — 찾기 그리드가
	# 쓰는 것과 같은 수법이다.
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attach_unpick_overlay(node)
	_bs.card_phase.relayout_hand(_bs.player_card_nodes)
	_layout_to_discard_row()
	# No auto-commit on the Nth pick — the player explicitly confirms via the
	# 확인 button now. _update_confirm_button gates the button on
	# to_discard_cards.size() == target_count.
	_update_confirm_button()


## 골라 둔 카드 위에 얹는 투명 버튼. 누르면 그 카드가 손패로 돌아간다.
func _attach_unpick_overlay(node: Card) -> void:
	var hit := Button.new()
	hit.name = "UnpickHit"
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	hit.flat = true
	hit.size = Vector2(Card.CARD_W, Card.CARD_H)
	hit.position = Vector2.ZERO
	hit.modulate = Color(1, 1, 1, 0)
	hit.pressed.connect(func() -> void: remove_card_from_pick(node))
	node.add_child(hit)


## 골라 둔 줄에서 빼내 **원래 자리로** 손패에 돌려놓는다. 카드 노드는 그대로
## 재사용한다 — 새로 세우면 드로우 인트로를 타거나(왼쪽 밖에서 날아온다) 그
## 카드에 걸려 있던 표시(보존 테두리 · 충전 배지)를 다시 붙여야 한다.
func remove_card_from_pick(node: Card) -> void:
	if not is_hand_pick_mode() or hidden_state:
		return
	_return_pick_to_hand(to_discard_nodes.find(node))
	_bs.card_phase.relayout_hand(_bs.player_card_nodes)
	_layout_to_discard_row()
	_update_confirm_button()


## 골라 둔 줄의 `i` 번째를 손패 원래 자리에 다시 꽂는다(배치는 부르는 쪽이 한다).
func _return_pick_to_hand(i: int) -> void:
	if i < 0 or i >= to_discard_nodes.size():
		return
	var node := to_discard_nodes[i] as Card
	var cd := to_discard_cards[i] as CardData
	var slot: int = int(_to_discard_slots[i])
	to_discard_nodes.remove_at(i)
	to_discard_cards.remove_at(i)
	_to_discard_slots.remove_at(i)
	# 트리에서 **먼저 떼고** 해제한다 — `queue_free` 만으로는 이 프레임이 끝날
	# 때까지 버튼이 카드 위에 남아, 손패로 돌아간 카드를 한 번 더 누르면 이미
	# 목록에서 빠진 노드로 무르기가 다시 돈다.
	var hit: Node = node.get_node_or_null("UnpickHit")
	if hit != null:
		node.remove_child(hit)
		hit.queue_free()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot = clampi(slot, 0, _bs.player_hand.size())
	_bs.player_hand.insert(slot, cd)
	_bs.player_card_nodes.insert(mini(slot, _bs.player_card_nodes.size()), node)


## 골라 둔 카드 전원을 손패로 — **고른 역순으로** 꽂아야 각자 떠나올 때의 인덱스가
## 그대로 맞는다(보존 확인 / 보존 취소).
func _return_all_picks_to_hand() -> void:
	for i in range(to_discard_nodes.size() - 1, -1, -1):
		_return_pick_to_hand(i)
	_bs.card_phase.relayout_hand(_bs.player_card_nodes)


# Toggles the highlight + selection state of a deck card in the search grid.
# Clamps to target_count selections at most.
func _toggle_search_pick(cd: CardData, node: Card) -> void:
	if not _is_grid_mode() or hidden_state:
		return
	if cd in search_selected:
		search_selected.erase(cd)
		node.modulate = Color.WHITE
	else:
		if search_selected.size() >= target_count:
			return
		search_selected.append(cd)
		node.modulate = SELECTED_TINT
	_update_confirm_button()


# ─── Commit / cancel ─────────────────────────────────────────────────────────
func _commit_discard() -> void:
	# Hooked to the 확인 button — only fires when target_count picks have been
	# placed. Guard against accidental external calls (or stale signals).
	if to_discard_cards.size() != target_count:
		return
	var picks := to_discard_cards.duplicate()
	# 중앙에 늘어선 카드들도 손패에서 버릴 때와 **같은 연출**로 내려보낸다.
	# `_teardown` 은 to_discard_nodes 를 그 자리에서 free 하므로, 연출을 넘길
	# 노드는 목록에서 먼저 떼어 낸다.
	var dropping := to_discard_nodes.duplicate()
	to_discard_nodes.clear()
	# 무르기 버튼은 노드와 함께 떠나므로 연출 도중에 다시 눌릴 수 없다.
	for raw in dropping:
		var node := raw as Card
		var hit: Node = node.get_node_or_null("UnpickHit")
		if hit != null:
			node.remove_child(hit)
			hit.queue_free()
	_teardown()
	for raw in dropping:
		var node := raw as Card
		if is_instance_valid(node) and _bs.card_phase != null:
			_bs.card_phase.play_discard_fx(node)
	_finish_with_picks(picks)


## 보존 확인 — 골라 둔 카드는 손패 원래 자리로 돌아가고, 보존 표시는 콜백이 건다.
func _commit_preserve() -> void:
	if to_discard_cards.size() != target_count:
		return
	var picks := to_discard_cards.duplicate()
	_return_all_picks_to_hand()
	_teardown()
	_finish_with_picks(picks)


func _commit_search() -> void:
	if search_selected.size() != target_count:
		return
	var picks := search_selected.duplicate()
	_teardown()
	_finish_with_picks(picks)


## SEARCH · CHOICE 둘이 같은 스크롤 그리드 UI 를 쓴다.
func _is_grid_mode() -> bool:
	return mode == Mode.SEARCH or mode == Mode.CHOICE


func _finish_with_picks(picks: Array) -> void:
	var cb := _on_complete
	mode = Mode.NONE
	_on_complete = Callable()
	_on_cancel = Callable()
	if cb.is_valid():
		cb.call(picks)


func _on_cancel_pressed() -> void:
	var cb := _on_cancel
	# 보존 취소 — 골라 둔 카드를 손패로 먼저 돌려놓는다. `_teardown` 은 줄에 남은
	# 노드를 해제하므로, 스냅샷 복원이 없는 호출(계략)에서는 그 카드가 사라진다.
	if mode == Mode.PRESERVE:
		_return_all_picks_to_hand()
	_teardown()
	mode = Mode.NONE
	_on_complete = Callable()
	_on_cancel = Callable()
	if cb.is_valid():
		cb.call()


func _on_hide_pressed() -> void:
	hidden_state = not hidden_state
	# While hidden, the description box / lifted-card state would obscure the
	# now-visible battle. Drop any active selection so the pick UI re-arms
	# cleanly when the player un-hides.
	if hidden_state and _bs.card_phase != null:
		_bs.card_phase.deselect_current_card()
	_refresh_visibility()
	_refresh_hide_label()


# ─── UI construction ─────────────────────────────────────────────────────────
func _build_battle_dim() -> void:
	# Discard mode dims only the battle area, NOT the hand. We add the dim to
	# _bs.canvas (same CanvasLayer as the hand cards) at child position 0 so
	# every existing canvas child — HUD, cost bars, hand cards — still draws on
	# top of the dim. The overlay buttons live on _overlay_layer above all of
	# this.
	_battle_dim = ColorRect.new()
	_battle_dim.color = DIM_COLOR
	_battle_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battle_dim.position = Vector2.ZERO
	_battle_dim.size = Vector2(ScreenMetrics.vp_w(), _bs.BS_HAND_CENTER.y)
	_bs.canvas.add_child(_battle_dim)
	_bs.canvas.move_child(_battle_dim, 0)


func _build_full_dim() -> void:
	# Search mode dims everything; the full-screen rect lives on the high-layer
	# overlay so it sits above the hand and HUD too.
	_full_dim = ColorRect.new()
	_full_dim.color = DIM_COLOR
	_full_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_full_dim.position = Vector2.ZERO
	_full_dim.size = ScreenMetrics.viewport_size()
	_overlay_layer.add_child(_full_dim)


func _build_buttons(is_discard: bool) -> void:
	_btn_hide = _make_btn("숨김")
	_btn_hide.position = Vector2(BTN_SIDE_MARGIN,
			ScreenMetrics.bottom_y() - BTN_BOTTOM_GAP - BTN_H)
	_btn_hide.pressed.connect(_on_hide_pressed)
	_overlay_layer.add_child(_btn_hide)

	# 확인 / 취소 hover at the top-right of the hand area so the player's
	# attention stays anchored where the cards are. _btn_top_y derives from
	# BS_HAND_CENTER.y so any future hand-row movement carries the buttons.
	var top_y: float = _bs.BS_HAND_CENTER.y - BTN_HAND_GAP - BTN_H
	var right_x: float = ScreenMetrics.right_x() - BTN_SIDE_MARGIN - BTN_W

	# 취소가 없는 두 모드 — 버리기와 강화 3택. 버리기는 시작한 이상 정확히
	# target_count 장을 골라야 끝나고, 3택은 이미 나간 카드의 정산이라 무를 것이
	# 없다. 둘 다 확인 버튼과 숨김만 놓는다.
	if is_discard or mode == Mode.CHOICE:
		_btn_confirm = _make_btn("확인")
		_btn_confirm.position = Vector2(right_x, top_y)
		if mode == Mode.DISCARD:
			_btn_confirm.pressed.connect(_commit_discard)
		else:
			_btn_confirm.pressed.connect(_commit_search)
		_btn_confirm.disabled = true
		_overlay_layer.add_child(_btn_confirm)
	else:
		_btn_cancel = _make_btn("보존 취소" if mode == Mode.PRESERVE else "찾기 취소")
		_btn_cancel.position = Vector2(right_x, top_y)
		_btn_cancel.pressed.connect(_on_cancel_pressed)
		_overlay_layer.add_child(_btn_cancel)
		_btn_confirm = _make_btn("확인")
		_btn_confirm.position = Vector2(
				right_x - CONFIRM_BTN_GAP - BTN_W, top_y)
		if mode == Mode.PRESERVE:
			_btn_confirm.pressed.connect(_commit_preserve)
		else:
			_btn_confirm.pressed.connect(_commit_search)
		_btn_confirm.disabled = true
		_overlay_layer.add_child(_btn_confirm)


func _make_btn(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 22)
	b.size = Vector2(BTN_W, BTN_H)
	return b


## Lays `source` out as the 5-column scroll grid SEARCH / PRESERVE / CHOICE all
## pick from. `source` is never mutated — the picks come back as CardData refs.
##
## `sort_names` 가 false 면 넘어온 순서를 그대로 쓴다. 강화 3택이 그 경우다 —
## 알파 · 베타 · 감마는 더미가 아니라 **정해진 순서가 있는 목록**이라, 이름순으로
## 다시 세우면 감마 · 베타 · 알파가 되어 카드 설명문의 차례와 어긋난다.
func _build_search_grid(source: Array, sort_names: bool = true) -> void:
	# 이름 오름차순으로 펼친다 — 실제 더미 순서를 그대로 보여 주면 그리드가 곧
	# "다음에 뽑을 순서" 표가 되어 버린다. 정렬은 표시용 복사본에만 하고 원본은
	# 건드리지 않는다 (picks 는 CardData 참조라 순서와 무관).
	# CardPileViewer 의 열람 목록도 같은 규칙을 쓴다.
	var deck: Array = _sorted_for_display(source) if sort_names else source.duplicate()
	if deck.is_empty():
		return
	var grid_w: float = ScreenMetrics.vp_w() - 2.0 * SEARCH_GRID_SIDE_PAD
	var grid_h: float = SEARCH_GRID_BOTTOM_Y - SEARCH_GRID_TOP_Y

	_scroll_root = ScrollContainer.new()
	_scroll_root.position = Vector2(SEARCH_GRID_SIDE_PAD, SEARCH_GRID_TOP_Y)
	_scroll_root.size = Vector2(grid_w, grid_h)
	_scroll_root.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_overlay_layer.add_child(_scroll_root)

	var inner := Control.new()
	var rows: int = int(ceil(float(deck.size()) / float(SEARCH_COL_COUNT)))
	var inner_h: float = float(rows) * Card.CARD_H \
			+ float(max(rows - 1, 0)) * SEARCH_ROW_GAP
	inner.custom_minimum_size = Vector2(grid_w, inner_h)
	inner.size = inner.custom_minimum_size
	# 기본값(STOP)이면 카드 사이 빈 자리를 눌러도 그 이벤트가 여기서 끊겨
	# ScrollContainer 가 드래그 스크롤을 시작하지 못한다.
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_root.add_child(inner)

	# Cell width: 5 columns evenly spaced inside the grid; cards keep their
	# native CARD_W and centre themselves in the column slack.
	var col_w: float = (grid_w - float(SEARCH_COL_COUNT - 1) * SEARCH_COL_GAP) \
			/ float(SEARCH_COL_COUNT)
	for i in deck.size():
		var cd := deck[i] as CardData
		var node := _bs.CARD_SCENE.instantiate() as Card
		# add_child BEFORE setup — Card.gd's @onready node refs only resolve
		# after the scene tree pass, and setup() touches them via _apply_data.
		inner.add_child(node)
		# is_player_card=false so Card._on_mouse_entered short-circuits — its
		# hover-brighten tween would otherwise stomp our SELECTED_TINT
		# modulate on every hover. mouse_filter=IGNORE keeps Card._gui_input
		# from intercepting the click before the Button overlay below sees it.
		node.setup(cd, false, true)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col: int = i % SEARCH_COL_COUNT
		@warning_ignore("integer_division")
		var row: int = i / SEARCH_COL_COUNT
		var x: float = float(col) * (col_w + SEARCH_COL_GAP) \
				+ (col_w - Card.CARD_W) * 0.5
		var y: float = float(row) * (Card.CARD_H + SEARCH_ROW_GAP)
		node.position = Vector2(x, y)
		_attach_search_pick_overlay(node, cd)
		search_grid_nodes.append(node)


# 이름(오름차순) → 같은 카드(`card_uid`)면 비용 순 정렬본. 원본 배열은 그대로 둔다.
func _sorted_for_display(src: Array) -> Array:
	var out: Array = src.duplicate()
	out.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.card_uid() == b.card_uid():
			return a.cost < b.cost
		return a.card_name.naturalnocasecmp_to(b.card_name) < 0)
	return out


func _attach_search_pick_overlay(node: Card, cd: CardData) -> void:
	# A flat, fully-transparent Button sized to the card. The Card underneath
	# is MOUSE_FILTER_IGNORE, so it never sees the click regardless.
	# **PASS, not the Button default STOP** — this sits inside a
	# ScrollContainer and STOP would stop the emulated mouse press from
	# reaching it, killing touch drag-scroll on mobile.
	var hit := Button.new()
	hit.mouse_filter = Control.MOUSE_FILTER_PASS
	hit.flat = true
	hit.size = Vector2(Card.CARD_W, Card.CARD_H)
	hit.position = Vector2.ZERO
	hit.modulate = Color(1, 1, 1, 0)
	hit.pressed.connect(func() -> void:
		_toggle_search_pick(cd, node)
		_show_grid_desc(node, cd))
	hit.mouse_entered.connect(func() -> void: _show_grid_desc(node, cd))
	hit.mouse_exited.connect(_hide_grid_desc)
	node.add_child(hit)


## 격자 카드 하나의 설명판을 그 카드 아래(자리가 없으면 위)에 띄운다.
func _show_grid_desc(node: Card, cd: CardData) -> void:
	_hide_grid_desc()
	if node == null or not is_instance_valid(node) or cd == null:
		return
	_desc_box = CardDescBox.build(cd, GRID_DESC_W)
	_overlay_layer.add_child(_desc_box)
	CardDescBox.place_near(_desc_box, node.get_global_rect(),
			ScreenMetrics.viewport_size())


func _hide_grid_desc() -> void:
	if _desc_box != null and is_instance_valid(_desc_box):
		_desc_box.queue_free()
	_desc_box = null


# Lays out the picked-for-discard cards in a horizontal fan that mirrors the
# hand row's spacing (so it visually reads as "a hand of cards being set
# aside").
## 골라 둔 카드가 늘어서는 줄의 세로 중심. **카드를 놓는 구역과 같은 중심**이라
## "놓은 자리에 그대로 늘어선다"가 된다 — 예전의 고정 700 은 구역이 화면 중앙일
## 때 줄이 그 위쪽에 걸려 놓은 곳과 쌓이는 곳이 어긋났다.
func to_discard_center_y() -> float:
	if _bs != null and _bs.card_phase != null:
		return _bs.card_phase.drop_zone_rect().get_center().y
	return ScreenMetrics.viewport_size().y * 0.5


func _layout_to_discard_row() -> void:
	var n: int = to_discard_nodes.size()
	if n == 0:
		return
	# 손패에서 그대로 들려 나온 카드들이므로 **배율도 손패 그대로**다 — 여기서
	# 1.0 으로 돌리면 골라 둘 때 작아지고 무를 때 다시 커진다. 폭을 재는 자리도
	# 확대된 폭이어야 간격이 손패와 같은 겹침으로 떨어진다.
	var card_w: float = CardPhaseManager.hand_card_w()
	var slot_y: float = to_discard_center_y() - Card.CARD_H * 0.5
	var hand_w: float = _bs.BS_HAND_WIDTH
	var visual_cx: float = ScreenMetrics.center_x()
	var ideal_total: float = float(n) * card_w \
			+ float(max(n - 1, 0)) * _bs.BS_HAND_CARD_GAP
	var spacing: float = card_w + _bs.BS_HAND_CARD_GAP
	if n > 1 and ideal_total > hand_w:
		spacing = (hand_w - card_w) / float(n - 1)
	var first_x: float = visual_cx - float(n - 1) * spacing * 0.5 \
			- Card.CARD_W * 0.5
	for i in n:
		var node := to_discard_nodes[i] as Card
		var pos := Vector2(first_x + float(i) * spacing, slot_y)
		node.tween_to(pos, 0.0, Vector2.ONE * CardPhaseManager.HAND_CARD_SCALE,
				_bs.BS_HAND_SPRING_DURATION,
				_bs.BS_HAND_TWEEN_EASE, _bs.BS_HAND_TWEEN_TRANS)


# 숨김 hides the dim + selection display so the player can review the battle.
# In hidden state, picking is disabled (can_pick_from_hand returns false and
# the search grid is not visible) but the cancel / confirm / hide buttons all
# stay reachable so the player can resolve the overlay either way.
func _refresh_visibility() -> void:
	var show := not hidden_state
	if is_hand_pick_mode():
		if _battle_dim != null:
			_battle_dim.visible = show
		for node in to_discard_nodes:
			(node as Card).visible = show
	elif _is_grid_mode():
		if _full_dim != null:
			_full_dim.visible = show
		if _scroll_root != null:
			_scroll_root.visible = show
	_refresh_hide_label()


func _refresh_hide_label() -> void:
	if _btn_hide != null:
		_btn_hide.text = "표시" if hidden_state else "숨김"


func _update_confirm_button() -> void:
	if _btn_confirm == null:
		return
	if is_hand_pick_mode():
		_btn_confirm.disabled = to_discard_cards.size() != target_count
	else:
		_btn_confirm.disabled = search_selected.size() != target_count


func _teardown() -> void:
	_hide_grid_desc()
	if _battle_dim != null and is_instance_valid(_battle_dim):
		_battle_dim.queue_free()
	_battle_dim = null
	if _full_dim != null and is_instance_valid(_full_dim):
		_full_dim.queue_free()
	_full_dim = null
	for node in to_discard_nodes:
		if is_instance_valid(node):
			(node as Card).queue_free()
	to_discard_nodes.clear()
	to_discard_cards.clear()
	_to_discard_slots.clear()
	for node in search_grid_nodes:
		if is_instance_valid(node):
			(node as Card).queue_free()
	search_grid_nodes.clear()
	search_selected.clear()
	if _scroll_root != null and is_instance_valid(_scroll_root):
		_scroll_root.queue_free()
	_scroll_root = null
	if _btn_hide != null and is_instance_valid(_btn_hide):
		_btn_hide.queue_free()
	_btn_hide = null
	if _btn_cancel != null and is_instance_valid(_btn_cancel):
		_btn_cancel.queue_free()
	_btn_cancel = null
	if _btn_confirm != null and is_instance_valid(_btn_confirm):
		_btn_confirm.queue_free()
	_btn_confirm = null
	hidden_state = false
