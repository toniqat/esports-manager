class_name CardSelectOverlay
extends Node

# Modal UI used by 버리기:N (discard) and 찾기:N (search/tutor) card effects.
# Owns a high-priority CanvasLayer and an ad-hoc set of Buttons / ColorRects
# that get rebuilt every time start_*() is called and freed in _teardown().
# CardPhaseManager pauses its effect-chain processing while is_active() is
# true; the configured callbacks resume or revert the chain.

var _bs: BattleSim = null

enum Mode { NONE, DISCARD, SEARCH }

const DIM_COLOR             := Color(0.0, 0.0, 0.0, 0.55)
# Vertical center of the to-discard row inside the dimmed battle area
# (battle dim spans y=0..BS_HAND_CENTER.y; 700 is the visual middle).
const TO_DISCARD_CENTER_Y   := 700.0
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
# Bottom-of-screen anchor for the 숨김 button (kept where it was — it gates
# both modes and feels natural near the home-bar safe area).
const BTN_BOTTOM_Y          := 1830.0
# Top-of-hand anchor for 확인 / 취소 buttons. Mirrors CardTargetingOverlay.
const BTN_HAND_GAP          := 10.0
const BTN_SIDE_MARGIN       := 24.0
const CONFIRM_BTN_GAP       := 12.0
const SELECTED_TINT         := Color(1.6, 1.6, 0.55, 1.0)

# ─── State ────────────────────────────────────────────────────────────────────
var mode: int = Mode.NONE
var hidden_state: bool = false
var target_count: int = 0

# Discard mode
var to_discard_cards: Array = []   # CardData refs in the order they were picked
var to_discard_nodes: Array = []   # Card visual nodes (live in _bs.canvas)

# Search mode
var search_selected: Array = []    # CardData refs (deck picks)
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


# Discriminator used by the description box to choose its action button.
# Stays true even while hidden_state is on (the button is rendered as
# 버리기 but disabled until the player un-hides).
func is_discard_mode() -> bool:
	return mode == Mode.DISCARD


# Tighter gate for actually accepting a pick: discard mode, not hidden, and
# the to-discard list isn't already full.
func can_pick_for_discard() -> bool:
	return mode == Mode.DISCARD and not hidden_state \
			and to_discard_cards.size() < target_count


# ─── Entry points ────────────────────────────────────────────────────────────
func start_discard(n: int, on_complete: Callable, on_cancel: Callable) -> void:
	mode = Mode.DISCARD
	target_count = max(0, min(n, _bs.player_hand.size()))
	hidden_state = false
	to_discard_cards.clear()
	to_discard_nodes.clear()
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


func start_search(n: int, on_complete: Callable, on_cancel: Callable) -> void:
	mode = Mode.SEARCH
	target_count = max(0, min(n, _bs.player_deck.size()))
	hidden_state = false
	search_selected.clear()
	_on_complete = on_complete
	_on_cancel = on_cancel
	if target_count <= 0:
		_finish_with_picks([])
		return
	_build_full_dim()
	_build_search_grid()
	_build_buttons(false)
	_refresh_visibility()
	_update_confirm_button()


# ─── Player interactions ─────────────────────────────────────────────────────
# Called from CardPhaseManager when the desc-box "버리기" button is pressed on
# a hand card. The card is removed from the live hand and parked in the
# centered to-discard row until the player presses 확인 (enabled once
# exactly target_count cards have been picked).
func add_card_to_discard(node: Card) -> void:
	if not can_pick_for_discard():
		return
	if not _bs.player_card_nodes.has(node):
		return
	var cd: CardData = node.data
	_bs.player_card_nodes.erase(node)
	_bs.player_hand.erase(cd)
	to_discard_cards.append(cd)
	to_discard_nodes.append(node)
	# Once a card joins the to-discard fan it is no longer part of the live
	# hand and shouldn't react to clicks (no un-pick path while we wait for
	# the player to hit 확인). MOUSE_FILTER_IGNORE makes the centred fan
	# inert until _commit_discard tears it down.
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bs.card_phase.relayout_hand(_bs.player_card_nodes)
	_layout_to_discard_row()
	# No auto-commit on the Nth pick — the player explicitly confirms via the
	# 확인 button now. _update_confirm_button gates the button on
	# to_discard_cards.size() == target_count.
	_update_confirm_button()


# Toggles the highlight + selection state of a deck card in the search grid.
# Clamps to target_count selections at most.
func _toggle_search_pick(cd: CardData, node: Card) -> void:
	if mode != Mode.SEARCH or hidden_state:
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
	_teardown()
	_finish_with_picks(picks)


func _commit_search() -> void:
	if search_selected.size() != target_count:
		return
	var picks := search_selected.duplicate()
	_teardown()
	_finish_with_picks(picks)


func _finish_with_picks(picks: Array) -> void:
	var cb := _on_complete
	mode = Mode.NONE
	_on_complete = Callable()
	_on_cancel = Callable()
	if cb.is_valid():
		cb.call(picks)


func _on_cancel_pressed() -> void:
	var cb := _on_cancel
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
	_battle_dim.size = Vector2(1080.0, _bs.BS_HAND_CENTER.y)
	_bs.canvas.add_child(_battle_dim)
	_bs.canvas.move_child(_battle_dim, 0)


func _build_full_dim() -> void:
	# Search mode dims everything; the full-screen rect lives on the high-layer
	# overlay so it sits above the hand and HUD too.
	_full_dim = ColorRect.new()
	_full_dim.color = DIM_COLOR
	_full_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_full_dim.position = Vector2.ZERO
	_full_dim.size = Vector2(1080.0, 1920.0)
	_overlay_layer.add_child(_full_dim)


func _build_buttons(is_discard: bool) -> void:
	_btn_hide = _make_btn("숨김")
	_btn_hide.position = Vector2(BTN_SIDE_MARGIN, BTN_BOTTOM_Y)
	_btn_hide.pressed.connect(_on_hide_pressed)
	_overlay_layer.add_child(_btn_hide)

	# 확인 / 취소 hover at the top-right of the hand area so the player's
	# attention stays anchored where the cards are. _btn_top_y derives from
	# BS_HAND_CENTER.y so any future hand-row movement carries the buttons.
	var top_y: float = _bs.BS_HAND_CENTER.y - BTN_HAND_GAP - BTN_H
	var right_x: float = 1080.0 - BTN_SIDE_MARGIN - BTN_W

	if is_discard:
		# 버리기 cards are non-cancellable — once started, the player must
		# pick exactly target_count cards and press 확인. Only the 확인 button
		# (top-right of the hand area) and the 숨김 peek button are exposed.
		_btn_confirm = _make_btn("확인")
		_btn_confirm.position = Vector2(right_x, top_y)
		_btn_confirm.pressed.connect(_commit_discard)
		_btn_confirm.disabled = true
		_overlay_layer.add_child(_btn_confirm)
	else:
		_btn_cancel = _make_btn("찾기 취소")
		_btn_cancel.position = Vector2(right_x, top_y)
		_btn_cancel.pressed.connect(_on_cancel_pressed)
		_overlay_layer.add_child(_btn_cancel)
		_btn_confirm = _make_btn("확인")
		_btn_confirm.position = Vector2(
				right_x - CONFIRM_BTN_GAP - BTN_W, top_y)
		_btn_confirm.pressed.connect(_commit_search)
		_btn_confirm.disabled = true
		_overlay_layer.add_child(_btn_confirm)


func _make_btn(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 22)
	b.size = Vector2(BTN_W, BTN_H)
	return b


func _build_search_grid() -> void:
	var deck: Array = _bs.player_deck
	if deck.is_empty():
		return
	var grid_w: float = 1080.0 - 2.0 * SEARCH_GRID_SIDE_PAD
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


func _attach_search_pick_overlay(node: Card, cd: CardData) -> void:
	# A flat, fully-transparent Button sized to the card. It absorbs clicks
	# (mouse_filter STOP by default on Button) so the underlying Card never
	# sees them.
	var hit := Button.new()
	hit.flat = true
	hit.size = Vector2(Card.CARD_W, Card.CARD_H)
	hit.position = Vector2.ZERO
	hit.modulate = Color(1, 1, 1, 0)
	hit.pressed.connect(func() -> void: _toggle_search_pick(cd, node))
	node.add_child(hit)


# Lays out the picked-for-discard cards in a horizontal fan that mirrors the
# hand row's spacing (so it visually reads as "a hand of cards being set
# aside").
func _layout_to_discard_row() -> void:
	var n: int = to_discard_nodes.size()
	if n == 0:
		return
	var slot_y: float = TO_DISCARD_CENTER_Y - Card.CARD_H * 0.5
	var hand_w: float = _bs.BS_HAND_WIDTH
	var visual_cx: float = 1080.0 * 0.5
	var ideal_total: float = float(n) * Card.CARD_W \
			+ float(max(n - 1, 0)) * _bs.BS_HAND_CARD_GAP
	var spacing: float = Card.CARD_W + _bs.BS_HAND_CARD_GAP
	if n > 1 and ideal_total > hand_w:
		spacing = (hand_w - Card.CARD_W) / float(n - 1)
	var first_x: float = visual_cx - float(n - 1) * spacing * 0.5 \
			- Card.CARD_W * 0.5
	for i in n:
		var node := to_discard_nodes[i] as Card
		var pos := Vector2(first_x + float(i) * spacing, slot_y)
		node.tween_to(pos, 0.0, Vector2.ONE,
				_bs.BS_HAND_SPRING_DURATION,
				_bs.BS_HAND_TWEEN_EASE, _bs.BS_HAND_TWEEN_TRANS)


# 숨김 hides the dim + selection display so the player can review the battle.
# In hidden state, picking is disabled (can_pick_for_discard returns false and
# the search grid is not visible) but the cancel / confirm / hide buttons all
# stay reachable so the player can resolve the overlay either way.
func _refresh_visibility() -> void:
	var show := not hidden_state
	if mode == Mode.DISCARD:
		if _battle_dim != null:
			_battle_dim.visible = show
		for node in to_discard_nodes:
			(node as Card).visible = show
	elif mode == Mode.SEARCH:
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
	if mode == Mode.DISCARD:
		_btn_confirm.disabled = to_discard_cards.size() != target_count
	else:
		_btn_confirm.disabled = search_selected.size() != target_count


func _teardown() -> void:
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
