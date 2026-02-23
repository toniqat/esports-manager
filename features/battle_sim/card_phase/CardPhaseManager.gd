class_name CardPhaseManager
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim


# ─── Deck setup ───────────────────────────────────────────────────────────────
func build_starter_decks() -> void:
	_bs._player_deck.clear(); _bs._ai_deck.clear()
	_bs._player_discard.clear(); _bs._ai_discard.clear()
	var pool := [
		make_card("Strike",     1, "Deal 20 dmg to random enemy",    "damage",       20),
		make_card("Mend",       1, "Heal 25 HP to lowest-HP ally",    "heal",         25),
		make_card("Reinforce",  2, "+15 minions to random ally lane", "minions",      15),
		make_card("Focus Fire", 2, "Deal 35 dmg to lowest-HP enemy", "focus_damage", 35),
		make_card("Rally",      3, "All ally pilots +5 ATK this turn","buff_atk",      5),
		make_card("Overcharge", 4, "All ally pilots +10 ATK",         "buff_atk",     10),
	]
	for i in range(10):
		_bs._player_deck.append(make_card_copy(pool[i % pool.size()] as CardData))
		_bs._ai_deck.append(make_card_copy(pool[i % pool.size()] as CardData))
	_bs._player_deck.shuffle()
	_bs._ai_deck.shuffle()


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
	_bs._sim_core.simulate_turn()
	if _bs.game_over:
		return
	_bs._player_cost += _bs.COST_RECOVERY
	_bs._ai_cost     += _bs.COST_RECOVERY
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

	if _bs._selected_card != null:
		deselect_card(_bs._selected_card)

	_bs.game_phase = GameEnums.BattlePhase.BATTLE
	_bs._renderer.queue_redraw()
	_bs._hud.update_hud()


# ─── Card draw ────────────────────────────────────────────────────────────────
func draw_card(is_player: bool) -> CardData:
	var deck:    Array = _bs._player_deck    if is_player else _bs._ai_deck
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
	_bs._canvas.add_child(node)
	node.setup(cd, true, true)
	node.card_clicked.connect(on_player_card_clicked)
	_bs._player_card_nodes.append(node)
	relayout_hand(_bs._player_card_nodes, _bs.BS_HAND_CENTER, false)
	highlight_affordable_cards()


func spawn_ai_card_node() -> void:
	var node := _bs.CARD_SCENE.instantiate() as Card
	node.pivot_offset = Vector2(80.0, 110.0)
	node.scale = Vector2(0.65, 0.65)
	_bs._canvas.add_child(node)
	node.setup(null, false, false)
	_bs._ai_card_nodes.append(node)
	relayout_hand(_bs._ai_card_nodes, _bs.BS_AI_HAND_CENTER, true)


func fan_slot(index: int, total: int, center: Vector2, flip: bool) -> Dictionary:
	if total <= 1:
		return {"position": center, "rotation": 0.0}
	var t        := float(index) / float(total - 1)
	var half_deg := minf(_bs.BS_FAN_HALF_DEG, float(total - 1) * _bs.BS_FAN_CARD_DEG * 0.5)
	var angle    := deg_to_rad(lerp(-half_deg, half_deg, t))
	var arc_dir  := -1.0 if flip else 1.0
	var arc_center := center + Vector2(0.0, arc_dir * _bs.BS_FAN_RADIUS)
	var pos := arc_center + Vector2(sin(angle), -cos(angle) * arc_dir) * _bs.BS_FAN_RADIUS
	var rot := -angle if flip else angle
	return {"position": pos, "rotation": rot}


func relayout_hand(nodes: Array, center: Vector2, flip: bool, skip = null) -> void:
	for i in nodes.size():
		if nodes[i] == _bs._selected_card or nodes[i] == skip:
			continue
		var slot := fan_slot(i, nodes.size(), center, flip)
		(nodes[i] as Card).global_position = slot["position"] as Vector2
		(nodes[i] as Card).rotation        = slot["rotation"] as float
		(nodes[i] as Card).store_base_y()


func highlight_affordable_cards() -> void:
	for node in _bs._player_card_nodes:
		var c := node as Card
		if c.data != null and c.face_up:
			c.set_affordable(c.data.cost <= _bs._player_cost)


# ─── Card interaction ─────────────────────────────────────────────────────────
func on_player_card_clicked(card: Card) -> void:
	if _bs.game_phase != GameEnums.BattlePhase.CARD_PHASE:
		return
	if _bs._selected_card == card:
		play_player_card(card)
	else:
		if _bs._selected_card != null:
			deselect_card(_bs._selected_card)
		select_card(card)


func select_card(card: Card) -> void:
	_bs._selected_card = card
	card.is_selected   = true
	var tw := card.create_tween()
	tw.tween_property(card, "global_position", _bs.BS_SELECTED_POS, 0.2).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(card, "rotation", 0.0, 0.2)
	tw.parallel().tween_property(card, "scale", _bs.BS_SELECTED_SCALE, 0.2)


func deselect_card(card: Card) -> void:
	card.is_selected   = false
	_bs._selected_card = null
	var idx := _bs._player_card_nodes.find(card)
	if idx == -1:
		return
	var slot := fan_slot(idx, _bs._player_card_nodes.size(), _bs.BS_HAND_CENTER, false)
	var tw := card.create_tween()
	tw.tween_property(card, "global_position", slot["position"] as Vector2, 0.2).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(card, "rotation", slot["rotation"] as float, 0.2)
	tw.parallel().tween_property(card, "scale", Vector2(1.0, 1.0), 0.2)
	tw.tween_callback(card.store_base_y)


func play_player_card(card: Card) -> void:
	if card.data == null:
		return
	if _bs._player_cost < card.data.cost:
		deselect_card(card)
		return
	var cd := card.data
	_bs._player_cost -= cd.cost
	_bs._player_hand.erase(cd)
	_bs._player_discard.append(cd)
	_bs._selected_card = null
	card.is_selected   = false
	_bs._player_card_nodes.erase(card)
	card.queue_free()
	var log_msg := apply_card_effect(cd, true)
	if log_msg != "":
		_bs.last_log = log_msg
	relayout_hand(_bs._player_card_nodes, _bs.BS_HAND_CENTER, false)
	highlight_affordable_cards()
	_bs._hud.update_hud()
	_bs._renderer.queue_redraw()


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
