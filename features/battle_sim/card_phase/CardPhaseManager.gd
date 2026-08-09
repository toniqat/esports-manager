class_name CardPhaseManager
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim

# Hand layout uses BS_HAND_WIDTH (inner) + BS_HAND_CARD_GAP (target gap) for
# adaptive spacing.

# ─── Click-to-select state ────────────────────────────────────────────────────
# When a card is clicked it pops up by Card.PRESS_LIFT, gets brought to the top
# of the scene tree, and a description box with a "카드 내기" button appears
# next to it. Other hand cards stay in their slots (gap remains where the
# selected card was). Clicking anywhere outside the card / box / button
# dismisses the box and returns the card to its slot.
var _selected_card: Card = null
var _description_box: Panel = null
var _play_button: Button = null
# Card currently under the cursor. Drives hover_push_offset (neighbours slide
# clear of the enlarged card) and the z-order raise in _reorder_hand_nodes.
var _hovered_card: Card = null
# Hover reflow bookkeeping. Reordering the hand re-evaluates mouse focus and
# makes the engine emit mouse_entered / mouse_exited *synchronously, from
# inside move_child* — so a reflow run straight out of a hover signal
# re-enters itself, fails its own move_child ("parent busy setting up
# children") and leaves half-applied tweens behind. Reflows are therefore
# deferred to idle and coalesced: `_hand_reflow_queued` collapses a whole
# enter/exit storm into one pass, `_reflow_focus` makes a pass that wouldn't
# change anything a true no-op, and `_reordering` stops re-entry outright.
var _hand_reflow_queued: bool = false
# Which card the layout currently on screen was computed around (see
# _push_focus_card) — NOT necessarily the hovered one, since a selection
# outranks the cursor.
var _reflow_focus: Card = null
var _reordering: bool = false

# Mouse picking for the hand is owned by one transparent Control over the whole
# row rather than by the cards themselves — see _apply_hit_bands for why.
# `_hit_bands[i]` is the viewport-space [left, right] strip card `i` answers for.
var _hand_hit_layer: Control = null
var _hit_bands: Array[Vector2] = []

# Description box layout (next to the selected card).
const DESC_BOX_W   := 320.0
const DESC_BOX_H   := 220.0
const DESC_BOX_GAP := 12.0

# ─── Reshuffle count tween state ─────────────────────────────────────────────
# When draw_card empties the deck and reshuffles the discard back in, the two
# count labels animate from old→new instead of snapping. The tween mutates the
# float fields below; _process_reshuffle_tween() is wired in via a Tween node.
var _deck_displayed:    float = 0.0
var _discard_displayed: float = 0.0
var _reshuffle_tween:   Tween = null

# ─── Async effect state ──────────────────────────────────────────────────────
# When the player plays a card whose effect chain contains 버리기:N or 찾기:N,
# the chain pauses on that clause and hands off to CardSelectOverlay. The
# `_pending_play` Dictionary holds everything we need to either resume after
# the player picks (and continue with the next clause) or roll back the play
# entirely on cancel.
#
# Layout:
#   "card"        — CardData of the played card (already removed from hand)
#   "is_player"   — always true here; AI never goes through this path
#   "caster"      — PilotData (시전자)
#   "ally_team"   — 0 / 1
#   "enemy_team"  — 1 / 0
#   "clauses"     — Array of unparsed clause dicts still to be processed
#   "log_lines"   — Array<String> of clause result lines accumulated so far
#   "snapshot"    — Dictionary used by _restore_from_snapshot on cancel
var _pending_play: Dictionary = {}

# Set during end_card_phase()'s async AI play loop so a stray button press
# can't re-enter the routine. Cleared once the await chain unwinds.
var _ai_play_in_progress: bool = false

# True while the "당신의 차례" banner is sweeping in / holding / fading out.
# The hand stays dimmed and clicks are blocked until it clears so the player
# can't pre-empt the announcement.
var _player_turn_announce_in_progress: bool = false

# 전투 개시(PREVIEW) 중 카드/설명 박스를 그대로 유지하기 위해, 카드 파괴와
# 비용 차감을 확인 시점까지 미룬다. preview 모드 동안 보류 중인 hand Card
# 노드 참조를 보관해 두었다가 _on_preview_play_confirm 에서 실제로 처리한다.
var _preview_pending_card: Card = null


# ─── Deck setup ───────────────────────────────────────────────────────────────
# Per-pilot 6-card draw: every pilot pulls 6 random cards from the DB pool and
# tags them with itself as the 시전자. All 5 pilots' stacks shuffle together
# into the team deck — same logic for player and AI sides.
const CARDS_PER_PILOT: int = 6


func build_starter_decks() -> void:
	# Drop any selection state held over from the previous match (the game
	# restart path queue_frees player_card_nodes without touching the
	# description box / selected-card refs we manage here).
	deselect_current_card()
	_bs.player_deck.clear(); _bs.ai_deck.clear()
	_bs.player_discard.clear(); _bs.ai_discard.clear()
	var pool := _build_pool_from_db()
	if pool.is_empty():
		update_deck_discard_labels()
		return
	_deal_team_deck(pool, _team_pilots(0), _bs.player_deck)
	_deal_team_deck(pool, _team_pilots(1), _bs.ai_deck)
	_bs.player_deck.shuffle()
	_bs.ai_deck.shuffle()
	# Sync the visible Deck / Discard counters with the freshly-built deck.
	update_deck_discard_labels()


# Pulls CARDS_PER_PILOT random copies from `pool` for every pilot in `pilots`,
# stamping each copy with that pilot as 시전자. Appends all copies to `out_deck`.
func _deal_team_deck(pool: Array, pilots: Array, out_deck: Array) -> void:
	if pool.is_empty():
		return
	for raw in pilots:
		var p := raw as PilotData
		for i in CARDS_PER_PILOT:
			var src := pool[randi() % pool.size()] as CardData
			var copy := make_card_copy(src)
			copy.owner_pilot = p
			out_deck.append(copy)


func _team_pilots(team: int) -> Array:
	var out: Array = []
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.team == team:
			out.append(p)
	return out


func _build_pool_from_db() -> Array:
	var gm: Node = _bs.gm
	if gm != null and not gm.card_pool_bs.is_empty():
		var pool: Array = []
		for card_def in gm.card_pool_bs:
			pool.append(_make_card_from_def(card_def))
		return pool
	# Minimal one-card fallback so the demo still runs before Rebuild game.db.
	return [_make_card_from_def({
		"name": "공격", "cost": 1, "uses": 1,
		"cast_method": "target", "target": "enemy",
		"cast_range": 1, "area": 0, "keyword": "",
		"effect": "attack:1", "description": "공격: 1",
	})]


func _make_card_from_def(def: Dictionary) -> CardData:
	var cd := CardData.new(
			String(def.get("name", "?")),
			int(def.get("cost", 0)),
			String(def.get("description", "")))
	cd.uses        = int(def.get("uses", 1))
	cd.cast_method = String(def.get("cast_method", "instant"))
	cd.target      = String(def.get("target", "hand"))
	cd.cast_range  = int(def.get("cast_range", 0))
	cd.area        = int(def.get("area", 0))
	cd.keyword     = String(def.get("keyword", ""))
	cd.effect      = String(def.get("effect", ""))
	cd.remaining_uses = max(1, cd.uses) if cd.uses > 0 else 0
	return cd


# Copies a CardData (so each draw is a unique instance) including 시전자 tag and
# resetting the per-instance use counter.
func make_card_copy(src: CardData) -> CardData:
	var cd := CardData.new(src.card_name, src.cost, src.description)
	cd.uses        = src.uses
	cd.cast_method = src.cast_method
	cd.target      = src.target
	cd.cast_range  = src.cast_range
	cd.area        = src.area
	cd.keyword     = src.keyword
	cd.effect      = src.effect
	cd.owner_pilot = src.owner_pilot
	cd.remaining_uses = max(1, src.uses) if src.uses > 0 else 0
	return cd


# ─── Turn flow ────────────────────────────────────────────────────────────────
func do_battle_turn() -> void:
	if _bs.game_over or _bs.game_phase != GameEnums.BattlePhase.BATTLE:
		return
	_bs.sim_core.simulate_turn()
	if _bs.game_over:
		return
	_bs.cost_counter += 1
	if _bs.cost_counter >= _bs.COST_RECOVERY_INTERVAL:
		_bs.cost_counter = 0
		_bs.player_cost += _bs.COST_RECOVERY
		_bs.ai_cost     += _bs.COST_RECOVERY
	_bs.draw_counter += 1
	if _bs.draw_counter >= _bs.CARD_DRAW_INTERVAL:
		_bs.draw_counter = 0
		if _bs.player_hand.size() < _bs.MAX_HAND_SIZE:
			var drawn := draw_card(true)
			if drawn != null:
				spawn_card_node(drawn)
		if _bs.ai_hand.size() < _bs.MAX_HAND_SIZE:
			# AI hand visuals (face-down card backs) live in HudBuilder; the
			# row reflows after the draw so the count peek matches state.
			draw_card(false)
			_bs.hud.update_ai_hand_visuals()
	if _bs.player_cost >= _bs.PHASE_THRESHOLD:
		start_card_phase()
	else:
		_bs.renderer.queue_redraw()
		_bs.hud.update_hud()


func start_card_phase() -> void:
	_bs.game_phase = GameEnums.BattlePhase.CARD_PHASE
	# Snapshot the player's cost on phase entry so the "단계 넘기기" button can
	# require >= 1 point spent before becoming clickable.
	_bs.card_phase_entry_cost = _bs.player_cost
	# Phase-bound cost modifiers (정밀 이동 / 집중) only live for one
	# 작전 단계; reset on entry so a leftover from a previous phase doesn't
	# persist. engage_discount_* is intentionally NOT reset — 전투 준비 was
	# played in BATTLE phase and should keep its one-shot reduction available
	# for the upcoming engage card.
	_bs.phase_cost_inc_p = 0
	_bs.phase_cost_inc_ai = 0
	_bs.phase_draw_discount_p = 0
	_bs.phase_draw_discount_ai = 0
	_bs.renderer.queue_redraw()
	_bs.hud.update_hud()
	# Announce the player's turn. The hand stays dimmed during the banner
	# sweep so the player can't click cards before it clears.
	_player_turn_announce_in_progress = true
	_apply_hand_dim_state()
	await _bs.hud.play_turn_announce(true)
	_player_turn_announce_in_progress = false
	highlight_affordable_cards()
	_apply_hand_dim_state()
	_bs.hud.update_hud()


# Hand-dim driver: cards stay bright only while it's actually the player's
# turn to act — i.e., game_phase == CARD_PHASE, no announce/AI loop is in
# flight, and no modal targeting / pick overlay is active. Called from every
# state-change path that could flip "is it my turn?".
func _apply_hand_dim_state() -> void:
	var dim: bool = _is_player_input_blocked() \
			or _bs.game_phase != GameEnums.BattlePhase.CARD_PHASE
	for node in _bs.player_card_nodes:
		var c := node as Card
		if is_instance_valid(c):
			c.set_dimmed(dim)


# Returns true once the player has spent at least 1 강 점수 this 작전 단계.
# Also blocked while a discard / search overlay is mid-resolution so the
# player can't 단계 넘기기 their way out of an unfinished pick.
func can_end_card_phase() -> bool:
	if _bs.game_phase != GameEnums.BattlePhase.CARD_PHASE:
		return false
	if _bs.card_select_overlay != null and _bs.card_select_overlay.is_active():
		return false
	if _bs.targeting_overlay != null and _bs.targeting_overlay.is_active():
		return false
	if _ai_play_in_progress:
		return false
	if _player_turn_announce_in_progress:
		return false
	return _bs.player_cost < _bs.card_phase_entry_cost


func end_card_phase() -> void:
	if not can_end_card_phase():
		return
	# Drop any active card selection so the description box and lifted-card
	# state don't survive across the phase transition.
	deselect_current_card()
	# Block re-entry while AI plays unfold async — the button is also disabled
	# in HUD update via can_end_card_phase, but a quick double-press could
	# still race here. The flag clears once the await chain completes.
	if _ai_play_in_progress:
		return
	_ai_play_in_progress = true
	_apply_hand_dim_state()
	_bs.hud.update_hud()
	# Announce the AI's turn before any plays unfold, regardless of whether
	# the AI actually has anything to play this phase — the banner marks the
	# handover so the player knows the action has flipped to the opponent.
	await _bs.hud.play_turn_announce(false)
	# AI plays go through AiCardPlayer which awaits the central card animation
	# (and engage modal, when applicable) between plays. The HUD's
	# 단계 넘기기 button is disabled while is_active() in EngagePhaseManager.
	if _bs.ai_cost >= _bs.PHASE_THRESHOLD and _bs.ai_card_player != null:
		await _bs.ai_card_player.run_ai_plays()
	# Phase end: re-evaluate recalls (HP threshold + out-of-position from card effects).
	var log_lines: Array = []
	_bs.recall_sys.process_phase_end_recalls(log_lines)
	if not log_lines.is_empty():
		_bs.last_log = log_lines[-1]
	_bs.game_phase = GameEnums.BattlePhase.BATTLE
	_bs.renderer.queue_redraw()
	_bs.hud.update_hud()
	_ai_play_in_progress = false
	_apply_hand_dim_state()


# ─── Card draw ────────────────────────────────────────────────────────────────
func draw_card(is_player: bool) -> CardData:
	var deck:    Array = _bs.player_deck    if is_player else _bs.ai_deck
	var discard: Array = _bs.player_discard if is_player else _bs.ai_discard
	var hand:    Array = _bs.player_hand    if is_player else _bs.ai_hand
	var did_reshuffle := false
	var pre_discard_size := discard.size()
	if deck.is_empty():
		if discard.is_empty():
			return null
		deck.append_array(discard)
		discard.clear()
		deck.shuffle()
		did_reshuffle = true
	var card := deck.pop_back() as CardData
	# 집중 (cost_reduce_draw_phase) — every card drawn during the current
	# 작전 단계 gets its cost reduced once, permanently. Mutating the
	# CardData copy is fine: each draw uses make_card_copy so this is a
	# per-instance mutation, not a pool-wide change.
	var draw_disc: int = _bs.phase_draw_discount_p if is_player else _bs.phase_draw_discount_ai
	if draw_disc > 0:
		card.cost = max(0, card.cost - draw_disc)
	hand.append(card)
	if is_player:
		if did_reshuffle:
			# Animate the swap as one motion: discard pre_size → 0, deck 0 → deck.size()
			# (post-pop), so the visible counts tween towards the final state.
			_animate_reshuffle_counts(pre_discard_size, deck.size(), discard.size())
		else:
			update_deck_discard_labels()
	return card


# ─── Deck / Discard count display ────────────────────────────────────────────
## Snap the visible Deck / Discard counts to the actual array sizes. Cancels
## any running reshuffle tween so the labels don't fight each other.
func update_deck_discard_labels() -> void:
	if _reshuffle_tween != null and _reshuffle_tween.is_running():
		_reshuffle_tween.kill()
	_deck_displayed    = float(_bs.player_deck.size())
	_discard_displayed = float(_bs.player_discard.size())
	_refresh_count_labels()


## Tween: discard `old_discard → new_discard` and deck `0 → new_deck` in
## parallel over BS_RESHUFFLE_TWEEN_DUR. Called when draw_card reshuffles.
func _animate_reshuffle_counts(old_discard: int, new_deck: int, new_discard: int) -> void:
	if _reshuffle_tween != null and _reshuffle_tween.is_running():
		_reshuffle_tween.kill()
	# Lock the visible state to the pre-reshuffle snapshot, then tween to target.
	_deck_displayed    = 0.0
	_discard_displayed = float(old_discard)
	_refresh_count_labels()
	_reshuffle_tween = create_tween().set_parallel()
	_reshuffle_tween.tween_method(_set_deck_displayed,
			0.0, float(new_deck), _bs.BS_RESHUFFLE_TWEEN_DUR
			).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	_reshuffle_tween.tween_method(_set_discard_displayed,
			float(old_discard), float(new_discard), _bs.BS_RESHUFFLE_TWEEN_DUR
			).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)


func _set_deck_displayed(v: float) -> void:
	_deck_displayed = v
	_refresh_count_labels()


func _set_discard_displayed(v: float) -> void:
	_discard_displayed = v
	_refresh_count_labels()


func _refresh_count_labels() -> void:
	if _bs.lbl_deck_count != null:
		_bs.lbl_deck_count.text = "Deck\n%d" % int(round(_deck_displayed))
	if _bs.lbl_discard_count != null:
		_bs.lbl_discard_count.text = "Discard\n%d" % int(round(_discard_displayed))


# ─── Card node helpers ────────────────────────────────────────────────────────
func spawn_card_node(cd: CardData) -> void:
	var node := _bs.CARD_SCENE.instantiate() as Card
	node.pivot_offset = Vector2(80.0, 110.0)
	_bs.canvas.add_child(node)
	# The hand's hit layer picks the mouse for every card in the row, so the
	# cards themselves must not — an overlapping card that claims its own rect
	# steals its neighbour's only clickable pixels (see _apply_hit_bands).
	_set_subtree_mouse_ignore(node)
	node.global_position = _bs.BS_HAND_CENTER  # start at hand center for spring-in
	node.setup(cd, true, true)
	# Hover brings the card to the top of the hand z-order; click selects it
	# and opens the description box (handled in CardPhaseManager).
	node.card_clicked.connect(on_card_clicked)
	node.card_hovered.connect(on_card_hovered)
	node.card_unhovered.connect(on_card_unhovered)
	_bs.player_card_nodes.append(node)
	relayout_hand(_bs.player_card_nodes)
	highlight_affordable_cards()
	update_deck_discard_labels()
	# Newly-spawned cards inherit the current turn dim state so a card drawn
	# during BATTLE / AI turn / banner sweep isn't briefly bright.
	_apply_hand_dim_state()


## Uniform centre-to-centre spacing (px) between adjacent cards in a hand of
## `total`. Cards sit `BS_HAND_CARD_GAP` apart until the natural span outgrows
## BS_HAND_WIDTH; from then on the spacing compresses uniformly so the row always
## fits the fixed-width slot the Deck / Discard indicators are measured against.
func slot_spacing(total: int) -> float:
	var ideal_spacing: float = Card.CARD_W + _bs.BS_HAND_CARD_GAP
	if total <= 1:
		return ideal_spacing
	var ideal_total: float = float(total) * Card.CARD_W \
			+ float(total - 1) * _bs.BS_HAND_CARD_GAP
	if ideal_total <= _bs.BS_HAND_WIDTH:
		return ideal_spacing
	return (_bs.BS_HAND_WIDTH - Card.CARD_W) / float(total - 1)


## Signed horizontal distance (px) from the middle of the hand row to the centre
## of card `index` — the single input every other piece of fan geometry derives
## from (X slot, tilt, arc drop all read off it).
##
## Folds in the spread that opens the row around the focus card. There is no
## push-free variant: a card's slot is a single number, and the focus card's own
## push is 0 by construction, so the lifted-card poses read the same slot as
## everyone else. (An opt-out parameter used to exist for exactly that case and
## was the bug — a card selected while a *different* card had opened the row got
## posed at its unpushed slot and visibly slid sideways on the way up.)
func slot_center_dx(index: int, total: int) -> float:
	if total <= 0:
		return 0.0
	var dx: float = (float(index) - float(total - 1) * 0.5) * slot_spacing(total)
	return dx + hover_push_offset(index, total)


# ── Hand fan ──────────────────────────────────────────────────────────────────
# The hand is a real fan, not a flat row. Every card centre rides a circle of
# radius BS_HAND_FAN_RADIUS whose pivot sits directly *below* the row, and both
# readings of the fan come off that one circle: a card's tilt is its angle on the
# circle, and its vertical offset is how far the circle has fallen away from its
# apex at that angle. The apex is the middle of the row, so the centre card is
# the highest and the hand curves *down* toward both ends — the way a hand of
# cards splays when it's held from underneath.

## Tilt (radians) of a card whose centre sits `dx` px sideways of the hand
## centre. Negative (counter-clockwise, leaning left) on the left half of the
## fan, positive (leaning right) on the right half.
func _fan_angle(dx: float) -> float:
	var radius: float = _bs.BS_HAND_FAN_RADIUS
	if radius <= 0.0:
		return 0.0
	return asin(clampf(dx / radius, -1.0, 1.0))


## How far (px) *below* the fan's apex a card at horizontal offset `dx` hangs.
## Always ≥ 0 and 0 only at the middle of the row, so the centre card is the
## highest one and the ends drop away symmetrically.
func _fan_arc_drop(dx: float) -> float:
	var radius: float = _bs.BS_HAND_FAN_RADIUS
	if radius <= 0.0:
		return 0.0
	var d: float = clampf(absf(dx), 0.0, radius)
	return radius - sqrt(radius * radius - d * d)


## Compute the slot position (top-left, viewport space) for card `index` in a
## hand of `total` cards. X follows slot_center_dx; Y rides the fan arc, so a
## card near either end of the row sits lower than the middle one. Rotation for
## the same slot comes from slot_rotation().
func slot_position(index: int, total: int) -> Vector2:
	if total <= 0:
		return _bs.BS_HAND_CENTER
	# BS_HAND_CENTER is the top-left a card centred in the row would take (see
	# BattleSim._ready), so a centre-to-centre distance adds to it directly.
	var dx: float = slot_center_dx(index, total)
	return Vector2(_bs.BS_HAND_CENTER.x + dx,
			_bs.BS_HAND_CENTER.y + _fan_arc_drop(dx))


## Horizontal offset (px) card `index` takes on while some *other* card in the
## hand is the focus, so the enlarged card doesn't cover its neighbours.
##
## **The hand keeps its resting width the whole time.** The two outermost cards
## are anchors and never move; everything between them slides away from the focus
## by `_hover_push_amount` scaled by a falloff that reaches exactly 0 at the end
## of its own side. So the row does not grow — it redistributes: the cards next
## to the focus take almost the whole push, and each card further out takes less,
## the outermost taking none. `BS_HAND_HOVER_FALLOFF_POW` (2.0) is what keeps the
## near neighbours close to full push instead of bleeding the give-way evenly
## across the block, which is the clearance a packed hand needs most.
##
## Note the two sides are ramped independently against their own distance to the
## end of the row, so a focus card sitting off-centre still pushes both of its
## neighbours by nearly the full amount.
func hover_push_offset(index: int, total: int) -> float:
	if total <= 1:
		return 0.0
	var focus := _push_focus_card()
	if focus == null:
		return 0.0
	var h := _bs.player_card_nodes.find(focus)
	if h < 0 or index == h:
		return 0.0
	# Cards remaining between the focus and the anchored end on this side.
	var steps_to_end: int = (total - 1 - h) if index > h else h
	if steps_to_end <= 0:
		return 0.0
	var t: float = float(absi(index - h)) / float(steps_to_end)
	var ramp: float = 1.0 - pow(t, _bs.BS_HAND_HOVER_FALLOFF_POW)
	var push: float = _hover_push_amount(total) * ramp
	return push if index > h else -push


## How far (px) the card immediately beside the focus slides away from it. Cards
## further out get a fraction of this — see hover_push_offset.
##
## Solved from the coverage it has to prevent rather than fixed: the focus card
## is drawn at `Card.HOVER_SCALE` around its own centre, so it covers
## `CARD_W × HOVER_SCALE / 2` to either side, and its neighbour only stays
## clickable while its centre sits that far off plus `BS_HAND_HOVER_MIN_STRIP`.
## The resting spacing already pays part of that bill and pays less the more
## cards the hand holds, so the push is whatever is still missing — **it grows
## with the hand size**: 0 extra up to 6 cards, ~16px at 8, ~61px at the 12-card
## cap. It never falls below `BS_HAND_HOVER_PUSH` so even a small, roomy hand
## still visibly opens around the focus. No edge clamp is needed: the row's
## outermost cards are anchored, so it can never grow past its resting span.
func _hover_push_amount(total: int) -> float:
	if total <= 1:
		return 0.0
	var clearance: float = Card.CARD_W * Card.HOVER_SCALE * 0.5 \
			+ _bs.BS_HAND_HOVER_MIN_STRIP
	return maxf(_bs.BS_HAND_HOVER_PUSH, clearance - slot_spacing(total))


## The card the row currently spreads around: the **selected** card if there is
## one, otherwise the card under the cursor.
##
## A selected card is the hand's focus in exactly the same way a hovered one is —
## the row must open around it and stay open while the player walks the cursor
## over to the description box. Routing both states through this one accessor is
## also what makes the lift reversible: the focus card's own push offset is 0, so
## its pushed slot *is* its resting slot, and select → deselect can't leave it
## displaced by a stale push from whichever card happened to be hovered first.
func _push_focus_card() -> Card:
	if _selected_card != null and is_instance_valid(_selected_card) \
			and _bs.player_card_nodes.has(_selected_card):
		return _selected_card
	return _hovered_hand_card()


## The hand card currently under the cursor, or null. `_hovered_card` is the
## fast path; it's validated against the card's own hover flag (and the array)
## so a stale pointer — freed card, hover that arrived while a modal owned the
## screen — can never keep the row pushed open.
func _hovered_hand_card() -> Card:
	if _hovered_card != null and is_instance_valid(_hovered_card) \
			and _bs.player_card_nodes.has(_hovered_card) \
			and _hovered_card.is_hovered():
		return _hovered_card
	for node in _bs.player_card_nodes:
		var c := node as Card
		if c.is_hovered():
			return c
	return null


## Rotation (radians) for card `index` in a hand of `total` cards: its angle on
## the fan circle, so the tilt always agrees with the arc drop in slot_position.
## The middle card stays upright, the left half leans left and the right half
## leans right. Cards rotate around their own centre (pivot_offset set in
## spawn_card_node), so the slot X positions still hold.
func slot_rotation(index: int, total: int) -> float:
	if total <= 1:
		return 0.0
	return _fan_angle(slot_center_dx(index, total))


## Animate all hand cards to their slot positions and fan rotations.
## After tweening, restores the canonical scene-tree draw order (newest on top).
func relayout_hand(nodes: Array, skip: Variant = null) -> void:
	var total := nodes.size()
	for i in total:
		var node := nodes[i] as Card
		if node == skip:
			continue
		var pos := slot_position(i, total)
		node.tween_to(pos, slot_rotation(i, total), Vector2.ONE,
				_bs.BS_HAND_SPRING_DURATION,
				_bs.BS_HAND_TWEEN_EASE, _bs.BS_HAND_TWEEN_TRANS)
		node.store_base_y()
	if nodes == _bs.player_card_nodes:
		# Whatever triggered this pass, the row now matches the current focus,
		# so record it — a queued reflow that would repeat this layout can then
		# bail instead of restarting every card's tween.
		_reflow_focus = _push_focus_card()
		_apply_hit_bands(total)
		_reorder_hand_nodes()


## Takes a hand card and everything inside it out of mouse picking.
##
## This has to be the **whole subtree**, not just the Card root. Godot's
## per-class defaults are the trap: `Container` subclasses default to
## `MOUSE_FILTER_PASS`, and a PASS control is still returned by picking — it only
## forwards the *event* to its parent afterwards. So Card.tscn's
## MarginContainer / VBoxContainer / CenterContainer kept answering for the
## card's full rect, the hit layer underneath never saw a single event, and
## because Godot also walks a mouse-enter up the parent chain, the Card itself
## still lit up. Same defaults, opposite direction, as the note in this folder's
## README about decorative children needing IGNORE or PASS.
func _set_subtree_mouse_ignore(node: Node) -> void:
	var ct := node as Control
	if ct != null:
		ct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_subtree_mouse_ignore(child)


## Recomputes the hand's hit bands and re-fits the hit layer over the row.
##
## Draw order and hit-testing are two different questions, and letting the first
## answer the second is what made a packed hand unclickable. The cards overlap
## far more than they are wide (160px on a 67.5px stride at the 12-card cap) and
## the focus card is drawn on top at 1.2×, so per-card rect picking let it eat
## the only pixels its right-hand neighbour had left — measured at 5–17px across
## most focus positions and **0px** with the row's 9th card focused, i.e. that
## neighbour could not be hovered at all. So the cards stop picking the mouse
## (`MOUSE_FILTER_IGNORE`) and one layer over the row answers instead, splitting
## it into bands cut at the midpoints between neighbouring card *centres*. The
## bands tile the row exactly — no overlap to fight over, no gap to fall
## through — so every card owns roughly `slot_spacing` px regardless of who is
## drawn on top of it.
func _apply_hit_bands(total: int) -> void:
	_hit_bands.clear()
	if total <= 0:
		if _hand_hit_layer != null:
			_hand_hit_layer.visible = false
		return
	var centers: Array[float] = []
	for i in total:
		centers.append(_bs.BS_HAND_CENTER.x + slot_center_dx(i, total)
				+ Card.CARD_W * 0.5)
	for i in total:
		# The outermost cards extend their band out to their own edge instead of
		# stopping half a stride short, so the ends of the row stay clickable.
		var left: float = centers[i] - Card.CARD_W * 0.5
		if i > 0:
			left = (centers[i - 1] + centers[i]) * 0.5
		var right: float = centers[i] + Card.CARD_W * 0.5
		if i < total - 1:
			right = (centers[i] + centers[i + 1]) * 0.5
		_hit_bands.append(Vector2(left, right))
	_fit_hit_layer(total)


## Builds (once) and re-fits the transparent Control that owns mouse picking for
## the whole hand row. It is deliberately sized to the band the cards already
## occupy — the row's span plus the hover enlargement, and the lift only while a
## card is actually selected — so it can't swallow anything the cards weren't
## covering anyway. The player 전략 포인트 도넛 clears its top edge by 28px.
func _fit_hit_layer(total: int) -> void:
	if _hand_hit_layer == null:
		_hand_hit_layer = Control.new()
		_hand_hit_layer.name = "HandHitLayer"
		_hand_hit_layer.mouse_filter = Control.MOUSE_FILTER_STOP
		_bs.canvas.add_child(_hand_hit_layer)
		_hand_hit_layer.gui_input.connect(_on_hit_layer_gui_input)
		_hand_hit_layer.mouse_exited.connect(_on_hit_layer_mouse_exited)
	var grow_x: float = Card.CARD_W * (Card.HOVER_SCALE - 1.0) * 0.5
	var grow_y: float = Card.CARD_H * (Card.HOVER_SCALE - 1.0) * 0.5
	var lift: float = Card.PRESS_LIFT if _selected_card != null else 0.0
	var left: float  = _bs.BS_HAND_CENTER.x + slot_center_dx(0, total) - grow_x
	var right: float = _bs.BS_HAND_CENTER.x + slot_center_dx(total - 1, total) \
			+ Card.CARD_W + grow_x
	# The row's ends hang lowest on the fan arc, so the deepest card sets the
	# bottom edge.
	var drop: float = _fan_arc_drop(slot_center_dx(0, total))
	drop = maxf(drop, _fan_arc_drop(slot_center_dx(total - 1, total)))
	var top: float = _bs.BS_HAND_CENTER.y - grow_y - lift
	_hand_hit_layer.position = Vector2(left, top)
	_hand_hit_layer.size = Vector2(right - left,
			_bs.BS_HAND_CENTER.y + drop + Card.CARD_H + grow_y - top)
	_hand_hit_layer.visible = true


## The hand card at viewport point `p`, or null.
##
## Band lookup with one hysteresis rule: **the focus card holds the cursor while
## it is anywhere on its enlarged face.** Without that, the hand walks away from
## the cursor — hovering a card re-spreads the row, which slides the bands
## sideways under a stationary cursor, which hands the hover to the next card
## along, which re-spreads again. That cascade is real and was measured: a single
## step from card 0 toward card 1 ran the focus 0 → 2 → 4 → 6 → 8 → 10 → 11.
func _hand_card_at(p: Vector2) -> Card:
	var total := _bs.player_card_nodes.size()
	if total == 0 or _hit_bands.size() != total:
		return null
	var focus := _push_focus_card()
	if focus != null and _card_rect(focus).has_point(p):
		return focus
	for i in total:
		var band: Vector2 = _hit_bands[i]
		if p.x < band.x or p.x > band.y:
			continue
		var card := _bs.player_card_nodes[i] as Card
		return card if _card_rect(card).has_point(p) else null
	return null


## A card's on-screen rect. Scale is applied around `pivot_offset`, so the
## visual top-left is `position + pivot − pivot·scale`. The fan tilt (≤6.7°) is
## ignored — this is a hit rect, not a drawing bound.
func _card_rect(card: Card) -> Rect2:
	return Rect2(card.position + card.pivot_offset - card.pivot_offset * card.scale,
			Vector2(Card.CARD_W, Card.CARD_H) * card.scale)


func _on_hit_layer_gui_input(event: InputEvent) -> void:
	var local: Vector2
	if event is InputEventMouse:
		local = (event as InputEventMouse).position
	elif event is InputEventScreenTouch:
		local = (event as InputEventScreenTouch).position
	elif event is InputEventScreenDrag:
		local = (event as InputEventScreenDrag).position
	else:
		return
	var p: Vector2 = _hand_hit_layer.get_global_transform_with_canvas() * local
	_update_hover_at(p)
	var pressed: bool = false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		pressed = mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	# accept_event() mirrors what Card._gui_input used to do: the press that
	# selects a card must not double back into the outside-click deselect.
	_hand_hit_layer.accept_event()
	var card := _hand_card_at(p)
	if card != null:
		on_card_clicked(card)
	else:
		# A press inside the layer's padding but on no card reads as "outside".
		deselect_current_card()


func _on_hit_layer_mouse_exited() -> void:
	_update_hover_at(Vector2(-1e9, -1e9))


## Makes exactly the card under `p` (if any) the hovered one. Unhovers first so
## `_hovered_card` can't be left pointing at a card that has already dropped its
## hover state.
func _update_hover_at(p: Vector2) -> void:
	var want := _hand_card_at(p)
	for node in _bs.player_card_nodes:
		var c := node as Card
		if c != want:
			c.set_hovered(false)
	if want != null:
		want.set_hovered(true)


## Reorder player card nodes in the scene tree so that draw order matches hand order.
## Index 0 (oldest) is lowest; last index (newest) draws on top of all others.
## The selected card — or, failing that, the card under the cursor — is then
## raised above all of them, so a card the player is pointing at is never
## covered by its right-hand neighbours (including right after a deselect,
## while the cursor is still sitting on it).
func _reorder_hand_nodes() -> void:
	if _reordering:
		return
	var top: Card = _selected_card
	if top == null:
		top = _hovered_hand_card()
	if top != null and (not is_instance_valid(top)
			or not _bs.player_card_nodes.has(top)):
		top = null
	# Desired draw order: hand order, with `top` lifted above all of it.
	var order: Array[Card] = []
	for node in _bs.player_card_nodes:
		var card := node as Card
		if card != top:
			order.append(card)
	if top != null:
		order.append(top)
	# Bail when the tree already draws them in that order. move_child re-runs
	# mouse picking and fires enter/exit on the very cards being sorted, so a
	# reorder that changes nothing must touch nothing — otherwise every reflow
	# kicks off another hover storm and the hand never settles.
	var prev: int = -1
	var sorted := true
	for card in order:
		var ci: int = card.get_index()
		if ci <= prev:
			sorted = false
			break
		prev = ci
	if sorted:
		return
	_reordering = true
	for card in order:
		# move_child to last puts each successive card on top of the previous.
		card.get_parent().move_child(card, card.get_parent().get_child_count() - 1)
	_reordering = false


func highlight_affordable_cards() -> void:
	for node in _bs.player_card_nodes:
		var c := node as Card
		if c.data == null or not c.face_up:
			continue
		var eff: int = _bs.effective_cost_for(c.data, true)
		c.set_affordable(eff <= _bs.player_cost)
		# Reflect any active cost modifier (사전 준비 / 전투 준비 / 집중 /
		# 정밀 이동) on the card's top-left cost number — green when reduced
		# below the printed cost, red when increased, white when matched.
		c.update_displayed_cost(eff)
	# Re-evaluate hand dim alongside affordability since both keys off the
	# same "is it the player's turn to act?" question — overlay close paths
	# all funnel through here, so this single call covers them.
	_apply_hand_dim_state()


# ─── Click-to-select interaction ──────────────────────────────────────────────
# Hover feedback (brightness modulate) lives in Card.gd. CardPhaseManager owns
# the z-ordering, the lifted-card pose, the description box, and the
# outside-click dismissal.

func on_card_hovered(card: Card) -> void:
	# Tracked before the guards so the pointer stays accurate even when the
	# hover arrives while a card is selected or a modal owns the screen.
	_hovered_card = card
	if _bs.game_phase != GameEnums.BattlePhase.CARD_PHASE:
		return
	if _is_player_input_blocked():
		return
	# No selection check here: _push_focus_card is the single home of the
	# "selection outranks the cursor" rule, and _apply_hand_reflow no-ops when
	# the focus hasn't actually moved.
	_queue_hand_reflow()


func on_card_unhovered(card: Card) -> void:
	if _hovered_card == card:
		_hovered_card = null
	_queue_hand_reflow()


## Schedules one hand reflow at idle. Never reflow straight out of a hover
## signal: those signals are emitted from inside move_child while the parent is
## locked, and moving from one card to its neighbour fires an exit and an enter
## in the same frame — running both immediately means two overlapping relayouts
## whose tweens kill each other. Deferring collapses the pair into one pass.
func _queue_hand_reflow() -> void:
	if _hand_reflow_queued:
		return
	_hand_reflow_queued = true
	_apply_hand_reflow.call_deferred()


func _apply_hand_reflow() -> void:
	_hand_reflow_queued = false
	if _bs == null or not is_instance_valid(_bs):
		return
	var focus := _push_focus_card()
	# Nothing to do when the row already matches the focus — this is what stops
	# the enter/exit churn a reorder provokes from looping forever, and it is
	# also what makes hovering around while a card is selected a no-op (the
	# selection stays the focus, so `focus` never changes).
	if focus == _reflow_focus:
		return
	# The **new** focus card must be laid out with everyone else. Its slot under
	# the new focus is its resting slot (own push = 0), but it is almost never
	# sitting there: the previous focus had pushed it aside, and skipping it left
	# it stranded at that stale offset — a card hovered right after its neighbour
	# stayed displaced by up to a full push (+26.9px at 8 cards, ~60px at the
	# 12-card cap), so it read as mis-hovered and then slid sideways on its way
	# up when clicked. Only the *selected* card is skipped, because
	# `_select_card` owns its lifted pose; the hovered card's scale is untouched
	# by `tween_to`, so the layout spring can't fight the hover tween.
	relayout_hand(_bs.player_card_nodes, _selected_card)


func on_card_clicked(card: Card) -> void:
	if _bs.game_phase != GameEnums.BattlePhase.CARD_PHASE:
		return
	if _is_player_input_blocked():
		return
	if not is_instance_valid(card) or not _bs.player_card_nodes.has(card):
		return
	if _selected_card == card:
		# Re-clicking the selected card toggles the selection off — same result
		# as clicking outside it. 전투 개시 PREVIEW 진행 중에는 overlay 의
		# 취소 버튼만이 유일한 탈출구이므로 토글을 막는다.
		if _preview_pending_card != null:
			return
		deselect_current_card()
		return
	_select_card(card)


# Player can't pick / hover hand cards while another modal owns the screen
# (search pick, targeting overlay) or while the AI's async play loop is in
# flight. Discard mode is the exception — the overlay's whole job is to let
# the player click hand cards and pick which ones to throw away, so we let
# input through and rely on the desc-box "버리기" button to route the pick.
func _is_player_input_blocked() -> bool:
	if _ai_play_in_progress:
		return true
	if _player_turn_announce_in_progress:
		return true
	if _bs.targeting_overlay != null and _bs.targeting_overlay.is_active():
		return true
	if _bs.card_select_overlay != null and _bs.card_select_overlay.is_active():
		if _bs.card_select_overlay.is_discard_mode():
			return false
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	# Outside-click / outside-touch dismisses the active selection. Card,
	# description box, and button each accept their own events, so anything
	# reaching this handler is by definition outside all of them.
	if _selected_card == null:
		return
	# 전투 개시 PREVIEW 진행 중에는 외부 클릭으로 카드가 해제되지 않도록 차단.
	# overlay 의 취소 버튼을 통해서만 빠져나갈 수 있다.
	if _preview_pending_card != null:
		return
	var pressed: bool = false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pressed = true
	elif event is InputEventScreenTouch and event.pressed:
		pressed = true
	if pressed:
		deselect_current_card()


func _select_card(card: Card) -> void:
	var previous: Card = _selected_card
	if previous != null and previous != card:
		# Drop the previous selection out of its lifted pose — otherwise two
		# cards would float at once. Its slot is rewritten by the row-wide
		# reflow below, off the NEW focus.
		if is_instance_valid(previous):
			previous.set_selected(false)
		_hide_description_box()
	_selected_card = card
	# Selecting makes this card the row's focus, exactly as hovering it would,
	# so the whole row re-spreads around it here: the neighbours give way, the
	# previous selection settles back in, and the anchored end cards hold the
	# hand's width. The focus card itself is skipped — its lifted pose follows.
	# relayout_hand → _reorder_hand_nodes also raises it above every other card.
	relayout_hand(_bs.player_card_nodes, card)
	var idx := _bs.player_card_nodes.find(card)
	var total := _bs.player_card_nodes.size()
	# The focus card's own push offset is 0, so this pushed slot IS its resting
	# slot — lift and drop are exact opposites without a push-free special case,
	# and the card can't inherit a sideways shift from whichever card the cursor
	# happened to open the row around before this one was clicked.
	var slot := slot_position(idx, total)
	var rot := slot_rotation(idx, total)
	# The card keeps its fan tilt and slides out along its OWN up-axis rather
	# than along screen-up — straight out of the fan, the way a card is drawn
	# from a real hand. A card on the left half of the fan leans left, so it
	# travels up-left; one on the right half travels up-right. Sideways travel is
	# PRESS_LIFT × sin(fan angle): ±4.6px on the outermost card of a 12-card hand,
	# and it grows if BS_HAND_FAN_RADIUS is tightened.
	var lifted := slot + Vector2(0.0, -Card.PRESS_LIFT).rotated(rot)
	card.set_selected(true)
	card.tween_to(lifted, rot, Vector2.ONE,
			_bs.BS_HAND_SPRING_DURATION,
			_bs.BS_HAND_TWEEN_EASE, _bs.BS_HAND_TWEEN_TRANS)
	_show_description_box(card)
	# Pre-show the cast range / engage area on the battlefield so the player
	# can judge the play before pressing 카드 내기. Non-modal — does not
	# disable hand input or 단계 넘기기.
	if _bs.targeting_overlay != null:
		_bs.targeting_overlay.start_selection_preview(card.data)


# Public so end_card_phase / restart can drop any pending selection.
func deselect_current_card() -> void:
	if _selected_card == null:
		return
	if is_instance_valid(_selected_card):
		_selected_card.set_selected(false)
	_hide_description_box()
	_selected_card = null
	# Reflow the whole row — the dropped card INCLUDED. One pass places every
	# card off the same hover state, so the returning card can't land on a slot
	# that disagrees with the row it's landing in. If the cursor is still on it
	# it stays enlarged, so its neighbours slide away exactly as they do on a
	# fresh hover, and _reorder_hand_nodes (inside relayout_hand) re-raises it
	# above its right-hand neighbours.
	relayout_hand(_bs.player_card_nodes)
	# Clear the range / area visualization that _select_card kicked off.
	if _bs.targeting_overlay != null:
		_bs.targeting_overlay.clear_selection_preview()


# ─── Description box ─────────────────────────────────────────────────────────
func _show_description_box(card: Card) -> void:
	_hide_description_box()

	var box := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.96)
	style.border_color = Color(0.95, 0.85, 0.45, 1.0)
	style.border_width_top    = 2
	style.border_width_bottom = 2
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.corner_radius_top_left     = 12
	style.corner_radius_top_right    = 12
	style.corner_radius_bottom_left  = 12
	style.corner_radius_bottom_right = 12
	box.add_theme_stylebox_override("panel", style)
	box.size = Vector2(DESC_BOX_W, DESC_BOX_H)

	# Position next to the card. Pick the side with more room; clamp to screen.
	var screen_w: float = _bs.canvas.get_viewport().get_visible_rect().size.x
	# Same slot the lift in _select_card poses from (the selected card is the
	# focus, so its own push is 0), so the box stays glued to the lifted card.
	var slot := slot_position(_bs.player_card_nodes.find(card),
			_bs.player_card_nodes.size())
	var card_left: float  = slot.x
	var card_right: float = slot.x + Card.CARD_W
	var box_x: float
	if card_right + DESC_BOX_GAP + DESC_BOX_W <= screen_w - 8.0:
		box_x = card_right + DESC_BOX_GAP
	else:
		box_x = card_left - DESC_BOX_GAP - DESC_BOX_W
	box_x = clamp(box_x, 8.0, screen_w - DESC_BOX_W - 8.0)
	var box_y: float = slot.y - Card.PRESS_LIFT  # align with the lifted card top
	box.position = Vector2(box_x, box_y)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   = 14
	vbox.offset_top    = 14
	vbox.offset_right  = -14
	vbox.offset_bottom = -14
	vbox.add_theme_constant_override("separation", 10)
	box.add_child(vbox)

	# Header row: card name on the left, cost number on the right. The 시전자
	# tag was dropped — the card body already shows the owner face.
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var name_lbl := Label.new()
	name_lbl.text = card.data.card_name
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(name_lbl)

	var eff_cost: int = _bs.effective_cost_for(card.data, true)
	var cost_lbl := Label.new()
	cost_lbl.text = str(eff_cost)
	cost_lbl.add_theme_font_size_override("font_size", 26)
	# Same colour ramp as the card's top-left cost (white/green/red) so the
	# two readouts agree when 사전 준비 / 전투 준비 / 정밀 이동 are active.
	var cost_col: Color = Card.COST_COLOR_BASE
	if eff_cost < card.data.cost:
		cost_col = Card.COST_COLOR_REDUCED
	elif eff_cost > card.data.cost:
		cost_col = Card.COST_COLOR_INCREASED
	cost_lbl.add_theme_color_override("font_color", cost_col)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(cost_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = card.data.description
	desc_lbl.add_theme_font_size_override("font_size", 18)
	desc_lbl.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc_lbl)

	_play_button = Button.new()
	_play_button.add_theme_font_size_override("font_size", 22)
	_play_button.custom_minimum_size = Vector2(0.0, 52.0)
	# When a 버리기:N overlay is active, every hand card's desc-box surfaces a
	# "버리기" button instead of 카드 내기. We key off is_discard_mode() (not
	# can_pick_for_discard) so the button still shows "버리기" while
	# hidden_state is on — disabled, but consistent with the active mode.
	if _bs.card_select_overlay != null and _bs.card_select_overlay.is_discard_mode():
		_play_button.text = "버리기"
		_play_button.disabled = not _bs.card_select_overlay.can_pick_for_discard()
		_play_button.pressed.connect(_on_discard_selected_pressed)
	else:
		_play_button.text = "카드 내기"
		# Disabled when unaffordable OR when the card needs a target (pilot /
		# location / engage participants) and none are in range — 결투 with
		# no enemies in cast_range is the canonical case.
		var unaffordable: bool = eff_cost > _bs.player_cost
		var no_targets: bool = not card_has_valid_targets(card.data)
		_play_button.disabled = unaffordable or no_targets
		_play_button.pressed.connect(_on_play_selected_pressed)
	vbox.add_child(_play_button)

	_bs.canvas.add_child(box)
	_description_box = box


func _hide_description_box() -> void:
	if _description_box != null and is_instance_valid(_description_box):
		_description_box.queue_free()
	_description_box = null
	_play_button = null


func _on_play_selected_pressed() -> void:
	if _selected_card == null or not is_instance_valid(_selected_card):
		return
	var card := _selected_card
	if card.data == null or _bs.effective_cost_for(card.data, true) > _bs.player_cost:
		return
	# 전투 개시(PREVIEW) 카드는 카드 노드/설명 박스를 그대로 유지한 채 좌/우
	# 참여 파일럿 패널을 띄운다. 확인 시점까지 비용 차감 / 카드 제거를 미룬다.
	if _targeting_kind(card.data) == "preview":
		_start_preview_play(card)
		return
	# Tear down selection state BEFORE freeing the card so the dangling
	# reference never escapes this function.
	_hide_description_box()
	_selected_card = null
	_play_card_direct(card)


# PREVIEW 카드 전용: 카드/설명 박스를 살려둔 채 targeting overlay 의 PREVIEW
# 모드를 띄운다. 확인하면 _on_preview_play_confirm 이 비용 차감과 카드 파괴를
# 거쳐 본래 _play_card_direct 의 chain 단계로 합류한다.
func _start_preview_play(card: Card) -> void:
	var cd := card.data
	var caster: PilotData = cd.owner_pilot
	if caster == null:
		# Owner 가 없으면 미리보기 의미가 없으니 즉시 파괴 경로로 폴백.
		_hide_description_box()
		_selected_card = null
		_play_card_direct(card)
		return
	if not card_has_valid_targets(cd):
		# Should be blocked by the desc-box button disable, but guard anyway.
		return
	_preview_pending_card = card
	# 카드 내기 버튼은 PREVIEW 동안 비활성화 — 확정은 overlay 의 확인 버튼으로.
	if _play_button != null and is_instance_valid(_play_button):
		_play_button.disabled = true
	var area := _compute_engage_area(caster)
	var exclude_lane: bool = _has_clause_flag(cd.effect, "engage", "exclude_lane")
	var participants := _compute_engage_participants(caster, area, exclude_lane)
	_bs.targeting_overlay.start_preview(caster, area, participants,
			cd.card_name,
			Callable(self, "_on_preview_play_confirm"),
			Callable(self, "_on_preview_play_cancel"))


func _on_preview_play_confirm() -> void:
	var card := _preview_pending_card
	_preview_pending_card = null
	if card == null or not is_instance_valid(card):
		return
	# 이제 실제 파괴 경로로 합류 — _play_card_direct 가 PREVIEW 분기를
	# 건너뛰고 chain 으로 직행하도록 skip_preview_modal=true 를 전달한다.
	_hide_description_box()
	_selected_card = null
	_play_card_direct(card, true)


func _on_preview_play_cancel() -> void:
	_preview_pending_card = null
	# 카드는 그대로 핸드에 남아있고 설명 박스도 건재하니 카드 내기 버튼만
	# 다시 살린다. SELECTION_PREVIEW 시각화도 다시 켜서 사거리 표시를 복원.
	if _selected_card != null and is_instance_valid(_selected_card):
		if _play_button != null and is_instance_valid(_play_button):
			var eff_cost: int = _bs.effective_cost_for(_selected_card.data, true)
			var unaffordable: bool = eff_cost > _bs.player_cost
			var no_targets: bool = not card_has_valid_targets(_selected_card.data)
			_play_button.disabled = unaffordable or no_targets
		if _bs.targeting_overlay != null:
			_bs.targeting_overlay.start_selection_preview(_selected_card.data)


# Description-box "버리기" button handler: hands the currently-selected hand
# card off to the active discard overlay. add_card_to_discard() does the
# bookkeeping (hand removal, layout, threshold check); we just clear the
# desc-box state so the next pick can re-open it cleanly.
func _on_discard_selected_pressed() -> void:
	if _selected_card == null or not is_instance_valid(_selected_card):
		return
	if _bs.card_select_overlay == null \
			or not _bs.card_select_overlay.can_pick_for_discard():
		return
	var card := _selected_card
	_hide_description_box()
	_selected_card = null
	# The card survives (it moves into the to-discard fan), so drop the lifted
	# shadow pose with it — otherwise it keeps casting a floating shadow there.
	card.set_selected(false)
	_bs.card_select_overlay.add_card_to_discard(card)


# Player play path. Snapshots the pre-play state up front so a 버리기 / 찾기
# clause inside the effect chain can fully roll back on cancel — even when
# earlier clauses (e.g. draw:2 inside a draw:2;discard:2 card) already mutated
# the hand. The chain runs to completion synchronously unless it hits a clause
# that hands off to CardSelectOverlay, in which case _process_pending_chain
# returns early and the overlay's complete / cancel callback resumes us.
func _play_card_direct(card: Card, skip_preview_modal: bool = false) -> void:
	var cd := card.data
	# Snapshot BEFORE any mutation so refund-on-cancel is exact.
	# Shallow copies are correct: we only ever compare CardData identity.
	# engage_discount_p is also captured so a cancelled engage card refunds
	# the one-shot discount it consumed.
	var snapshot: Dictionary = {
		"hand":    _bs.player_hand.duplicate(),
		"deck":    _bs.player_deck.duplicate(),
		"discard": _bs.player_discard.duplicate(),
		"cost":    _bs.player_cost,
		"engage_discount_p": _bs.engage_discount_p,
	}
	var eff_cost: int = _bs.effective_cost_for(cd, true)
	_bs.player_cost -= eff_cost
	# Consume the engage discount on use so it doesn't double-dip onto a
	# follow-up engage. If this card is later cancelled, the snapshot
	# restore puts the discount back.
	if _bs.engage_discount_p > 0 and card_has_engage(cd):
		_bs.engage_discount_p = 0
	_bs.player_hand.erase(cd)
	_bs.player_card_nodes.erase(card)
	card.queue_free()

	_pending_play = {
		"card":       cd,
		"is_player":  true,
		"caster":     cd.owner_pilot,
		"ally_team":  0,
		"enemy_team": 1,
		"clauses":    _parse_effect_chain(cd.effect),
		"log_lines":  [],
		"snapshot":   snapshot,
		# Set after the targeting overlay resolves; remains null for cards that
		# don't need a target. Effect handlers consult this when wiring damage /
		# heals / location effects.
		"target":     null,
	}
	# Targeting branch: cards whose cast_method designates a pilot, cell or
	# caster-area open the targeting overlay before the chain runs. The
	# overlay either returns a target (→ continue chain) or fires cancel
	# (→ snapshot rollback, identical to the search/discard cancel path).
	var kind := _targeting_kind(cd)
	if kind == "pilot":
		var caster: PilotData = cd.owner_pilot
		var team_filter: int = _pending_play["enemy_team"] if cd.target == "enemy" \
				else _pending_play["ally_team"]
		var valid_pilots := _compute_valid_pilot_targets(cd, caster, team_filter)
		if valid_pilots.is_empty():
			# No legal target — refund and abort silently.
			_on_targeting_cancel()
			return
		_bs.targeting_overlay.start_pilot_target(valid_pilots,
				caster, max(0, cd.cast_range),
				Callable(self, "_on_targeting_pilot"),
				Callable(self, "_on_targeting_cancel"))
		return
	if kind == "location":
		var caster_loc: PilotData = cd.owner_pilot
		var valid_cells := _compute_valid_location_targets(cd, caster_loc)
		if valid_cells.is_empty():
			_on_targeting_cancel()
			return
		_bs.targeting_overlay.start_location_target(valid_cells,
				caster_loc, max(1, cd.cast_range),
				Callable(self, "_on_targeting_location"),
				Callable(self, "_on_targeting_cancel"))
		return
	if kind == "preview" and not skip_preview_modal:
		var caster_p: PilotData = cd.owner_pilot
		if caster_p == null:
			# Legacy fallback path — no caster means no preview is meaningful.
			_process_pending_chain()
			return
		var area := _compute_engage_area(caster_p)
		var exclude_lane: bool = _has_clause_flag(cd.effect, "engage", "exclude_lane")
		var participants := _compute_engage_participants(caster_p, area, exclude_lane)
		_bs.targeting_overlay.start_preview(caster_p, area, participants,
				cd.card_name,
				Callable(self, "_on_targeting_preview_confirm"),
				Callable(self, "_on_targeting_cancel"))
		return
	# No targeting required (instant cards) — straight to the chain.
	_process_pending_chain()


# Returns true when `cd` either needs no target OR has at least one legal
# target available right now (for the player side). Drives the desc-box
# 카드 내기 disable check so 결투-style cards with nothing in range can't
# be played; also surfaced to the selection-preview path so the renderer
# can decide whether to highlight any pilots/cells at all.
func card_has_valid_targets(cd: CardData) -> bool:
	if cd == null:
		return false
	var caster: PilotData = cd.owner_pilot
	match _targeting_kind(cd):
		"pilot":
			if caster == null:
				return false
			var team_filter: int = 1 if cd.target == "enemy" else 0
			return not _compute_valid_pilot_targets(cd, caster, team_filter).is_empty()
		"location":
			if caster == null:
				return false
			return not _compute_valid_location_targets(cd, caster).is_empty()
		"preview":
			# engage — require at least one alive participant from each
			# side inside the caster's area so start_engage doesn't no-op.
			if caster == null:
				return false
			var area := _compute_engage_area(caster)
			var exclude_lane: bool = _has_clause_flag(cd.effect, "engage", "exclude_lane")
			var participants := _compute_engage_participants(caster, area, exclude_lane)
			var has_p: bool = false
			var has_e: bool = false
			for raw in participants:
				var p := raw as PilotData
				if p.team == 0:
					has_p = true
				else:
					has_e = true
			return has_p and has_e
		_:
			return true


# ─── Targeting helpers ───────────────────────────────────────────────────────
# Maps a CardData's cast_method/target onto the kind of overlay we open.
#   "pilot"    — pick an enemy/ally pilot
#   "location" — pick a cell
#   "preview"  — caster-centred area; player confirms or cancels
#   "none"     — instant / no targeting
func _targeting_kind(cd: CardData) -> String:
	if cd == null:
		return "none"
	# 전투 개시류 (engage) 만 시전자 셀+인접 6칸을 PREVIEW 로 띄운다.
	# target=caster 가 그 표지. 전진(target=enemy)처럼 같은 cast_method=range
	# 라도 시전자 본인이 한 칸 이동/교전만 하는 카드는 PREVIEW 모달이 없다.
	if cd.cast_method == "range" and cd.target == "caster":
		return "preview"
	if cd.cast_method == "location":
		return "location"
	if cd.cast_method == "target":
		if cd.target == "enemy" or cd.target == "ally" or cd.target == "pilot":
			return "pilot"
	return "none"


# Pilots within hex range of caster, on the requested team, alive. Honours the
# `min_range` flag (e.g. 저격: range 6 with min_range:2 → cells 2..6 hexes
# from caster). Returns an Array of PilotData.
func _compute_valid_pilot_targets(cd: CardData, caster: PilotData,
		team: int) -> Array:
	var out: Array = []
	if caster == null:
		return out
	var max_r: int = max(0, cd.cast_range)
	var min_r: int = _clause_int_flag(cd.effect, "min_range", 0)
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive or p.team != team:
			continue
		var d: int = _bs.hex_grid.hex_distance(caster.grid_pos, p.grid_pos)
		if d > max_r:
			continue
		if d < min_r:
			continue
		out.append(p)
	return out


# Cells within hex range of caster (alive cells only). For 약탈
# (capture_jungle), restrict further to neutral_zone_cells currently owned by
# the enemy team.
func _compute_valid_location_targets(cd: CardData, caster: PilotData) -> Array:
	var out: Array = []
	if caster == null:
		return out
	var max_r: int = max(1, cd.cast_range)
	# Inspect the effect chain for clauses that constrain the legal set.
	var require_enemy_jungle: bool = false
	for clause in _parse_effect_chain(cd.effect):
		if String(clause.get("name", "")) == "capture_jungle":
			require_enemy_jungle = true
			break
	var enemy_team: int = 1 - caster.team
	var seen: Dictionary = {}
	for col in range(-8, 8):
		for row in range(-8, 8):
			var c := Vector2i(col, row)
			if not _bs.hex_grid.is_valid_cell(c.x, c.y):
				continue
			if seen.has(c):
				continue
			seen[c] = true
			var d: int = _bs.hex_grid.hex_distance(caster.grid_pos, c)
			if d == 0 or d > max_r:
				continue
			if require_enemy_jungle:
				if not _bs.neutral_zone_cells.has(c):
					continue
				if int(_bs.neutral_zone_cells[c]) != enemy_team:
					continue
			out.append(c)
	return out


# Caster cell + all 6 neighbours, mirroring EngagePhaseManager._gather_participants.
func _compute_engage_area(caster: PilotData) -> Array:
	var out: Array = [caster.grid_pos]
	for n in _bs.hex_grid.get_neighbors(caster.grid_pos.x, caster.grid_pos.y):
		out.append(n)
	return out


# Pilots in the engage area that would actually fight. Mirrors EngagePhaseManager
# rules including the exclude_lane filter for the 교전 card.
func _compute_engage_participants(caster: PilotData, area: Array,
		exclude_lane: bool) -> Array:
	var area_set: Dictionary = {}
	for c in area:
		area_set[c as Vector2i] = true
	var out: Array = []
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive:
			continue
		if not area_set.has(p.grid_pos):
			continue
		if exclude_lane and not (p.is_guerrilla or _bs.neutral_zone_cells.has(p.grid_pos)):
			continue
		out.append(p)
	return out


# Returns true if any clause in `effect_chain` named `clause_name` carries
# `flag_name` as a modifier (e.g. has_clause_flag("attack:1|pierce", "attack", "pierce")).
func _has_clause_flag(effect_chain: String, clause_name: String,
		flag_name: String) -> bool:
	for clause in _parse_effect_chain(effect_chain):
		if String(clause["name"]) != clause_name:
			continue
		for f in (clause.get("flags", []) as Array):
			var fs: String = f as String
			if fs == flag_name:
				return true
			if fs.begins_with(flag_name + ":"):
				return true
	return false


# Pulls an int value off a `flag:value` modifier inside any clause's flags.
# Used for min_range; returns `default` if absent.
func _clause_int_flag(effect_chain: String, flag_name: String,
		default: int) -> int:
	for clause in _parse_effect_chain(effect_chain):
		for f in (clause.get("flags", []) as Array):
			var fs: String = f as String
			if fs.begins_with(flag_name + ":"):
				return int(fs.substr(flag_name.length() + 1))
	return default


# ─── Targeting completion / cancel callbacks ────────────────────────────────
func _on_targeting_pilot(picked: PilotData) -> void:
	if _pending_play.is_empty():
		return
	_pending_play["target"] = picked
	_process_pending_chain()


func _on_targeting_location(cell: Vector2i) -> void:
	if _pending_play.is_empty():
		return
	_pending_play["target"] = cell
	_process_pending_chain()


func _on_targeting_preview_confirm() -> void:
	if _pending_play.is_empty():
		return
	# No explicit target stored — engage's effect handler reads from the card's
	# 시전자 field which is always set on the pending play.
	_process_pending_chain()


# Targeting cancel — same restore semantics as the discard/search overlay
# cancel path. Refunds cost, returns the played card to hand.
func _on_targeting_cancel() -> void:
	if _pending_play.is_empty():
		return
	var snap: Dictionary = _pending_play["snapshot"]
	_pending_play.clear()
	_restore_from_snapshot(snap)
	_bs.last_log = "[취소]"
	_bs.hud.update_hud()
	_bs.renderer.queue_redraw()


# Drains _pending_play.clauses one clause at a time. discard:N / search:N
# clauses (player side only) park the rest of the chain in _pending_play and
# bail out after starting the overlay; the resume callbacks call back into
# _process_pending_chain. Synchronous clauses just append to log_lines.
func _process_pending_chain() -> void:
	if _pending_play.is_empty():
		return
	var clauses: Array = _pending_play["clauses"]
	while not clauses.is_empty():
		var clause: Dictionary = clauses.pop_front()
		var ename: String = String(clause.get("name", ""))
		var n: int = int(clause.get("value", 0))
		if ename == "discard":
			_pending_play["clauses"] = clauses
			_bs.card_select_overlay.start_discard(n,
					_on_discard_overlay_complete,
					_on_overlay_cancel)
			return
		if ename == "search":
			_pending_play["clauses"] = clauses
			_bs.card_select_overlay.start_search(n,
					_on_search_overlay_complete,
					_on_overlay_cancel)
			return
		var msg := _apply_single_effect(clause, true,
				_pending_play["caster"],
				int(_pending_play["ally_team"]),
				int(_pending_play["enemy_team"]),
				_pending_play.get("target", null))
		if msg != "":
			(_pending_play["log_lines"] as Array).append(msg)
	_finalize_pending_play()


# Called by CardSelectOverlay when the player has picked all N cards (or the
# hand was smaller than N). The picks have already been removed from the
# player's hand by add_card_to_discard(); we just file them in the discard
# pile and resume the chain.
func _on_discard_overlay_complete(picks: Array) -> void:
	if _pending_play.is_empty():
		return
	for pick_raw in picks:
		_bs.player_discard.append(pick_raw as CardData)
	(_pending_play["log_lines"] as Array).append("버리기 %d" % picks.size())
	relayout_hand(_bs.player_card_nodes)
	update_deck_discard_labels()
	_bs.hud.update_hud()
	_process_pending_chain()


# Search complete: the picks are still in the deck — move them to the hand
# (capped at MAX_HAND_SIZE) and resume the chain.
func _on_search_overlay_complete(picks: Array) -> void:
	if _pending_play.is_empty():
		return
	var taken: int = 0
	for pick_raw in picks:
		if _bs.player_hand.size() >= _bs.MAX_HAND_SIZE:
			break
		var cd: CardData = pick_raw as CardData
		_bs.player_deck.erase(cd)
		_bs.player_hand.append(cd)
		spawn_card_node(cd)
		taken += 1
	(_pending_play["log_lines"] as Array).append("찾기 %d" % taken)
	update_deck_discard_labels()
	highlight_affordable_cards()
	_bs.hud.update_hud()
	_process_pending_chain()


# Cancel button handler — restores the entire pre-play state from the
# snapshot so the played card returns to hand, cost is refunded, and any
# interim mutations (draws, picked-for-discard cards still parked in the
# overlay) are rolled back together.
func _on_overlay_cancel() -> void:
	if _pending_play.is_empty():
		return
	var snap: Dictionary = _pending_play["snapshot"]
	_pending_play.clear()
	_restore_from_snapshot(snap)
	_bs.last_log = "[취소]"
	_bs.hud.update_hud()
	_bs.renderer.queue_redraw()


# Wipes out the live hand visuals and rebuilds them from a snapshot's CardData
# list. Cost / deck / discard arrays are restored verbatim. Used both for the
# overlay-cancel path and for any future "mid-effect bail" needs.
func _restore_from_snapshot(snap: Dictionary) -> void:
	# Drop any active selection (description box) before tearing down nodes —
	# _selected_card may point at a node we're about to free.
	deselect_current_card()
	for raw in _bs.player_card_nodes:
		var node := raw as Card
		if is_instance_valid(node):
			node.queue_free()
	_bs.player_card_nodes.clear()
	_bs.player_hand    = (snap["hand"]    as Array).duplicate()
	_bs.player_deck    = (snap["deck"]    as Array).duplicate()
	_bs.player_discard = (snap["discard"] as Array).duplicate()
	_bs.player_cost    = int(snap["cost"])
	if snap.has("engage_discount_p"):
		_bs.engage_discount_p = int(snap["engage_discount_p"])
	for raw_cd in _bs.player_hand:
		spawn_card_node(raw_cd as CardData)
	relayout_hand(_bs.player_card_nodes)
	highlight_affordable_cards()
	update_deck_discard_labels()


# Finalize: dispose the played card, log the chain summary, and refresh UI.
func _finalize_pending_play() -> void:
	if _pending_play.is_empty():
		return
	var cd: CardData = _pending_play["card"]
	var caster_label: String = "—"
	if _pending_play["caster"] != null:
		caster_label = _bs.pilot_label(_pending_play["caster"] as PilotData)
	var prefix: String = "%s [%s]" % [caster_label, cd.card_name]
	var lines: Array = _pending_play["log_lines"]
	var log_msg: String = prefix
	if not lines.is_empty():
		log_msg = "%s · %s" % [prefix, ", ".join(lines)]
	# 사용 횟수 / 소멸 routing decides whether the card lands in the discard
	# pile or is removed from the match entirely.
	_dispose_used_card(cd, true)
	_bs.last_log = log_msg
	_pending_play.clear()
	relayout_hand(_bs.player_card_nodes)
	highlight_affordable_cards()
	update_deck_discard_labels()
	_bs.hud.update_hud()
	_bs.renderer.queue_redraw()


# Routes a played card by 키워드 / 사용 횟수 rules:
#  - keyword == "exhaust"     → removed (소멸), never re-enters the deck
#  - uses == 0                → unlimited; always returns to the discard pile
#  - uses > 0                 → decrement remaining_uses; remove when it hits 0
#  - else                     → returns to the discard pile
func _dispose_used_card(cd: CardData, is_player: bool) -> void:
	var discard: Array = _bs.player_discard if is_player else _bs.ai_discard
	if cd.keyword == "exhaust":
		return
	if cd.uses > 0:
		cd.remaining_uses -= 1
		if cd.remaining_uses <= 0:
			return
	discard.append(cd)


# ─── Card effects ─────────────────────────────────────────────────────────────
# Effect column on cards.csv is a semicolon-separated chain of clauses; each
# clause is `name[:value][|flag[:value]]…`. Examples:
#   "draw:2;discard:2"            — two clauses
#   "attack:1|pierce|min_range:2" — one attack clause with two modifier flags
#   "engage:3|exclude_lane"       — engage with one modifier
# `caster` (cd.owner_pilot) is the 시전자 — it appears in the log line and is
# what future combat math will resolve from.
# Public AI-side wrapper: applies the effect chain AND runs 사용 횟수 / 소멸
# routing so the called side (AiCardPlayer) doesn't have to reach into private
# helpers across the module boundary.
func apply_and_dispose_ai_card(cd: CardData) -> String:
	var msg := apply_card_effect(cd, false)
	_dispose_used_card(cd, false)
	return msg


# Returns true if `cd`'s effect chain contains an `engage:N` clause. Public so
# AiCardPlayer can decide whether to await the engage modal between plays
# without reaching into _parse_effect_chain.
func card_has_engage(cd: CardData) -> bool:
	for clause in _parse_effect_chain(cd.effect):
		if String(clause["name"]) == "engage":
			return true
	return false


func apply_card_effect(cd: CardData, is_player: bool) -> String:
	var caster: PilotData = cd.owner_pilot
	var caster_label: String = _bs.pilot_label(caster) if caster != null else "—"
	var ally_team: int = 0 if is_player else 1
	var enemy_team: int = 1 - ally_team
	# AI / fallback path: pre-pick a deterministic target so effect handlers
	# don't have to branch on null. Returns null for cards that don't target.
	var target: Variant = _ai_pick_target(cd, caster, ally_team, enemy_team)

	var clauses: Array = _parse_effect_chain(cd.effect)
	var lines: Array = []
	for clause in clauses:
		var msg := _apply_single_effect(clause, is_player, caster,
				ally_team, enemy_team, target)
		if msg != "":
			lines.append(msg)
	var prefix: String = "%s [%s]" % [caster_label, cd.card_name]
	if lines.is_empty():
		return prefix
	return "%s · %s" % [prefix, ", ".join(lines)]


# Picks a target for an AI-played card. Mirrors the player-side targeting
# overlay rules but resolves to a random valid pick instead of opening UI.
# Returns PilotData (target=enemy/ally), Vector2i (target=location), or null.
func _ai_pick_target(cd: CardData, caster: PilotData,
		ally_team: int, enemy_team: int) -> Variant:
	if cd == null:
		return null
	match _targeting_kind(cd):
		"pilot":
			var team: int = enemy_team if cd.target == "enemy" else ally_team
			var valid := _compute_valid_pilot_targets(cd, caster, team)
			if valid.is_empty():
				return null
			return valid[randi() % valid.size()]
		"location":
			var valid_cells := _compute_valid_location_targets(cd, caster)
			if valid_cells.is_empty():
				return null
			return valid_cells[randi() % valid_cells.size()]
		_:
			return null


func _parse_effect_chain(raw: String) -> Array:
	var out: Array = []
	for clause_raw in raw.split(";", false):
		var clause: String = clause_raw.strip_edges()
		if clause.is_empty():
			continue
		var parts: Array = clause.split("|", false)
		var head: String = (parts[0] as String).strip_edges()
		var ename: String = head
		var value: int = 0
		var colon_idx: int = head.find(":")
		if colon_idx >= 0:
			ename = head.substr(0, colon_idx)
			value = int(head.substr(colon_idx + 1))
		var flags: Array = []
		for j in range(1, parts.size()):
			flags.append((parts[j] as String).strip_edges())
		out.append({"name": ename, "value": value, "flags": flags})
	return out


func _apply_single_effect(e: Dictionary, is_player: bool, caster: PilotData,
		ally_team: int, enemy_team: int,
		selected_target: Variant = null) -> String:
	var ename: String = String(e["name"])
	var value: int = int(e.get("value", 0))
	var flags: Array = e.get("flags", [])
	match ename:
		"draw":     return _effect_draw(is_player, value)
		"search":   return _effect_draw(is_player, value)   # 찾기 = same draw mechanic
		"discard":  return _effect_discard(is_player, value)
		"strategy": return _effect_strategy(is_player, value)
		"attack":   return _effect_attack(value, flags, caster, enemy_team,
				selected_target as PilotData)
		"shield_pct": return _effect_shield_pct(value, ally_team,
				selected_target as PilotData)
		"recall_ally": return _effect_recall_ally(ally_team,
				selected_target as PilotData)
		"exhaust_choice": return _effect_exhaust_choice(is_player, value)
		"engage":   return _effect_engage(value, flags, caster, is_player)
		"duel":                    return _effect_duel(caster,
				selected_target as PilotData, is_player)
		"move":                    return _effect_move(caster, selected_target)
		"capture_jungle":          return _effect_capture_jungle(value,
				selected_target, caster)
		"cost_reduce_engage":      return _effect_cost_reduce_engage(value, is_player)
		"cost_reduce_hand":        return _effect_cost_reduce_hand(value, is_player)
		"cost_reduce_draw_phase":  return _effect_cost_reduce_draw_phase(value, is_player)
		"cost_inc_phase":          return _effect_cost_inc_phase(value, is_player)
		"advance":                 return _effect_advance(value, caster)
		# Stubbed — landing log only until the supporting systems exist.
		"strategy_on_kill":        return "처치 시 전략 점수 +%d (예약)" % value
		"return_left":             return ""   # decorator on move; no standalone log
		_: return ""


func _effect_draw(is_player: bool, n: int) -> String:
	var hand: Array = _bs.player_hand if is_player else _bs.ai_hand
	var drew: int = 0
	for i in n:
		if hand.size() >= _bs.MAX_HAND_SIZE:
			break
		var c := draw_card(is_player)
		if c == null:
			break
		if is_player:
			spawn_card_node(c)
		drew += 1
	if not is_player and drew > 0:
		_bs.hud.update_ai_hand_visuals()
	return "드로우 %d" % drew


func _effect_discard(is_player: bool, n: int) -> String:
	# UI selection isn't built yet — discard random N from hand for the demo.
	var hand: Array    = _bs.player_hand    if is_player else _bs.ai_hand
	var discard: Array = _bs.player_discard if is_player else _bs.ai_discard
	var moved: int = 0
	for i in n:
		if hand.is_empty():
			break
		var pick := hand[randi() % hand.size()] as CardData
		hand.erase(pick)
		discard.append(pick)
		if is_player:
			_despawn_player_card_node(pick)
		moved += 1
	if is_player:
		relayout_hand(_bs.player_card_nodes)
	else:
		_bs.hud.update_ai_hand_visuals()
	return "버리기 %d" % moved


func _effect_strategy(is_player: bool, n: int) -> String:
	if is_player:
		_bs.player_cost += n
	else:
		_bs.ai_cost += n
	return "전략 점수 +%d" % n


func _effect_attack(n: int, flags: Array, caster: PilotData, enemy_team: int,
		picked: PilotData = null) -> String:
	var t: PilotData = picked
	if t == null or not t.alive or t.team != enemy_team:
		var targets: Array = []
		for raw in _bs.pilots:
			var p := raw as PilotData
			if p.alive and p.team == enemy_team:
				targets.append(p)
		if targets.is_empty():
			return "공격 (대상 없음)"
		t = targets[randi() % targets.size()] as PilotData
	# Damage = 시전자 ATK × value (value is the design unit, e.g. 공격:1 → 1×ATK).
	# Mech ATK was scaled ×20 in the DB so a 1×ATK card hit lands at a meaningful
	# share of pilot HP without a separate placeholder multiplier. Caster falls
	# back to a flat 100 only when the card has no owner_pilot (legacy paths).
	var atk_value: int = caster.atk if caster != null else 100
	var dmg: int = max(1, atk_value * n)
	# 보호막 absorbs first, HP next.
	if t.shield > 0:
		var absorbed: int = min(t.shield, dmg)
		t.shield -= absorbed
		dmg -= absorbed
	if dmg > 0:
		t.hp = max(0, t.hp - dmg)
	if t.hp <= 0:
		t.alive = false
		t.respawn_timer = _bs.RESPAWN_TURNS
	elif dmg > 0:
		_bs.anim_pilot_shake(t)
	var pierce: bool = "pierce" in flags
	var tag: String = " (필중)" if pierce else ""
	return "공격%s %s -%d HP" % [tag, _bs.pilot_label(t), dmg]


func _effect_advance(steps: int, caster: PilotData) -> String:
	# 전진 — 시전자가 자기 레인을 따라 한 칸 전진하며, 도달한 셀에서 기존
	# 레인 푸시 룰(파일럿 vs 파일럿, 같은 레인 타워 공격/방어)이 즉시
	# 적용된다. SimulationCore.advance_pilot 가 이동/전투 한 틱을
	# 캐스터 한 명에 대해서만 실행한다.
	if caster == null or steps <= 0:
		return "전진 (시전자 없음)"
	if not caster.alive:
		return "전진 (시전자 사망)"
	var log_lines: Array = []
	_bs.sim_core.advance_pilot(caster, steps, log_lines)
	var tag: String = ""
	if not log_lines.is_empty():
		tag = " · " + ", ".join(log_lines)
	return "전진 %d%s" % [steps, tag]


func _effect_engage(rounds: int, flags: Array, caster: PilotData,
		is_player: bool) -> String:
	# 시전자 없는 카드(레거시 fallback)는 전투 자체가 의미가 없음. 이 경우는
	# 효과 체인 줄에 안내만 남기고 통과.
	if caster == null or rounds <= 0:
		return "전투 개시 (시전자 없음)"
	var exclude_lane: bool = "exclude_lane" in flags
	# Both player and AI plays open the modal so the engage is visible —
	# AiCardPlayer awaits engage_finished between AI plays so the
	# back-to-back animations don't stomp each other.
	_bs.engage_phase.start_engage(caster, rounds, exclude_lane,
			Callable(self, "_on_engage_finished"))
	var tag: String = " (레인 제외)" if exclude_lane else ""
	var who: String = "" if is_player else " (AI)"
	return "전투 개시 %d라운드%s%s" % [rounds, tag, who]


# Engage 모달이 닫힌 직후 호출. 사망자가 생겼을 수 있고, 보호막/HP 가
# 변동했을 수 있으므로 hand 의 affordable 표시를 다시 그려준다. 게임
# 페이즈는 EngagePhaseManager 가 이미 CARD_PHASE 로 되돌린 뒤다.
func _on_engage_finished() -> void:
	highlight_affordable_cards()
	_bs.hud.update_hud()
	_bs.renderer.queue_redraw()


func _effect_shield_pct(pct: int, ally_team: int,
		picked: PilotData = null) -> String:
	var t: PilotData = picked
	if t == null or not t.alive or t.team != ally_team:
		t = null
		for raw in _bs.pilots:
			var p := raw as PilotData
			if p.alive and p.team == ally_team:
				if t == null or p.hp < t.hp:
					t = p
	if t == null:
		return "보호막 (대상 없음)"
	var amount: int = int(t.max_hp * pct / 100)
	t.shield += amount
	return "보호막 +%d %s" % [amount, _bs.pilot_label(t)]


func _effect_recall_ally(ally_team: int,
		picked: PilotData = null) -> String:
	var t: PilotData = picked
	if t == null or not t.alive or t.team != ally_team:
		t = null
		for raw in _bs.pilots:
			var p := raw as PilotData
			if p.alive and p.team == ally_team:
				if t == null or p.hp < t.hp:
					t = p
	if t == null:
		return "복귀 (대상 없음)"
	var orig := t.grid_pos
	t.grid_pos = _bs.PLAYER_HQ_POS if ally_team == 0 else _bs.ENEMY_HQ_POS
	t.hp       = t.max_hp
	t.shield   = 0   # 본진 복귀 시 보호막 제거
	t.waypoint_idx = 0
	_bs.anim_pilot_recall(t, orig)
	return "복귀 %s" % _bs.pilot_label(t)


# 결투 — opens an engage modal restricted to caster + picked enemy. Runs to
# the first KO (engage stops as soon as one side is empty; we set
# rounds_total to a large value so the round cap effectively never matters).
func _effect_duel(caster: PilotData, picked: PilotData,
		is_player: bool) -> String:
	if caster == null or picked == null:
		return "결투 (대상 없음)"
	_bs.engage_phase.start_duel(caster, picked,
			Callable(self, "_on_engage_finished"))
	var who: String = "" if is_player else " (AI)"
	return "결투 %s → %s%s" % [_bs.pilot_label(caster),
			_bs.pilot_label(picked), who]


# 이동 — teleports the caster onto the picked cell. The location overlay's
# _compute_valid_location_targets already validates the cell against
# cast_range; we just commit the new grid_pos and play the tween. If the
# pilot lands inside a jungle/neutral cell, RecallSystem.process_phase_end_recalls
# will pull them back to HQ at end of 작전 단계 — that's the existing
# displacement rule, not a move-card bug.
func _effect_move(caster: PilotData, picked: Variant) -> String:
	if not (picked is Vector2i) or caster == null:
		return "이동 (대상 없음)"
	var cell := picked as Vector2i
	if cell == caster.grid_pos:
		return "이동 %s (제자리)" % _bs.pilot_label(caster)
	var orig := caster.grid_pos
	caster.grid_pos = cell
	_bs.anim_pilot_move(caster, orig)
	return "이동 %s → (%d,%d)" % [_bs.pilot_label(caster), cell.x, cell.y]


# 약탈 — flip an enemy-owned jungle cell to the caster's team for `turns`
# turns. Cell must already be a jungle/neutral cell currently owned by the
# enemy team. SimulationCore restores the previous owner once
# turn_count >= expires_turn.
func _effect_capture_jungle(turns: int, picked: Variant,
		caster: PilotData) -> String:
	if not (picked is Vector2i) or caster == null:
		return "정글 점령 (대상 없음)"
	var cell := picked as Vector2i
	if not _bs.neutral_zone_cells.has(cell):
		return "정글 점령 실패 (정글 아님)"
	var prev_owner: int = int(_bs.neutral_zone_cells[cell])
	if prev_owner == caster.team:
		return "정글 점령 실패 (이미 아군 소유)"
	_bs.sim_core.set_zone_cell(cell, caster.team)
	_bs.temp_zone_overrides.append({
		"cell": cell,
		"prev_owner": prev_owner,
		"expires_turn": _bs.turn_count + turns,
	})
	return "정글 점령 (%d,%d) %d턴" % [cell.x, cell.y, turns]


# 사전 준비 — hand-wide cost reduction. Mutates every current hand card's
# cost in place; the played card is already gone from hand by the time we
# get here so it's not affected.
func _effect_cost_reduce_hand(n: int, is_player: bool) -> String:
	if n <= 0:
		return ""
	var hand: Array = _bs.player_hand if is_player else _bs.ai_hand
	for raw in hand:
		var c := raw as CardData
		if c == null: continue
		c.cost = max(0, c.cost - n)
	return "핸드 카드 비용 -%d" % n


# 전투 준비 — one-shot pending discount on the caster side's next engage
# card. Consumed in _play_card_direct (player) and AiCardPlayer.run_ai_plays.
func _effect_cost_reduce_engage(n: int, is_player: bool) -> String:
	if n <= 0:
		return ""
	if is_player:
		_bs.engage_discount_p += n
	else:
		_bs.engage_discount_ai += n
	return "다음 전투개시 비용 -%d" % n


# 집중 — phase-bound discount applied to every card drawn during the
# current 작전 단계 (and any subsequent phase until end_card_phase resets).
# Stacks additively if played multiple times in the same phase.
func _effect_cost_reduce_draw_phase(n: int, is_player: bool) -> String:
	if n <= 0:
		return ""
	if is_player:
		_bs.phase_draw_discount_p += n
	else:
		_bs.phase_draw_discount_ai += n
	return "이번 단계 드로우 카드 비용 -%d" % n


# 정밀 이동 (return_left) 카드의 부수 효과 — phase-bound additive cost
# bump on every card play during the current 작전 단계. Consumed by
# effective_cost_for; reset on phase entry.
func _effect_cost_inc_phase(n: int, is_player: bool) -> String:
	if n <= 0:
		return ""
	if is_player:
		_bs.phase_cost_inc_p += n
	else:
		_bs.phase_cost_inc_ai += n
	return "이번 단계 비용 +%d" % n


func _effect_exhaust_choice(is_player: bool, n: int) -> String:
	# UI selection not built yet — exhaust N random hand cards.
	var hand: Array = _bs.player_hand if is_player else _bs.ai_hand
	var removed: int = 0
	for i in n:
		if hand.is_empty():
			break
		var pick := hand[randi() % hand.size()] as CardData
		hand.erase(pick)
		if is_player:
			_despawn_player_card_node(pick)
		removed += 1
	if is_player:
		relayout_hand(_bs.player_card_nodes)
	else:
		_bs.hud.update_ai_hand_visuals()
	return "소멸 %d" % removed


func _despawn_player_card_node(cd: CardData) -> void:
	for node in _bs.player_card_nodes:
		var c := node as Card
		if c.data == cd:
			_bs.player_card_nodes.erase(c)
			c.queue_free()
			return
