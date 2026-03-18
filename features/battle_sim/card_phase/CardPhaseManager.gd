class_name CardPhaseManager
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim

# ─── Local constants ───────────────────────────────────────────────────────────
## Hover scale — kept here as it is purely visual, not a layout tweak.
const HOVER_SCALE_VEC := Vector2(1.35, 1.35)

# ─── Drop-zone constant ────────────────────────────────────────────────────────
# Cards dropped above this Y are treated as "played on field"; below = return to hand.
const HAND_ZONE_Y := 1400.0

# ─── Drag state ───────────────────────────────────────────────────────────────
# Original hand index of the card being dragged, so it returns to the same slot.
var _dragged_card_original_idx: int = -1


# ─── Deck setup ───────────────────────────────────────────────────────────────
func build_starter_decks() -> void:
	_bs.player_deck.clear(); _bs.ai_deck.clear()
	_bs._player_discard.clear(); _bs._ai_discard.clear()
	var pool := _build_pool_from_db()
	for i in range(10):
		_bs.player_deck.append(make_card_copy(pool[i % pool.size()] as CardData))
		_bs.ai_deck.append(make_card_copy(pool[i % pool.size()] as CardData))
	_bs.player_deck.shuffle()
	_bs.ai_deck.shuffle()


func _build_pool_from_db() -> Array:
	var gm: Node = _bs.gm
	if gm != null and not gm.card_pool_bs.is_empty():
		var pool: Array = []
		for card_def in gm.card_pool_bs:
			pool.append(make_card(
				card_def["name"],
				card_def["cost"],
				"",
				card_def["effect_type"],
				card_def["value"],
			))
		return pool
	# Fallback: hardcoded pool
	return [
		make_card("Strike",     1, "Deal 20 dmg to random enemy",    "damage",       20),
		make_card("Mend",       1, "Heal 25 HP to lowest-HP ally",    "heal",         25),
		make_card("Reinforce",  2, "+15 minions to random ally lane", "minions",      15),
		make_card("Focus Fire", 2, "Deal 35 dmg to lowest-HP enemy", "focus_damage", 35),
		make_card("Rally",      3, "All ally pilots +5 ATK this turn","buff_atk",      5),
		make_card("Overcharge", 4, "All ally pilots +10 ATK",         "buff_atk",     10),
	]


func make_card(p_name: String, p_cost: int, p_desc: String,
		p_effect: String, p_value: int) -> CardData:
	var cd := CardData.new(p_name, p_cost, p_desc)
	cd.effect_type  = p_effect
	cd.effect_value = p_value
	return cd


func make_card_copy(src: CardData) -> CardData:
	return make_card(src.card_name, src.cost, src.description,
			src.effect_type, src.effect_value)


# ─── Turn flow ────────────────────────────────────────────────────────────────
func do_battle_turn() -> void:
	if _bs.game_over or _bs.game_phase != GameEnums.BattlePhase.BATTLE:
		return
	_bs.sim_core.simulate_turn()
	if _bs.game_over:
		return
	_bs._cost_counter += 1
	if _bs._cost_counter >= _bs.COST_RECOVERY_INTERVAL:
		_bs._cost_counter = 0
		_bs._player_cost += _bs.COST_RECOVERY
		_bs._ai_cost     += _bs.COST_RECOVERY
	_bs._draw_counter += 1
	if _bs._draw_counter >= _bs.CARD_DRAW_INTERVAL:
		_bs._draw_counter = 0
		if _bs._player_hand.size() < _bs.MAX_HAND_SIZE:
			var drawn := draw_card(true)
			if drawn != null:
				spawn_card_node(drawn)
		if _bs._ai_hand.size() < _bs.MAX_HAND_SIZE:
			var ai_drawn := draw_card(false)
			if ai_drawn != null:
				spawn_ai_card_node()
	if _bs._player_cost >= _bs.PHASE_THRESHOLD:
		start_card_phase()
	else:
		_bs._renderer.queue_redraw()
		_bs._hud.update_hud()


func start_card_phase() -> void:
	_bs.game_phase = GameEnums.BattlePhase.CARD_PHASE
	highlight_affordable_cards()
	_bs._renderer.queue_redraw()
	_bs._hud.update_hud()


func end_card_phase() -> void:
	# AI mirrors phase: plays all affordable cards if it has >= PHASE_THRESHOLD cost
	if _bs._ai_cost >= _bs.PHASE_THRESHOLD:
		while not _bs._ai_hand.is_empty():
			var affordable: Array = []
			for cd in _bs._ai_hand:
				if (cd as CardData).cost <= _bs._ai_cost:
					affordable.append(cd)
			if affordable.is_empty():
				break
			var pick := affordable[randi() % affordable.size()] as CardData
			_bs._ai_cost -= pick.cost
			_bs._ai_hand.erase(pick)
			_bs._ai_discard.append(pick)
			var log_msg := apply_card_effect(pick, false)
			if log_msg != "":
				_bs.last_log = log_msg
			if not _bs._ai_card_nodes.is_empty():
				var n = _bs._ai_card_nodes.pop_back()
				if is_instance_valid(n):
					(n as Card).queue_free()

	_bs.game_phase = GameEnums.BattlePhase.BATTLE
	_bs._renderer.queue_redraw()
	_bs._hud.update_hud()


# ─── Card draw ────────────────────────────────────────────────────────────────
func draw_card(is_player: bool) -> CardData:
	var deck:    Array = _bs.player_deck    if is_player else _bs.ai_deck
	var discard: Array = _bs._player_discard if is_player else _bs._ai_discard
	var hand:    Array = _bs._player_hand    if is_player else _bs._ai_hand
	if deck.is_empty():
		if discard.is_empty():
			return null
		deck.append_array(discard)
		discard.clear()
		deck.shuffle()
	var card := deck.pop_back() as CardData
	hand.append(card)
	return card


# ─── Card node helpers ────────────────────────────────────────────────────────
func spawn_card_node(cd: CardData) -> void:
	var node := _bs.CARD_SCENE.instantiate() as Card
	node.pivot_offset = Vector2(80.0, 110.0)
	node.drag_enabled = true
	_bs.canvas.add_child(node)
	node.global_position = _bs.BS_HAND_CENTER  # start at hand center for spring-in
	node.setup(cd, true, true)
	node.card_hovered.connect(on_card_hovered)
	node.card_unhovered.connect(on_card_unhovered)
	node.card_drag_started.connect(on_card_drag_started)
	node.card_dropped.connect(on_card_dropped)
	_bs._player_card_nodes.append(node)
	relayout_hand(_bs._player_card_nodes, _bs.BS_HAND_CENTER, false)
	highlight_affordable_cards()


func spawn_ai_card_node() -> void:
	var node := _bs.CARD_SCENE.instantiate() as Card
	node.pivot_offset = Vector2(80.0, 110.0)
	node.scale = Vector2(0.65, 0.65)
	_bs.canvas.add_child(node)
	node.setup(null, false, false)
	_bs._ai_card_nodes.append(node)
	relayout_hand(_bs._ai_card_nodes, _bs.BS_AI_HAND_CENTER, true)


## Compute the position and rotation for card at `index` within a hand of `total` cards.
## `card_deg` overrides BS_FAN_CARD_DEG when >= 0 (used for hover-tightened spacing).
func fan_slot(index: int, total: int, center: Vector2, flip: bool,
		card_deg: float = -1.0) -> Dictionary:
	if total <= 1:
		return {"position": center, "rotation": 0.0}
	var deg      := card_deg if card_deg >= 0.0 else _bs.BS_FAN_CARD_DEG
	var t        := float(index) / float(total - 1)
	var half_deg := minf(_bs.BS_FAN_HALF_DEG, float(total - 1) * deg * 0.5)
	var angle    := deg_to_rad(lerp(-half_deg, half_deg, t))
	var arc_dir  := -1.0 if flip else 1.0
	var arc_center := center + Vector2(0.0, arc_dir * _bs.BS_FAN_RADIUS)
	var pos := arc_center + Vector2(sin(angle), -cos(angle) * arc_dir) * _bs.BS_FAN_RADIUS
	var rot := -angle if flip else angle
	return {"position": pos, "rotation": rot}


## Animate all hand cards to their fan slot positions with a spring ease.
## After tweening, restores the canonical scene-tree draw order (newest card on top).
func relayout_hand(nodes: Array, center: Vector2, flip: bool, skip = null) -> void:
	var total := nodes.size()
	for i in total:
		var node := nodes[i] as Card
		if node == skip:
			continue
		var slot := fan_slot(i, total, center, flip)
		node.tween_to(slot["position"] as Vector2, slot["rotation"] as float,
				Vector2.ONE, _bs.BS_HAND_SPRING_DURATION,
				_bs.BS_HAND_TWEEN_EASE, _bs.BS_HAND_TWEEN_TRANS)
		node.store_base_y()
	if nodes == _bs._player_card_nodes:
		_reorder_hand_nodes()


## Reorder player card nodes in the scene tree so that draw order matches hand order.
## Index 0 (oldest) is lowest; last index (newest) draws on top of all others.
func _reorder_hand_nodes() -> void:
	for node in _bs._player_card_nodes:
		# move_child to last puts each successive card on top of the previous.
		var card := node as Card
		card.get_parent().move_child(card, card.get_parent().get_child_count() - 1)


func highlight_affordable_cards() -> void:
	for node in _bs._player_card_nodes:
		var c := node as Card
		if c.data != null and c.face_up:
			c.set_affordable(c.data.cost <= _bs._player_cost)


# ─── Hover interaction ────────────────────────────────────────────────────────

func on_card_hovered(card: Card) -> void:
	var idx := _bs._player_card_nodes.find(card)
	if idx == -1:
		return
	var total := _bs._player_card_nodes.size()

	# Hovered card: anchor at its NORMAL slot X — hover never shifts horizontally.
	var h_slot    := fan_slot(idx, total, _bs.BS_HAND_CENTER, false)
	var hovered_x := (h_slot["position"] as Vector2).x

	# Fixed hover Y: all cards reach the same screen height when hovered.
	var hover_y := _bs.BS_HAND_CENTER.y - _bs.BS_HOVER_LIFT

	# Secondary gap used by every non-adjacent card.
	var secondary_gap := _bs.PRIMARY_HOVER_SPACING * _bs.SECONDARY_SPACING_RATIO

	for i in total:
		var node := _bs._player_card_nodes[i] as Card
		if node == card:
			# Hovered card: fixed Y, rotation flattened, scaled up.
			node.tween_to(Vector2(hovered_x, hover_y), 0.0,
					HOVER_SCALE_VEC, _bs.BS_HOVER_SPRING_DURATION,
					_bs.BS_HAND_TWEEN_EASE, _bs.BS_HAND_TWEEN_TRANS)
		else:
			# Non-hovered: keep arc Y and tilt; only X is redistributed.
			# Immediate neighbour (dist=1) shifts by PRIMARY_HOVER_SPACING.
			# Every further card shifts by PRIMARY_HOVER_SPACING + (dist-1)*secondary_gap.
			var slot := fan_slot(i, total, _bs.BS_HAND_CENTER, false)
			var target_x: float
			if i < idx:
				var dist := idx - i
				target_x = hovered_x - _bs.PRIMARY_HOVER_SPACING \
						- (dist - 1) * secondary_gap
			else:
				var dist := i - idx
				target_x = hovered_x + _bs.PRIMARY_HOVER_SPACING \
						+ (dist - 1) * secondary_gap
			node.tween_to(Vector2(target_x, (slot["position"] as Vector2).y),
					slot["rotation"] as float, Vector2.ONE,
					_bs.BS_HOVER_SPRING_DURATION,
					_bs.BS_HAND_TWEEN_EASE, _bs.BS_HAND_TWEEN_TRANS)

	# Bring hovered card on top of all siblings.
	card.get_parent().move_child(card, card.get_parent().get_child_count() - 1)


func on_card_unhovered(card: Card) -> void:
	var idx := _bs._player_card_nodes.find(card)
	if idx == -1:
		return
	var total := _bs._player_card_nodes.size()

	# Reflow ALL cards back to normal spacing.
	for i in total:
		var node := _bs._player_card_nodes[i] as Card
		var slot := fan_slot(i, total, _bs.BS_HAND_CENTER, false)
		node.tween_to(slot["position"] as Vector2, slot["rotation"] as float,
				Vector2.ONE, _bs.BS_HAND_SPRING_DURATION,
				_bs.BS_HAND_TWEEN_EASE, _bs.BS_HAND_TWEEN_TRANS)
		node.store_base_y()

	# Restore canonical draw order (newest = last child = on top).
	_reorder_hand_nodes()


# ─── Drag interaction ─────────────────────────────────────────────────────────

func on_card_drag_started(card: Card) -> void:
	var idx := _bs._player_card_nodes.find(card)
	if idx == -1:
		return
	# Remember original slot so the card returns to the same position.
	_dragged_card_original_idx = idx
	_bs._player_card_nodes.erase(card)
	# Reflow remaining cards (they close the gap left by the dragged card).
	relayout_hand(_bs._player_card_nodes, _bs.BS_HAND_CENTER, false)
	# Bring dragged card in front of all siblings.
	card.get_parent().move_child(card, card.get_parent().get_child_count() - 1)


func on_card_dropped(card: Card, drop_pos: Vector2) -> void:
	var on_field      := drop_pos.y < HAND_ZONE_Y
	var in_card_phase := _bs.game_phase == GameEnums.BattlePhase.CARD_PHASE
	var affordable    := card.data != null and _bs._player_cost >= card.data.cost

	if on_field and in_card_phase and affordable:
		_play_card_direct(card)
	else:
		_return_card_to_hand(card)


func _play_card_direct(card: Card) -> void:
	var cd := card.data
	_bs._player_cost -= cd.cost
	_bs._player_hand.erase(cd)
	_bs._player_discard.append(cd)
	card.queue_free()
	var log_msg := apply_card_effect(cd, true)
	if log_msg != "":
		_bs.last_log = log_msg
	relayout_hand(_bs._player_card_nodes, _bs.BS_HAND_CENTER, false)
	highlight_affordable_cards()
	_bs._hud.update_hud()
	_bs._renderer.queue_redraw()


func _return_card_to_hand(card: Card) -> void:
	# Re-insert at the original slot index to preserve hand order.
	var insert_idx := clampi(_dragged_card_original_idx, 0, _bs._player_card_nodes.size())
	_bs._player_card_nodes.insert(insert_idx, card)
	relayout_hand(_bs._player_card_nodes, _bs.BS_HAND_CENTER, false)
	highlight_affordable_cards()


# ─── Card effects ─────────────────────────────────────────────────────────────
func apply_card_effect(cd: CardData, is_player: bool) -> String:
	var ally_team  := 0 if is_player else 1
	var enemy_team := 1 - ally_team
	var who        := "Player" if is_player else "AI"
	match cd.effect_type:
		"damage":
			var targets: Array = []
			for r in _bs.pilots:
				var p := r as PilotData
				if p.alive and p.team == enemy_team:
					targets.append(p)
			if targets.is_empty():
				return "%s: %s (no targets)" % [who, cd.card_name]
			var t := targets[randi() % targets.size()] as PilotData
			t.hp = max(0, t.hp - cd.effect_value)
			if t.hp <= 0:
				t.alive = false; t.respawn_timer = _bs.RESPAWN_TURNS
			return "%s: %s → %s -%d HP" % [who, cd.card_name, _bs.pilot_label(t), cd.effect_value]
		"focus_damage":
			var best: PilotData = null
			for r in _bs.pilots:
				var p := r as PilotData
				if p.alive and p.team == enemy_team:
					if best == null or p.hp < best.hp:
						best = p
			if best == null:
				return "%s: %s (no targets)" % [who, cd.card_name]
			best.hp = max(0, best.hp - cd.effect_value)
			if best.hp <= 0:
				best.alive = false; best.respawn_timer = _bs.RESPAWN_TURNS
			return "%s: %s → %s -%d HP" % [who, cd.card_name, _bs.pilot_label(best), cd.effect_value]
		"heal":
			var best: PilotData = null
			for r in _bs.pilots:
				var p := r as PilotData
				if p.alive and p.team == ally_team:
					if best == null or p.hp < best.hp:
						best = p
			if best == null:
				return "%s: %s (no targets)" % [who, cd.card_name]
			best.hp = min(best.hp + cd.effect_value, best.max_hp)
			return "%s: %s → %s +%d HP" % [who, cd.card_name, _bs.pilot_label(best), cd.effect_value]
		"buff_atk":
			if is_player:
				_bs._pending_atk_buff_p  += cd.effect_value
			else:
				_bs._pending_atk_buff_ai += cd.effect_value
			return "%s: %s → all allies +%d ATK this turn" % [who, cd.card_name, cd.effect_value]
		"minions":
			var lane_idx := randi() % 3
			var m        := MinionData.new()
			m.team       = ally_team; m.lane = lane_idx; m.count = cd.effect_value
			var path: Array = _bs.LANE_PATHS_TEAM0[lane_idx] if ally_team == 0 \
					else _bs.LANE_PATHS_TEAM1[lane_idx]
			m.grid_pos     = path[0] as Vector2i
			m.waypoint_idx = 0; m.alive = true
			_bs._minions.append(m)
			return "%s: %s → +%d %s minions" % [who, cd.card_name, cd.effect_value, _bs.LANE_NAMES[lane_idx]]
	return ""
