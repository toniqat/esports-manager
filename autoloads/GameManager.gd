extends Node

# ── Battle Sim State ──────────────────────────────────────────────────────────
var battle_phase: int  = GameEnums.BattlePhase.GAMBIT
var battle_turn: int   = 0
var player_hq_hp: int  = 500
var enemy_hq_hp: int   = 500
var battle_over: bool  = false

signal battle_phase_changed(new_phase: int)
signal battle_turn_advanced(n: int)

func set_battle_phase(p: int) -> void:
	battle_phase = p
	battle_phase_changed.emit(p)

func advance_battle_turn() -> void:
	battle_turn += 1
	battle_turn_advanced.emit(battle_turn)

func reset_battle_state() -> void:
	battle_phase = GameEnums.BattlePhase.GAMBIT
	battle_turn  = 0
	player_hq_hp = 500
	enemy_hq_hp  = 500
	battle_over  = false

# ── Card Draw State ───────────────────────────────────────────────────────────
signal phase_changed(new_phase: int)
signal card_drawn(is_player: bool, card_data: CardData)
signal card_played(is_player: bool, card_data: CardData)
signal mana_changed(player_mana: int, ai_mana: int, max_cost: int)
signal hand_updated(is_player: bool, hand: Array)
signal game_log(message: String)
signal ai_turn_finished()
signal card_overflow_discarded(is_player: bool, card_data: CardData)

const INITIATIVE_THRESHOLD := 7
const MAX_HAND_SIZE        := 7

var current_phase: int = GameEnums.Phase.DRAW
var draw_turn_player: bool = true

var player_deck: Array[CardData] = []
var ai_deck: Array[CardData] = []
var player_hand: Array[CardData] = []
var ai_hand: Array[CardData] = []
var player_discard: Array[CardData] = []
var ai_discard: Array[CardData] = []

var max_cost: int = 0
var player_mana: int = 0
var ai_mana: int = 0


func _ready() -> void:
	_build_decks()
	_shuffle_deck(player_deck)
	_shuffle_deck(ai_deck)


func _build_decks() -> void:
	var templates: Array = [
		["Strike",   1, "A basic attack."],
		["Guard",    2, "Raise your defenses."],
		["Surge",    3, "A burst of energy."],
		["Blitz",    4, "Fast aggressive play."],
		["Rally",    5, "Gather your strength."],
		["Overload", 6, "Overwhelming force."],
		["Gambit",   2, "A risky maneuver."],
		["Feint",    1, "A clever diversion."],
		["Crush",    4, "Raw power."],
		["Nexus",    7, "The ultimate play."],
	]
	for t in templates:
		player_deck.append(CardData.new(t[0], t[1], t[2]))
		ai_deck.append(CardData.new(t[0], t[1], t[2]))


func _shuffle_deck(deck: Array[CardData]) -> void:
	deck.shuffle()


# ── Draw Phase ────────────────────────────────────────────────────────────────

func start_draw_phase() -> void:
	current_phase = GameEnums.Phase.DRAW
	draw_turn_player = true
	phase_changed.emit(current_phase)
	game_log.emit("── Draw phase begins ──")


func execute_draw() -> void:
	if current_phase != GameEnums.Phase.DRAW:
		return
	if draw_turn_player:
		_draw_for_player()
	else:
		_draw_for_ai()


func _draw_for_player() -> void:
	if player_deck.is_empty():
		_reshuffle(player_deck, player_discard)
	if player_deck.is_empty():
		return
	var card: CardData = player_deck.pop_back()
	if player_hand.size() >= MAX_HAND_SIZE:
		var oldest: CardData = player_hand[0]
		player_hand.remove_at(0)
		player_discard.append(oldest)
		card_overflow_discarded.emit(true, oldest)
		game_log.emit("Hand full! %s discarded." % oldest.card_name)
	player_hand.append(card)
	_increment_player_cost()
	card_drawn.emit(true, card)
	hand_updated.emit(true, player_hand.duplicate())
	game_log.emit("Player draws %s (cost %d)." % [card.card_name, card.cost])
	draw_turn_player = false
	_check_initiative()


func _draw_for_ai() -> void:
	if ai_deck.is_empty():
		_reshuffle(ai_deck, ai_discard)
	if ai_deck.is_empty():
		return
	var card: CardData = ai_deck.pop_back()
	if ai_hand.size() >= MAX_HAND_SIZE:
		var oldest: CardData = ai_hand[0]
		ai_hand.remove_at(0)
		ai_discard.append(oldest)
		card_overflow_discarded.emit(false, oldest)
	ai_hand.append(card)
	_increment_ai_cost()
	card_drawn.emit(false, card)
	hand_updated.emit(false, ai_hand.duplicate())
	game_log.emit("AI draws a card.")
	draw_turn_player = true
	_check_initiative()


func _increment_player_cost() -> void:
	player_mana += 1
	mana_changed.emit(player_mana, ai_mana, INITIATIVE_THRESHOLD)


func _increment_ai_cost() -> void:
	ai_mana += 1
	mana_changed.emit(player_mana, ai_mana, INITIATIVE_THRESHOLD)


func _reshuffle(deck: Array[CardData], discard: Array[CardData]) -> void:
	deck.append_array(discard)
	discard.clear()
	_shuffle_deck(deck)
	game_log.emit("Deck reshuffled from discard.")


func _check_initiative() -> void:
	if player_mana >= INITIATIVE_THRESHOLD:
		_start_player_action()
	elif ai_mana >= INITIATIVE_THRESHOLD:
		_start_ai_action()


# ── Action Phases ─────────────────────────────────────────────────────────────

func _start_player_action() -> void:
	max_cost = player_mana
	current_phase = GameEnums.Phase.PLAYER_ACTION
	phase_changed.emit(current_phase)
	mana_changed.emit(player_mana, ai_mana, max_cost)
	game_log.emit("Player's turn! CP: %d" % player_mana)


func _start_ai_action() -> void:
	max_cost = ai_mana
	current_phase = GameEnums.Phase.AI_ACTION
	phase_changed.emit(current_phase)
	mana_changed.emit(player_mana, ai_mana, max_cost)
	game_log.emit("AI's turn! CP: %d" % ai_mana)


func player_play_card(card: CardData) -> bool:
	if current_phase != GameEnums.Phase.PLAYER_ACTION:
		return false
	if player_mana < card.cost:
		return false
	if not card in player_hand:
		return false
	player_hand.erase(card)
	player_discard.append(card)
	player_mana -= card.cost
	mana_changed.emit(player_mana, ai_mana, max_cost)
	card_played.emit(true, card)
	hand_updated.emit(true, player_hand.duplicate())
	game_log.emit("Player plays %s  [-%d mana → %d left]" % [card.card_name, card.cost, player_mana])
	return true


func ai_play_card() -> CardData:
	var affordable: Array[CardData] = ai_hand.filter(func(c): return c.cost <= ai_mana)
	if affordable.is_empty():
		return null
	var card: CardData = affordable[randi() % affordable.size()]
	ai_hand.erase(card)
	ai_discard.append(card)
	ai_mana -= card.cost
	mana_changed.emit(player_mana, ai_mana, max_cost)
	card_played.emit(false, card)
	hand_updated.emit(false, ai_hand.duplicate())
	game_log.emit("AI plays %s  [-%d mana → %d left]" % [card.card_name, card.cost, ai_mana])
	return card


func end_player_turn() -> void:
	if current_phase != GameEnums.Phase.PLAYER_ACTION:
		return
	if player_mana >= max_cost:
		game_log.emit("Must spend at least 1 mana before ending turn.")
		return
	game_log.emit("Player ends turn.")
	start_draw_phase()


func end_ai_turn() -> void:
	if current_phase != GameEnums.Phase.AI_ACTION:
		return
	game_log.emit("AI ends turn.")
	ai_turn_finished.emit()
	start_draw_phase()
