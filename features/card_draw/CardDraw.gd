extends Node2D

# ── Constants ─────────────────────────────────────────────────────────────────
const CARD_SCENE := preload("res://scenes/Card.tscn")

const PLAYER_HAND_CENTER := Vector2(540, 1780)
const AI_HAND_CENTER     := Vector2(540, 140)
const PLAYER_DECK_POS    := Vector2(940, 1680)
const AI_DECK_POS        := Vector2(140, 240)

const FAN_RADIUS         := 900.0
const FAN_HALF_ANGLE_DEG := 24.0
const FAN_CARD_ANGLE_DEG := 5.0   # angular gap between adjacent cards (degrees)
const AI_PLAY_DELAY      := 1.0
const SELECTED_CARD_POS  := Vector2(540, 1520)
const SELECTED_CARD_SCALE := Vector2(1.5, 1.5)

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var player_hand_root : Node2D = $PlayerHandRoot
@onready var ai_hand_root     : Node2D = $AIHandRoot
@onready var phase_label      : Label  = $HUD/PhaseLabel
@onready var mana_label       : Label  = $HUD/ManaLabel
@onready var end_turn_btn     : Button = $HUD/EndTurnButton
@onready var log_label        : Label  = $HUD/LogLabel
@onready var player_deck_lbl  : Label  = $PlayerDeckLabel
@onready var ai_deck_lbl      : Label  = $AIDeckLabel

# Runtime reference to the autoload singleton
@onready var _gm: Node = get_node("/root/GameManager")

# ── State ─────────────────────────────────────────────────────────────────────
var player_card_nodes : Array[Card] = []
var ai_card_nodes     : Array[Card] = []
var selected_card     : Card = null


func _ready() -> void:
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	end_turn_btn.visible = false

	_gm.phase_changed.connect(_on_phase_changed)
	_gm.card_drawn.connect(_on_card_drawn)
	_gm.card_played.connect(_on_card_played)
	_gm.card_overflow_discarded.connect(_on_card_overflow_discarded)
	_gm.mana_changed.connect(_on_mana_changed)
	_gm.game_log.connect(_on_game_log)
	_gm.ai_turn_finished.connect(_on_ai_turn_finished)

	_update_deck_labels()
	_update_mana_label(0, 0, 0)

	await get_tree().create_timer(0.5).timeout
	_gm.start_draw_phase()


# ── Draw Phase ────────────────────────────────────────────────────────────────

func _schedule_next_draw() -> void:
	if _gm.current_phase != GameEnums.Phase.DRAW:
		return
	_do_draw()


func _do_draw() -> void:
	if _gm.current_phase != GameEnums.Phase.DRAW:
		return
	_gm.execute_draw()


func _on_card_drawn(is_player: bool, card_data: CardData) -> void:
	var card_node := CARD_SCENE.instantiate() as Card
	card_node.pivot_offset = Vector2(80, 110)

	if is_player:
		player_hand_root.add_child(card_node)
		card_node.setup(card_data, true, true)
		card_node.card_clicked.connect(_on_player_card_clicked)
		card_node.global_position = PLAYER_DECK_POS
		player_card_nodes.append(card_node)
		var target := _fan_position(player_card_nodes.size() - 1, player_card_nodes.size(), PLAYER_HAND_CENTER, false)
		card_node.rotation = target.rotation
		_relayout_hand(player_card_nodes, PLAYER_HAND_CENTER, false, card_node)
		card_node.animate_to(target.position, 0.45, func():
			card_node.store_base_y()
			_schedule_next_draw()
		)
	else:
		ai_hand_root.add_child(card_node)
		card_node.setup(card_data, false)
		card_node.global_position = AI_DECK_POS
		ai_card_nodes.append(card_node)
		var target := _fan_position(ai_card_nodes.size() - 1, ai_card_nodes.size(), AI_HAND_CENTER, true)
		card_node.rotation = target.rotation
		_relayout_hand(ai_card_nodes, AI_HAND_CENTER, true, card_node)
		card_node.animate_to(target.position, 0.45, func():
			card_node.store_base_y()
			_schedule_next_draw()
		)

	_update_deck_labels()


# ── Fan Layout ────────────────────────────────────────────────────────────────

class FanSlot:
	var position: Vector2
	var rotation: float


func _fan_position(index: int, total: int, center: Vector2, flip: bool) -> FanSlot:
	var slot := FanSlot.new()
	if total <= 1:
		slot.position = center
		slot.rotation = 0.0
		return slot
	var t        := float(index) / float(total - 1)
	# Clamp spread so a small hand stays tightly grouped
	var half_deg := minf(FAN_HALF_ANGLE_DEG, (total - 1) * FAN_CARD_ANGLE_DEG * 0.5)
	var angle    := deg_to_rad(lerp(-half_deg, half_deg, t))
	# arc_dir controls which side the arc center sits on:
	#   Player   (bottom): arc_center below hand → fan bows downward, cards peek up
	#   Opponent (top):    arc_center above hand → fan bows upward, true vertical mirror
	var arc_dir    := -1.0 if flip else 1.0
	var arc_center := center + Vector2(0, arc_dir * FAN_RADIUS)
	slot.position  = arc_center + Vector2(sin(angle), -cos(angle) * arc_dir) * FAN_RADIUS
	# Negate rotation for opponent so tilts are a vertical mirror:
	#   Player left card: CCW tilt  →  Opponent left card: CW tilt
	#   Player right card: CW tilt  →  Opponent right card: CCW tilt
	slot.rotation  = -angle if flip else angle
	return slot


func _relayout_hand(nodes: Array[Card], center: Vector2, flip: bool, skip: Card = null) -> void:
	for i in nodes.size():
		if nodes[i] == selected_card or nodes[i] == skip:
			continue
		var slot := _fan_position(i, nodes.size(), center, flip)
		var tw := nodes[i].create_tween()
		tw.tween_property(nodes[i], "global_position", slot.position, 0.2).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(nodes[i], "rotation", slot.rotation, 0.2)
		nodes[i].store_base_y()


# ── Action Phase ──────────────────────────────────────────────────────────────

func _on_phase_changed(new_phase: int) -> void:
	match new_phase:
		GameEnums.Phase.DRAW:
			phase_label.text = "Draw Phase"
			end_turn_btn.visible = false
			_schedule_next_draw()
		GameEnums.Phase.PLAYER_ACTION:
			phase_label.text = "Your Turn"
			end_turn_btn.visible = true
			end_turn_btn.disabled = (_gm.player_mana >= _gm.max_cost)
			_highlight_affordable_cards()
		GameEnums.Phase.AI_ACTION:
			phase_label.text = "AI Turn"
			end_turn_btn.visible = false
			if selected_card != null:
				_deselect_card_to_fan(selected_card)
			_run_ai_turn()


func _highlight_affordable_cards() -> void:
	for node in player_card_nodes:
		if node.data != null and node.face_up:
			node.set_affordable(node.data.cost <= _gm.player_mana)


func _on_player_card_clicked(card_node: Card) -> void:
	if _gm.current_phase != GameEnums.Phase.PLAYER_ACTION:
		return
	if card_node == selected_card:
		# Second tap on selected card → play it
		selected_card = null
		card_node.is_selected = false
		_play_card(card_node)
	else:
		# Select this card (deselect previous if any)
		if selected_card != null:
			_deselect_card_to_fan(selected_card)
		_select_card(card_node)


func _select_card(card_node: Card) -> void:
	selected_card = card_node
	card_node.is_selected = true
	var tw := card_node.create_tween()
	tw.tween_property(card_node, "global_position", SELECTED_CARD_POS, 0.2).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(card_node, "rotation", 0.0, 0.2)
	tw.parallel().tween_property(card_node, "scale", SELECTED_CARD_SCALE, 0.2)


func _deselect_card_to_fan(card_node: Card) -> void:
	card_node.is_selected = false
	selected_card = null
	var idx := player_card_nodes.find(card_node)
	if idx == -1:
		return
	var slot := _fan_position(idx, player_card_nodes.size(), PLAYER_HAND_CENTER, false)
	var tw := card_node.create_tween()
	tw.tween_property(card_node, "global_position", slot.position, 0.2).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(card_node, "rotation", slot.rotation, 0.2)
	tw.parallel().tween_property(card_node, "scale", Vector2(1.0, 1.0), 0.2)
	tw.tween_callback(card_node.store_base_y)


func _play_card(card_node: Card) -> void:
	if not _gm.player_play_card(card_node.data):
		# Not affordable — send it back to the fan
		_deselect_card_to_fan(card_node)
		return
	player_card_nodes.erase(card_node)
	card_node.queue_free()
	_relayout_hand(player_card_nodes, PLAYER_HAND_CENTER, false)
	_highlight_affordable_cards()


func _on_end_turn_pressed() -> void:
	if selected_card != null:
		_deselect_card_to_fan(selected_card)
	_gm.end_player_turn()


# ── AI Turn ───────────────────────────────────────────────────────────────────

func _run_ai_turn() -> void:
	await get_tree().create_timer(AI_PLAY_DELAY).timeout
	_ai_play_next()


func _ai_play_next() -> void:
	if _gm.current_phase != GameEnums.Phase.AI_ACTION:
		return
	var played: CardData = _gm.ai_play_card()
	if played != null:
		for node in ai_card_nodes:
			if node.data == played:
				ai_card_nodes.erase(node)
				node.queue_free()
				_relayout_hand(ai_card_nodes, AI_HAND_CENTER, true)
				break
		await get_tree().create_timer(AI_PLAY_DELAY).timeout
		_ai_play_next()
	else:
		await get_tree().create_timer(0.5).timeout
		_gm.end_ai_turn()


func _on_ai_turn_finished() -> void:
	pass


func _on_card_played(_is_player: bool, _card_data: CardData) -> void:
	pass


func _on_card_overflow_discarded(is_player: bool, card_data: CardData) -> void:
	var nodes: Array[Card] = player_card_nodes if is_player else ai_card_nodes
	for i in nodes.size():
		if nodes[i].data == card_data:
			var node := nodes[i]
			nodes.remove_at(i)
			node.queue_free()
			break


# ── HUD ───────────────────────────────────────────────────────────────────────

func _on_mana_changed(p_mana: int, a_mana: int, m_cost: int) -> void:
	_update_mana_label(p_mana, a_mana, m_cost)
	if _gm.current_phase == GameEnums.Phase.PLAYER_ACTION:
		_highlight_affordable_cards()
		end_turn_btn.disabled = (p_mana >= m_cost)


func _update_mana_label(p_mana: int, a_mana: int, m_cost: int) -> void:
	mana_label.text = "CP: %d / %d  |  AI: %d / %d" % [p_mana, m_cost, a_mana, m_cost]


func _on_game_log(message: String) -> void:
	log_label.text = message


func _update_deck_labels() -> void:
	player_deck_lbl.text = "Deck: %d" % _gm.player_deck.size()
	ai_deck_lbl.text     = "Deck: %d" % _gm.ai_deck.size()
