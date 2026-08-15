class_name CardPhaseManager
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim

# Hand layout uses BS_HAND_WIDTH (inner) + BS_HAND_CARD_GAP (target gap) for
# adaptive spacing.

# ─── Click-to-select state ────────────────────────────────────────────────────
# When a card is clicked it pops up by Card.PRESS_LIFT, gets brought to the top
# of the scene tree, and a description box appears next to it. Selecting IS the
# targeting step — there is no "카드 내기" button any more; the card is committed
# by 확인 in CardTargetingOverlay (see _on_selection_confirm). The rest of the
# row reflows around the selected card, and clicking outside the card / box
# deselects it.
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

# Set for the whole "상대 차례" — the banner sweep plus AiCardPlayer's async
# play loop (_run_ai_turn) — so the BATTLE auto-tick is held, the player hand
# stays dimmed and a stray button press can't re-enter the routine. Cleared
# once the await chain unwinds.
var _ai_play_in_progress: bool = false

# 완벽한 마무리(`end_phase`)가 세워 놓는 요청 플래그. 한 번에 한 쪽만 자기
# 작전 단계를 갖고 있으므로 양 팀이 공유해도 충돌하지 않는다 — 세운 쪽이
# 그 턴 안에 `consume_end_phase_request()` 로 받아 간다.
var _end_phase_requested: bool = false

# True while the "당신의 차례" banner is sweeping in / holding / fading out.
# The hand stays dimmed and clicks are blocked until it clears so the player
# can't pre-empt the announcement.
var _player_turn_announce_in_progress: bool = false

# 마지막으로 차례를 잡은 팀 (0 = 플레이어, 1 = AI, -1 = 아직 아무도 안 잡음).
# 양 팀이 동시에 문턱 위에 있을 때 교대를 강제하는 유일한 상태 — 자세한 규칙은
# _next_turn_side() 주석 참조. 새 판마다 build_starter_decks 가 -1 로 되돌린다.
var _last_turn_side: int = -1

# 연속 공격(`attack:N|repeat`)이 명중을 이어갈 때 한 번의 사용으로 허용되는
# 최대 타수. 확률상 거의 닿지 않지만 무한 루프를 구조적으로 막는 상한이다.
const MAX_ATTACK_REPEATS: int = 5

# ─── Deck setup ───────────────────────────────────────────────────────────────
# Per-pilot 6-card draw: every pilot pulls 6 cards from the DB pool and tags them
# with itself as the 시전자. All 5 pilots' stacks shuffle together into the team
# deck — same logic for player and AI sides. Deck size is 5 × 6 = 30 per side.
#
# The 6 split into two halves that are drawn from different pools:
#   • 메크 카드 3장 — `card_type = mech` (공격 / 전진 / 전투 개시 / 보호 …)
#   • 파일럿 카드 3장 — `card_type = pilot`, and *which* 3 depends on the role:
#       정글러      → 정글 2 + 드로우 1
#       서포터      → 라인전 1 + 드로우 2
#       그 외 3인   → 라인전 2 + 드로우 1
const MECH_CARDS_PER_PILOT:  int = 3
const PILOT_CARDS_PER_PILOT: int = 3


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
	# 개시 손패를 돌리기 전에 이전 판의 손패를 확실히 비운다. 재시작 경로는
	# 이미 비우고 들어오지만, 여기서 손패가 비어 있다는 것이 개시 배분의 전제다.
	_clear_hands()
	# 차례 교대 기록도 새 판에서는 백지 — 첫 선은 블루가 잡는다.
	_last_turn_side = -1
	_deal_initial_hands()


# Deals every pilot in `pilots` its 6-card stack out of `pool`, stamping each
# copy with that pilot as 시전자. Appends all copies to `out_deck`.
#
# Two filters stack here and they answer different questions:
#   • `CardData.scope` — **who may own this card**. A 정글러 never draws a
#     lane-only card (전진 …) and a 레인 파일럿 never draws a jungle-only one
#     (약탈 …). Filtering at deal time rather than at play time is what keeps the
#     rule invisible: the 시전자 never changes after the deal, so a mis-owned card
#     would sit in the hand permanently locked.
#   • `CardData.card_cat` — **which deck slot this card can fill**. That is the
#     role-dependent 라인전 / 드로우 / 정글 split above.
#
# Each slot pool is sampled **without replacement**, unlike the old flat random
# draw. The 라인전 pool holds 3 cards and the slot asks for 2 of them; with
# replacement the same card came up twice more often than not.
func _deal_team_deck(pool: Array, pilots: Array, out_deck: Array) -> void:
	if pool.is_empty():
		return
	for raw in pilots:
		var p := raw as PilotData
		var eligible := _pool_for_pilot(pool, p)
		if eligible.is_empty():
			continue
		var picks: Array = _sample(_cards_of_type(eligible, CardData.TYPE_MECH),
				MECH_CARDS_PER_PILOT, eligible)
		for slot in _pilot_slots_for(p):
			var cat: String = String(slot[0])
			var count: int  = int(slot[1])
			picks.append_array(_sample(
					_cards_in_category(eligible, cat), count, eligible))
		for src_raw in picks:
			var copy := make_card_copy(src_raw as CardData)
			copy.owner_pilot = p
			out_deck.append(copy)


## The 파일럿 카드 slot table for one pilot: `[[category, count], …]` summing to
## `PILOT_CARDS_PER_PILOT`. Role is read the same way the rest of the sim reads
## it — `is_guerrilla` for the jungler, `role` for the supporter.
func _pilot_slots_for(p: PilotData) -> Array:
	if p.is_guerrilla:
		return [[CardData.CAT_JUNGLE, 2], [CardData.CAT_DRAW, 1]]
	if p.role == GameEnums.Role.SUPPORT:
		return [[CardData.CAT_LANE, 1], [CardData.CAT_DRAW, 2]]
	return [[CardData.CAT_LANE, 2], [CardData.CAT_DRAW, 1]]


func _cards_of_type(pool: Array, card_type: String) -> Array:
	var out: Array = []
	for raw in pool:
		if (raw as CardData).card_type == card_type:
			out.append(raw)
	return out


## Pilot cards eligible for the `cat` slot. `CAT_COMMON` cards (복귀) answer for
## both the 라인전 and the 정글 slot — see `CardData.fits_category`.
func _cards_in_category(pool: Array, cat: String) -> Array:
	var out: Array = []
	for raw in pool:
		var cd := raw as CardData
		if cd.card_type == CardData.TYPE_PILOT and cd.fits_category(cat):
			out.append(cd)
	return out


## `n` distinct cards out of `src`, order randomised.
##
## Two fallbacks keep a thin CSV from ever producing a short deck: an empty
## `src` falls back to `fallback` (the pilot's whole scope-filtered pool), and a
## pool smaller than `n` is topped up with repeats. Deck size is a hard invariant
## — 5 pilots × 6 cards — and a mis-tagged `card_cat` must not silently break it.
func _sample(src: Array, n: int, fallback: Array) -> Array:
	if n <= 0:
		return []
	var bag: Array = (src if not src.is_empty() else fallback).duplicate()
	if bag.is_empty():
		return []
	bag.shuffle()
	var out: Array = []
	while out.size() < n:
		if bag.is_empty():
			# Pool smaller than the slot asks for — refill and allow repeats.
			bag = (src if not src.is_empty() else fallback).duplicate()
			bag.shuffle()
		out.append(bag.pop_back())
	return out


## Empties both hands and frees the player's card nodes, so `_deal_initial_hands`
## can assume it is dealing into an empty hand. `_on_restart_pressed` already
## does this on its way in; this keeps the precondition local to the deal.
func _clear_hands() -> void:
	for node in _bs.player_card_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_bs.player_card_nodes.clear()
	_bs.player_hand.clear()
	_bs.ai_hand.clear()


## 개시 손패 — 양 팀에 `INITIAL_HAND_SIZE` 장씩 미리 돌린다.
##
## 이게 없으면 양 팀 다 **빈 손**으로 시작해, 첫 차례가 오는 시점의 손패가
## 그때까지 지나간 자동 드로우 횟수(CARD_DRAW_INTERVAL 에 묶인 수)로만
## 결정된다 — 상한 `MAX_HAND_SIZE` 에 한참 못 미치는 손으로 첫 작전 단계를
## 맞게 된다는 뜻이다. 개시 배분은 그 격차를 메워, 첫 차례를 거의 꽉 찬 손으로
## 시작하게 한다.
##
## `MAX_HAND_SIZE` 보다 훨씬 작은 장수이므로 `_trim_hand_overflow` 는 돌리지
## 않는다. 덱이 마르면 `draw_card` 가 null 을 돌려주고 그 자리에서 멈춘다.
func _deal_initial_hands() -> void:
	for _i in range(_bs.INITIAL_HAND_SIZE):
		var drawn := draw_card(true)
		if drawn != null:
			spawn_card_node(drawn)
		draw_card(false)
	if _bs.hud != null:
		_bs.hud.update_ai_hand_visuals()


## Subset of `pool` this pilot is allowed to own. Falls back to the unfiltered
## pool if the scope filter leaves nothing at all, so a mis-tagged CSV can never
## hand a pilot an empty mini-deck.
func _pool_for_pilot(pool: Array, p: PilotData) -> Array:
	var out: Array = []
	for raw in pool:
		var cd := raw as CardData
		if cd.allowed_for_guerrilla(p.is_guerrilla):
			out.append(cd)
	return out if not out.is_empty() else pool


func _team_pilots(team: int) -> Array:
	var out: Array = []
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.team == team:
			out.append(p)
	return out


# Every card the random starter-deck deal may draw from. Rows flagged
# `pool = 0` in cards.csv are skipped here: they exist in the DB (and stay
# playable through whatever future path grants them — 결투 is slated to become a
# mech-unique card) but nothing hands them out at random.
func _build_pool_from_db() -> Array:
	var gm: Node = _bs.gm
	if gm != null and not gm.card_pool_bs.is_empty():
		var pool: Array = []
		for card_def in gm.card_pool_bs:
			if int(card_def.get("pool", 1)) == 0:
				continue
			pool.append(_make_card_from_def(card_def))
		if not pool.is_empty():
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
	cd.scope       = String(def.get("scope", CardData.SCOPE_ANY))
	cd.pool        = int(def.get("pool", 1))
	cd.card_type   = String(def.get("card_type", CardData.TYPE_MECH))
	cd.card_cat    = String(def.get("card_cat", CardData.CAT_NONE))
	return cd


# Copies a CardData (so each draw is a unique instance) including the 시전자 tag.
func make_card_copy(src: CardData) -> CardData:
	var cd := CardData.new(src.card_name, src.cost, src.description)
	cd.uses        = src.uses
	cd.cast_method = src.cast_method
	cd.target      = src.target
	cd.cast_range  = src.cast_range
	cd.area        = src.area
	cd.keyword     = src.keyword
	cd.effect      = src.effect
	cd.scope       = src.scope
	cd.pool        = src.pool
	cd.card_type   = src.card_type
	cd.card_cat    = src.card_cat
	cd.owner_pilot = src.owner_pilot
	return cd


# ─── Turn flow ────────────────────────────────────────────────────────────────
func do_battle_turn() -> void:
	if _bs.game_over or _bs.game_phase != GameEnums.BattlePhase.BATTLE:
		return
	# An AI turn unfolds *inside* BATTLE (see _run_ai_turn) and awaits its card
	# animations, so the auto-tick has to stay out until it unwinds. BattleSim
	# already holds the tick via is_ai_turn_active(); this is the backstop.
	if _ai_play_in_progress:
		return
	_bs.sim_core.simulate_turn()
	if _bs.game_over:
		return
	# 카드 경제 게이트. `ECONOMY_START_TURN` 전까지는 전략 점수도 자동 드로우도
	# 멈춰 있다 — 개시 손패 5장과 블루 선점 1점만 들고 초반 몇 턴을 라인전으로
	# 보내라는 규칙이다. 카운터 자체를 굴리지 않으므로 게이트가 풀리는 턴에
	# 밀린 회복이 한꺼번에 터지지도 않는다.
	#
	# `simulate_turn()` 이 자기 초입에서 `turn_count` 를 올리므로, 이 시점의
	# `turn_count` 는 **방금 끝난 턴의 번호**(1-based)다. 카운터는 개시 시
	# `INTERVAL - 1` 로 놓여 있어 게이트가 열리는 첫 턴에 곧바로 발동한다 —
	# ECONOMY_START_TURN = 4 면 4턴째에 첫 회복 / 첫 드로우가 들어간다.
	if _bs.turn_count >= _bs.ECONOMY_START_TURN:
		_bs.cost_counter += 1
		if _bs.cost_counter >= _bs.COST_RECOVERY_INTERVAL:
			_bs.cost_counter = 0
			_bs.player_cost += _bs.COST_RECOVERY
			_bs.ai_cost     += _bs.COST_RECOVERY
		_bs.draw_counter += 1
		if _bs.draw_counter >= _bs.CARD_DRAW_INTERVAL:
			_bs.draw_counter = 0
			# These are the "waiting for my turn" draws — the ones that tick by
			# while 작전 점수 climbs back to PHASE_THRESHOLD. They always draw,
			# even on a full hand, and the overflow is paid for by discarding the
			# OLDEST cards. Skipping the draw instead (the old rule) stalled the
			# deck and left the same dead hand sitting there for the whole wait.
			var drawn := draw_card(true)
			if drawn != null:
				spawn_card_node(drawn)
			_trim_hand_overflow(true)
			# AI hand visuals (face-down card backs) live in HudBuilder; the row
			# reflows after the draw so the count peek matches state.
			draw_card(false)
			_trim_hand_overflow(false)
			_bs.hud.update_ai_hand_visuals()
	# Whose turn is it now? Each side gets its turn the moment *its own* 작전
	# 점수 reaches PHASE_THRESHOLD — the AI's turn is no longer bolted onto the
	# end of the player's, so the "상대 차례" banner only ever shows when the AI
	# actually acts. `_next_turn_side` owns the arbitration when both are ready.
	var turn_side := _next_turn_side()
	if turn_side == 1:
		_last_turn_side = 1
		await _run_ai_turn()
	elif turn_side == 0:
		_last_turn_side = 0
		start_card_phase()
	else:
		# Respawn countdowns on the hand cards tick with the battle turn, so the
		# card faces have to be re-read every tick, not just on phase entry.
		highlight_affordable_cards()
		_bs.renderer.queue_redraw()
		_bs.hud.update_hud()


## 이번 틱에 차례를 가져갈 팀 — 0 = 플레이어, 1 = AI, -1 = 아무도 준비되지 않음.
##
## 규칙은 두 줄이다.
##   1. 한 쪽만 준비됐으면 그 쪽이 잡는다.
##   2. 양쪽 다 준비됐으면 **직전에 차례를 잡지 않은 쪽**이 잡고, 아직 아무도
##      잡은 적이 없으면 블루(`_bs.blue_team`)가 잡는다.
##
## 두 번째 줄이 두 가지를 한꺼번에 책임진다.
##
## **같은 점수면 블루 먼저.** 개시 직후에는 `_last_turn_side` 가 -1 이라 블루가
## 무조건 선을 잡는다. 점수 선점(`BattleSim.BLUE_COST_HEAD_START`)만으로도
## 보통은 블루가 문턱에 먼저 닿지만, 카드로 점수를 쓴 뒤 양쪽이 같은 틱에
## 다시 닿는 경우의 타이브레이크는 이 규칙이 맡는다.
##
## **굶주림 방지.** 예전 코드는 이 자리에서 AI 를 **무조건 먼저** 검사해
## 굶주림을 막았다 — 0코스트 카드만 내고 턴을 넘긴 플레이어는 다음 틱에도
## 점수가 문턱 위로 남아 자기 단계에 재진입하고, 그렇게 AI 를 영원히 굶길 수
## 있기 때문이다. 블루 우선으로 뒤집으면 그 방어가 사라지므로, 대신 교대
## 규칙이 그 자리를 메운다: 방금 차례를 잡은 쪽은 상대가 한 번 잡기 전까지
## 다시 잡지 못한다. 상대가 문턱 아래라면 교대할 상대가 없으므로 연속 진입이
## 그대로 허용된다(규칙 1).
##
## 준비 판정이 양쪽 비대칭인 것은 의도된 기존 동작이다. AI 는 낼 수 있는 카드가
## 손에 있어야 준비된 것으로 치고(`_ai_turn_ready`), 플레이어는 점수만 차면
## 진입한다 — 낼 게 없는 손은 `can_end_card_phase` 의 탈출구가 통과시킨다.
func _next_turn_side() -> int:
	var player_ready: bool = _bs.player_cost >= _bs.PHASE_THRESHOLD
	var ai_ready: bool = _ai_turn_ready()
	if player_ready and ai_ready:
		return _bs.blue_team if _last_turn_side == -1 else 1 - _last_turn_side
	if player_ready:
		return 0
	if ai_ready:
		return 1
	return -1


## Discards from the **front** of `hand` (oldest first) until it is back down to
## MAX_HAND_SIZE, returning how many were dropped.
##
## Only the BATTLE-phase auto-draw calls this. Cards drawn by a card effect
## during 작전 단계 are the player's own turn and are left alone even when they
## push the hand over the cap — the next auto-draw after the turn ends is what
## trims the excess.
##
## 계획 중시(`preserve:N`)로 보존된 카드는 **건너뛴다** — 그게 그 카드의 유일한
## 효과다. 손패가 통째로 보존되는 경우(최대 2장이라 실제로는 불가능)에도
## 루프가 멈추도록 인덱스 스캔으로 돈다: 상한 초과가 남아도 무한 루프는 없다.
func _trim_hand_overflow(is_player: bool) -> int:
	var hand:    Array = _bs.player_hand    if is_player else _bs.ai_hand
	var discard: Array = _bs.player_discard if is_player else _bs.ai_discard
	_prune_preserved(is_player)
	var preserved: Array = _bs.preserved_cards_p if is_player else _bs.preserved_cards_ai
	var dropped: int = 0
	var i: int = 0
	while hand.size() > _bs.MAX_HAND_SIZE and i < hand.size():
		var oldest := hand[i] as CardData
		if preserved.has(oldest):
			i += 1
			continue
		hand.remove_at(i)
		discard.append(oldest)
		if is_player:
			_despawn_player_card_node(oldest)
		dropped += 1
	if dropped > 0 and is_player:
		relayout_hand(_bs.player_card_nodes)
		update_deck_discard_labels()
	return dropped


## Drops preserve entries whose card has already left the hand (played, forced
## into the discard by another card, trimmed away before it was preserved …).
## Without this the list accumulates dangling CardData and a *different* card
## drawn later could never collide with it — but the list would keep growing for
## the rest of the match. Cheap enough to run on every trim.
func _prune_preserved(is_player: bool) -> void:
	var hand:      Array = _bs.player_hand      if is_player else _bs.ai_hand
	var preserved: Array = _bs.preserved_cards_p if is_player else _bs.preserved_cards_ai
	for i in range(preserved.size() - 1, -1, -1):
		if not hand.has(preserved[i]):
			preserved.remove_at(i)


func start_card_phase() -> void:
	_bs.game_phase = GameEnums.BattlePhase.CARD_PHASE
	_bs.blog.stage("card-phase")
	_bs.blog.log_event("PHASE", "작전 단계 시작 — player %d / ai %d 점"
			% [_bs.player_cost, _bs.ai_cost])
	# The 턴 넘기기 gate counts *cards played*, not points spent — see
	# can_end_card_phase(). Reset it on entry so last phase's plays don't
	# unlock this one.
	_bs.cards_played_this_phase = 0
	# Phase-bound cost modifiers (정밀 이동 / 집중) only live for one
	# 작전 단계; reset on entry so a leftover from a previous phase doesn't
	# persist. engage_discount_* is intentionally NOT reset — 전투 준비 was
	# played in BATTLE phase and should keep its one-shot reduction available
	# for the upcoming engage card.
	_bs.phase_cost_inc_p = 0
	_bs.phase_cost_inc_ai = 0
	_bs.phase_draw_discount_p = 0
	_bs.phase_draw_discount_ai = 0
	_apply_phase_entry_carryovers(true)
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


## 작전 단계 진입 시 정산되는 **지연 효과 세 가지**를 한 곳에서 처리한다.
## 플레이어는 `start_card_phase`, AI 는 `_run_ai_turn` 이 부른다.
##
##  1. 계획 중시의 보존 — 한 번의 BATTLE 구간만 버티는 효과이므로 여기서 걷는다.
##  2. 아드레날린의 다음 단계 전략 점수(음수 가능) — 점수는 0 아래로 안 내려간다.
##  3. 완벽한 마무리의 성장 배율 — "다음 작전 단계까지"가 여기서 끝난다.
func _apply_phase_entry_carryovers(is_player: bool) -> void:
	var team: int = 0 if is_player else 1
	if is_player:
		_bs.preserved_cards_p.clear()
		_bs.player_cost = maxi(0, _bs.player_cost + _bs.next_phase_strategy_p)
		_bs.next_phase_strategy_p = 0
	else:
		_bs.preserved_cards_ai.clear()
		_bs.ai_cost = maxi(0, _bs.ai_cost + _bs.next_phase_strategy_ai)
		_bs.next_phase_strategy_ai = 0
	_bs.sim_core.clear_growth_until_phase(team)


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


# Returns true once the player has played at least one card this 작전 단계.
# Also blocked while a discard / search overlay is mid-resolution so the
# player can't 턴 넘기기 their way out of an unfinished pick.
#
# The gate used to be "player_cost dropped below the phase-entry snapshot",
# which deadlocked the phase outright: 8 of the 20 cards cost 0 (임기응변 /
# 정밀 이동 / 복귀 …), so a hand whose only playable cards were free could
# never lower the cost, the 턴 넘기기 face never enabled, and BATTLE stays
# paused during 작전 단계 — nothing could ever unstick it. Counting *plays*
# keeps the "do something on your turn" intent without the trap.
#
# Second escape hatch: a hand with nothing playable at all (시전자 전멸,
# every card unaffordable, no legal targets) can't satisfy the play rule
# either, and the hand can't change because draws only tick in BATTLE. That
# state passes straight through.
func can_end_card_phase() -> bool:
	if _bs.game_phase != GameEnums.BattlePhase.CARD_PHASE:
		return false
	if _bs.card_select_overlay != null and _bs.card_select_overlay.is_active():
		return false
	# Deck / Discard 목록을 펼쳐 놓은 동안에는 턴을 넘길 수 없다 — 도넛은
	# 열람 딤 아래에 있고, CostDonut._input 은 GUI 픽보다 먼저 돌아 딤을
	# 뚫고 눌리기 때문이다.
	if _bs.card_pile_viewer != null and _bs.card_pile_viewer.is_active():
		return false
	if _ai_play_in_progress:
		return false
	if _player_turn_announce_in_progress:
		return false
	if _bs.cards_played_this_phase > 0:
		return true
	return not _has_any_playable_card()


## True while the player may open the Deck / Discard 목록 (HudBuilder wires the
## two counter buttons to this). 작전 단계 전용 — BATTLE 자동 진행 중이거나
## 차례 배너 / 상대 차례 / 버리기·찾기 오버레이 / 교전 아레나가 화면을 잡고
## 있을 때는 열리지 않는다. 이미 열려 있는 상태는 여기서 보지 않는다 — 열람
## 딤이 카운터 버튼을 덮으므로 그 경로로 다시 눌릴 수가 없다.
func can_browse_piles() -> bool:
	if _bs.game_phase != GameEnums.BattlePhase.CARD_PHASE:
		return false
	if _ai_play_in_progress or _player_turn_announce_in_progress:
		return false
	if _bs.card_select_overlay != null and _bs.card_select_overlay.is_active():
		return false
	if _bs.engage_phase != null and _bs.engage_phase.is_active():
		return false
	return true


# True while at least one card in the player's hand could be committed right
# now (cost, 시전자 생존 and target availability all hold) — i.e. the player
# still has a move to make.
func _has_any_playable_card() -> bool:
	for raw in _bs.player_hand:
		if card_is_playable(raw as CardData):
			return true
	return false


# Ends the *player's* 작전 단계 and hands control straight back to BATTLE.
#
# It does NOT hand over to the AI. The opponent takes its own turn when its own
# 작전 점수 reaches PHASE_THRESHOLD (see _run_ai_turn, driven from
# do_battle_turn), so passing the turn no longer fires a "상대 차례" banner for
# an opponent that has nothing to spend.
func end_card_phase() -> void:
	if not can_end_card_phase():
		return
	# Drop any active card selection so the description box and lifted-card
	# state don't survive across the phase transition.
	deselect_current_card()
	# Phase end: re-evaluate recalls (HP threshold + out-of-position from card effects).
	_bs.blog.stage("phase-end")
	var log_lines: Array = []
	_bs.recall_sys.process_phase_end_recalls(log_lines)
	if not log_lines.is_empty():
		_bs.last_log = log_lines[-1]
	_bs.game_phase = GameEnums.BattlePhase.BATTLE
	# 계획 살인의 예약은 그 작전 단계 안에서만 유효하다 — 안 터졌으면 사라진다.
	_bs.kill_bounty_p = 0
	_bs.blog.log_event("PHASE", "작전 단계 종료 → BATTLE")
	_bs.renderer.queue_redraw()
	_bs.hud.update_hud()
	_apply_hand_dim_state()


## Reads and clears the `end_phase` request. Public so `AiCardPlayer` can break
## its play loop on the same flag the player path consumes in
## `_finalize_pending_play`.
func consume_end_phase_request() -> bool:
	if not _end_phase_requested:
		return false
	_end_phase_requested = false
	return true


# ─── 상대 차례 ────────────────────────────────────────────────────────────────
# True while the AI turn's await chain is in flight. BattleSim reads this to
# hold the BATTLE auto-tick (and the in-game clock) for the duration.
func is_ai_turn_active() -> bool:
	return _ai_play_in_progress


# The AI gets a turn only when it can actually do something with it: 작전 점수
# at the threshold AND at least one card it can pay for. Without the second
# half an AI sitting on a full score with an empty / unaffordable hand would
# re-announce "상대 차례" every single tick and play nothing — the mirror of the
# deadlock `_has_any_playable_card` covers on the player side. The affordability
# test is deliberately the same one AiCardPlayer.run_ai_plays uses, so a turn
# that starts is guaranteed to consume at least one card.
func _ai_turn_ready() -> bool:
	if _bs.ai_card_player == null:
		return false
	if _bs.ai_cost < _bs.PHASE_THRESHOLD:
		return false
	for raw in _bs.ai_hand:
		if _bs.effective_cost_for(raw as CardData, false) <= _bs.ai_cost:
			return true
	return false


# The AI's own 작전 단계. Unlike the player's it never switches game_phase —
# it runs inside BATTLE with the auto-tick held — but it is a real turn: the
# "상대 차례" banner marks its start, AiCardPlayer walks the affordable hand one
# card at a time (awaiting the centre animation and any engage arena), and the
# same phase-end recall sweep the player's turn gets runs on the way out.
func _run_ai_turn() -> void:
	if _ai_play_in_progress:
		return
	_ai_play_in_progress = true
	# The player shouldn't be holding a lifted card here (BATTLE dims the hand),
	# but deselect is idempotent and keeps stray state from crossing the turn.
	deselect_current_card()
	_apply_hand_dim_state()
	_bs.blog.stage("ai-turn")
	_apply_phase_entry_carryovers(false)
	_bs.blog.log_event("PHASE", "상대 차례 시작 — ai %d 점" % _bs.ai_cost)
	_bs.hud.update_hud()
	await _bs.hud.play_turn_announce(false)
	await _bs.ai_card_player.run_ai_plays()
	if not _bs.game_over:
		# Same sweep end_card_phase runs: HP threshold + pilots the AI's cards
		# displaced out of position.
		_bs.blog.stage("ai-turn-end")
		var log_lines: Array = []
		_bs.recall_sys.process_phase_end_recalls(log_lines)
		if not log_lines.is_empty():
			_bs.last_log = log_lines[-1]
	_bs.kill_bounty_ai = 0
	_bs.blog.log_event("PHASE", "상대 차례 종료 → BATTLE")
	_ai_play_in_progress = false
	highlight_affordable_cards()
	_bs.renderer.queue_redraw()
	_bs.hud.update_hud()


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
## Builds the visual node for a card that just entered the player's hand.
##
## `at_left` puts it at the **head** of `player_card_nodes` instead of the tail,
## i.e. the leftmost slot of the fan — `relayout_hand` reads position purely
## from the array index, so this one flag is the whole "손패 맨 왼쪽" rule
## (정밀 이동 / `return_left`). Callers must insert into `_bs.player_hand` at the
## matching end; the two arrays are kept in the same order.
func spawn_card_node(cd: CardData, at_left: bool = false) -> void:
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
	if at_left:
		_bs.player_card_nodes.insert(0, node)
	else:
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
		# 시전자가 쓰러져 있으면 카드도 같이 잠긴다 — 카드 전체가 어두워지고
		# 부활까지 남은 턴이 한가운데 크게 찍힌다.
		c.set_respawn_turns(respawn_turns_for(c.data))
		# 계획 중시로 보존된 카드는 시안 테두리를 두른다 — 사용 가능 여부와는
		# 무관한 별개의 표시라 슬래브와 겹쳐 떠도 서로를 가리지 않는다.
		c.set_preserved(_bs.preserved_cards_p.has(c.data))
		# Reflect any active cost modifier (사전 준비 / 전투 준비 / 집중 /
		# cost_inc_phase) on the card's top-left cost number — green when
		# reduced below the printed cost, red when increased, white when
		# matched. 정밀 이동's +1 is baked into cd.cost by return_left, so a
		# returned card reads white at its new printed price.
		c.update_displayed_cost(eff)
	# Re-evaluate hand dim alongside affordability since both keys off the
	# same "is it the player's turn to act?" question — overlay close paths
	# all funnel through here, so this single call covers them.
	_apply_hand_dim_state()
	# A cost change (or a 시전자 dying mid-selection) can flip the lifted card
	# between playable and not, so the 확인 button re-reads it here too.
	_refresh_confirm_button()


## Turns left until `cd`'s 시전자 comes back on the field, or 0 while they're
## alive (or the card has no owner). 전장을 비우는 사유는 사망뿐이므로 이건 곧
## 부활까지 남은 턴이다 — 본진 복귀한 파일럿은 계속 `alive` 라 카드가 잠기지
## 않는다. `BattleSim.turns_until_return` 은 돌아오기 직전 틱에도 최소 1 을
## 돌려주므로 카드가 깜빡이며 풀리지 않는다.
func respawn_turns_for(cd: CardData) -> int:
	if cd == null:
		return 0
	return _bs.turns_until_return(cd.owner_pilot)


## Can the player commit `cd` right now? Cost, 시전자 생존, and target
## availability all have to hold. Drives the 확인 button's enable state.
func card_is_playable(cd: CardData) -> bool:
	if cd == null:
		return false
	if respawn_turns_for(cd) > 0:
		return false
	if _bs.effective_cost_for(cd, true) > _bs.player_cost:
		return false
	return card_has_valid_targets(cd)


## Pushes the "is the lifted card playable?" verdict into the targeting
## overlay, which ANDs it with "has a target been picked yet?" to decide
## whether 확인 is clickable.
func _refresh_confirm_button() -> void:
	if _bs.targeting_overlay == null:
		return
	if _selected_card == null or not is_instance_valid(_selected_card):
		return
	_bs.targeting_overlay.set_play_allowed(card_is_playable(_selected_card.data))


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
		# Re-clicking the selected card toggles the selection off — the same
		# thing the 취소 button does, and the escape hatch for the targeting
		# kinds whose battlefield clicks the overlay swallows.
		deselect_current_card()
		return
	_select_card(card)


# Player can't pick / hover hand cards while the search-pick modal owns the
# screen or while the AI's async play loop is in flight. The targeting overlay
# is deliberately NOT in this list any more: card selection *is* targeting now,
# so the hand has to stay live for the player to switch to a different card
# mid-pick. Discard mode is the other exception — the overlay's whole job is to
# let the player click hand cards and choose which to throw away, so input goes
# through and the desc-box "버리기" button routes the pick.
func _is_player_input_blocked() -> bool:
	if _ai_play_in_progress:
		return true
	if _player_turn_announce_in_progress:
		return true
	# Deck / Discard 열람 중 — 목록이 화면을 덮고 있으므로 핸드는 딤 상태로.
	if _bs.card_pile_viewer != null and _bs.card_pile_viewer.is_active():
		return true
	if _bs.card_select_overlay != null and _bs.card_select_overlay.is_active():
		if _bs.card_select_overlay.is_discard_mode():
			return false
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	# Outside-click / outside-touch dismisses the active selection. Card,
	# description box, and buttons each accept their own events, so anything
	# reaching this handler is by definition outside all of them.
	#
	# PILOT / LOCATION selections never get here: CardTargetingOverlay runs its
	# _unhandled_input first (it is added to BattleSim after CardPhaseManager,
	# and unhandled input walks the tree back-to-front) and marks every
	# battlefield press handled, hit or miss — otherwise a tap 5 px off a pilot
	# marker would silently throw away the pick. Those kinds exit via 취소, a
	# re-click on the card, or by selecting a different card.
	if _selected_card == null:
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
	# Selecting a card IS the targeting step: the cast range lights up, out-of-
	# range tiles dim, and 확인 / 취소 appear bottom-left. Still non-modal — the
	# hand and 턴 넘기기 stay live. Skipped while a 버리기 overlay owns the hand,
	# where the desc-box "버리기" button is the only action a card can take.
	if _bs.targeting_overlay != null and not _in_discard_pick_mode():
		_bs.targeting_overlay.start_card_selection(card.data,
				Callable(self, "_on_selection_confirm"),
				Callable(self, "_on_selection_cancel"))
		_refresh_confirm_button()


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
	# Drop the range / area visualization and the 확인 / 취소 row that
	# _select_card put up. Nothing to refund — no cost was spent yet.
	if _bs.targeting_overlay != null:
		_bs.targeting_overlay.clear_selection()


## True while a 버리기:N pick overlay owns the hand. In that state a card click
## opens the description box with a "버리기" button instead of entering the
## normal targeting/확인 flow.
func _in_discard_pick_mode() -> bool:
	return _bs.card_select_overlay != null \
			and _bs.card_select_overlay.is_discard_mode()


# ─── Selection confirm / cancel (from CardTargetingOverlay) ──────────────────
## 확인 pressed. `picked` is the resolved target — PilotData for PILOT,
## Vector2i for LOCATION, null for PREVIEW / INSTANT cards. Only now is the
## cost deducted and the card consumed.
func _on_selection_confirm(picked: Variant) -> void:
	if _selected_card == null or not is_instance_valid(_selected_card):
		return
	var card := _selected_card
	# Re-check rather than trusting the button state: a battle tick can't fire
	# during 작전 단계, but an engage resolved from an earlier card in the same
	# phase can have killed the 시전자 or drained the points since.
	if not card_is_playable(card.data):
		return
	# Tear down selection state BEFORE handing the node to the play path, which
	# frees it — the dangling reference must never escape this function.
	_hide_description_box()
	_selected_card = null
	_play_card_direct(card, picked)


## 취소 pressed. The card is still in hand and no cost has moved, so this is
## just a deselect. The overlay has already torn itself down by this point;
## clear_selection() inside deselect_current_card is a no-op.
func _on_selection_cancel() -> void:
	deselect_current_card()


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

	# The old "카드 내기" button is gone — committing a card is now the 확인
	# button that CardTargetingOverlay parks at the bottom-left, so the play
	# action lives in one place whether or not the card needs a target. The
	# only button this box still owns is the 버리기:N pick action, which has
	# nothing to do with playing a card. is_discard_mode() (not
	# can_pick_for_discard) decides whether it appears, so the button stays
	# visible-but-disabled while the overlay's 숨김 state is on.
	if _in_discard_pick_mode():
		_play_button = Button.new()
		_play_button.add_theme_font_size_override("font_size", 22)
		_play_button.custom_minimum_size = Vector2(0.0, 52.0)
		_play_button.text = "버리기"
		_play_button.disabled = not _bs.card_select_overlay.can_pick_for_discard()
		_play_button.pressed.connect(_on_discard_selected_pressed)
		vbox.add_child(_play_button)

	_bs.canvas.add_child(box)
	_description_box = box


func _hide_description_box() -> void:
	if _description_box != null and is_instance_valid(_description_box):
		_description_box.queue_free()
	_description_box = null
	_play_button = null


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


# Player play path, entered only from 확인 — by which point the target (if the
# card wanted one) is already resolved, so nothing here opens a picker.
#
# Snapshots the pre-play state up front so a 버리기 / 찾기 clause inside the
# effect chain can fully roll back on cancel — even when earlier clauses (e.g.
# draw:2 inside a draw:2;discard:2 card) already mutated the hand. The chain
# runs to completion synchronously unless it hits a clause that hands off to
# CardSelectOverlay, in which case _process_pending_chain returns early and the
# overlay's complete / cancel callback resumes us.
#
# `pre_target` is PilotData (PILOT), Vector2i (LOCATION), or null.
func _play_card_direct(card: Card, pre_target: Variant = null) -> void:
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
		# 계획 중시가 체인 중간에서 취소되면 이미 올라간 보존 표시도 되돌린다.
		"preserved": _bs.preserved_cards_p.duplicate(),
	}
	var eff_cost: int = _bs.effective_cost_for(cd, true)
	_bs.blog.log_event("CARD", "PLAYER plays [%s] cost=%d effect=%s target=%s" % [
			cd.card_name, eff_cost, cd.effect, _target_str(pre_target)])
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
		# Resolved during the selection step; null for cards that don't need a
		# target. Effect handlers consult this when wiring damage / heals /
		# location effects.
		"target":     pre_target,
	}
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
	match targeting_kind(cd):
		"pilot":
			if caster == null:
				return false
			var team_filter: int = 1 if cd.target == "enemy" else 0
			return not compute_valid_pilot_targets(cd, caster, team_filter).is_empty()
		"location":
			if caster == null:
				return false
			return not compute_valid_location_targets(cd, caster).is_empty()
		"preview":
			# engage — require at least one alive participant from each
			# side inside the caster's area so start_engage doesn't no-op.
			if caster == null:
				return false
			var area := compute_engage_area(caster)
			var exclude_lane: bool = has_clause_flag(cd.effect, "engage", "exclude_lane")
			var participants := compute_engage_participants(caster, area, exclude_lane)
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
func targeting_kind(cd: CardData) -> String:
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
func compute_valid_pilot_targets(cd: CardData, caster: PilotData,
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


# Cells within hex range of caster (alive cells only). 약탈 (capture_jungle)
# runs on its own rule set — see compute_capture_jungle_targets.
func compute_valid_location_targets(cd: CardData, caster: PilotData) -> Array:
	var out: Array = []
	if caster == null:
		return out
	# Inspect the effect chain for clauses that constrain the legal set.
	for clause in _parse_effect_chain(cd.effect):
		var cname: String = String(clause.get("name", ""))
		if cname == "capture_jungle":
			return compute_capture_jungle_targets(caster)
		if cname == "move" and "own_jungle" in (clause.get("flags", []) as Array):
			return compute_own_jungle_targets(caster)
	var max_r: int = max(1, cd.cast_range)
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
			out.append(c)
	return out


# 약탈의 유효 대상 — **적 팀이 소유한 정글 셀 중, 시전자 팀이 소유한 정글 셀과
# 인접한 것**. 시전자 사거리는 보지 않는다(카드의 cast_range 는 99).
#
# 예전에는 "사거리(1) 안의 적 소유 정글 셀"이었는데, 정글은 레인에서 떨어져
# 있고 레인 파일럿은 정글 셀에 들어가지도 못하므로 유효 대상이 사실상 항상
# 비어 있었다 — card_has_valid_targets 가 false 를 돌려주니 카드가 영영
# 사용 불가였다. 전선을 자기 정글에서 한 칸씩 밀어 나가는 규칙으로 바꾸면
# 시전자가 어디 있든 최소한 한 칸은 열려 있다.
func compute_capture_jungle_targets(caster: PilotData) -> Array:
	var out: Array = []
	if caster == null:
		return out
	var zones: Dictionary = _bs.neutral_zone_cells
	var enemy_team: int = 1 - caster.team
	for raw_cell in zones.keys():
		var cell := raw_cell as Vector2i
		if int(zones[cell]) != enemy_team:
			continue
		for n in _bs.hex_grid.get_neighbors(cell.x, cell.y):
			var nb := n as Vector2i
			if not zones.has(nb):
				continue
			if int(zones[nb]) == caster.team:
				out.append(cell)
				break
	return out


# 정글 파밍(`move|own_jungle`)의 유효 대상 — **시전자 팀이 소유한 정글 셀**
# 전부. 약탈과 마찬가지로 `cast_range` 는 보지 않는다(카드의 cast_range 는 99):
# 정글러는 자기 정글 어디로든 붙을 수 있어야 하고, 사거리로 묶으면 정글 반대편
# 캠프가 영영 닿지 않는다. 제자리 셀은 뺀다 — 이동이 no-op 이 되기 때문.
#
# 소유 판정은 `neutral_zone_cells` 를 그대로 읽으므로 약탈이 걸어 둔 임시 점령
# (`temp_zone_overrides`)도 자동으로 반영된다 — 그 카드가 소유 맵 자체를 바꾼다.
func compute_own_jungle_targets(caster: PilotData) -> Array:
	var out: Array = []
	if caster == null:
		return out
	var zones: Dictionary = _bs.neutral_zone_cells
	for raw_cell in zones.keys():
		var cell := raw_cell as Vector2i
		if int(zones[cell]) != caster.team:
			continue
		if cell == caster.grid_pos:
			continue
		out.append(cell)
	return out


# Caster cell + all 6 neighbours, mirroring EngagePhaseManager._gather_participants.
func compute_engage_area(caster: PilotData) -> Array:
	var out: Array = [caster.grid_pos]
	for n in _bs.hex_grid.get_neighbors(caster.grid_pos.x, caster.grid_pos.y):
		out.append(n)
	return out


# Pilots in the engage area that would actually fight. Mirrors EngagePhaseManager
# rules including the exclude_lane filter for the 교전 card.
func compute_engage_participants(caster: PilotData, area: Array,
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
func has_clause_flag(effect_chain: String, clause_name: String,
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
		if ename == "preserve":
			_pending_play["clauses"] = clauses
			_bs.card_select_overlay.start_preserve(n,
					_on_preserve_overlay_complete,
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


# Search complete: the picks are still in the deck — move them to the hand and
# resume the chain. Like 드로우:N, a 찾기 resolved during 작전 단계 may overfill
# the hand; the next BATTLE auto-draw trims it back to MAX_HAND_SIZE.
func _on_search_overlay_complete(picks: Array) -> void:
	if _pending_play.is_empty():
		return
	var taken: int = 0
	for pick_raw in picks:
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


# 계획 중시 complete: the picks never left the hand — the overlay only showed
# them — so all we do is file them in the preserve list. From here until the
# player's next 작전 단계 they are skipped by `_trim_hand_overflow`.
func _on_preserve_overlay_complete(picks: Array) -> void:
	if _pending_play.is_empty():
		return
	var marked: int = 0
	for raw in picks:
		var cd := raw as CardData
		if _bs.preserved_cards_p.has(cd):
			continue
		_bs.preserved_cards_p.append(cd)
		marked += 1
	(_pending_play["log_lines"] as Array).append("보존 %d" % marked)
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
	if snap.has("preserved"):
		_bs.preserved_cards_p = (snap["preserved"] as Array).duplicate()
	# 취소된 카드가 세워 둔 단계 종료 요청도 함께 되돌린다.
	_end_phase_requested = false
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
	# Counted here rather than in _play_card_direct so a card cancelled out of a
	# 버리기 / 찾기 overlay (which rolls the whole play back via the snapshot in
	# _on_overlay_cancel) doesn't unlock 턴 넘기기 on a play that never happened.
	if bool(_pending_play.get("is_player", false)):
		_bs.cards_played_this_phase += 1
	_pending_play.clear()
	relayout_hand(_bs.player_card_nodes)
	highlight_affordable_cards()
	update_deck_discard_labels()
	_bs.hud.update_hud()
	_bs.renderer.queue_redraw()
	# 완벽한 마무리 — 체인이 다 돌고 `_dispose_used_card` 까지 끝난 **뒤**라야
	# 단계를 닫을 수 있다. 체인 도중에 닫으면 카드가 손패 밖에 떠 있는 채로
	# 문이 닫혀 discard 로도 소멸로도 가지 못한다. `cards_played_this_phase` 도
	# 바로 위에서 이미 올라갔으므로 `can_end_card_phase()` 의 게이트를 통과한다.
	if consume_end_phase_request():
		end_card_phase()


# Routes a played card by 키워드:
#  - `return_left[:N]` clause → back to the **손패 맨 왼쪽** (정밀 이동)
#  - keyword == "exhaust"     → removed (소멸), never re-enters the deck
#  - anything else            → returns to the discard pile
#
# 소멸은 `exhaust` 키워드 **하나로만** 결정된다. 예전에는 `uses > 0` 인 카드가
# 사용 횟수를 다 쓰면 사라졌는데, cards.csv 는 exhaust 가 아닌 카드도 거의 전부
# `uses = 1` 이라 전투 개시를 포함한 대부분의 카드가 한 번 내면 그대로 소멸했다
# (덱이 돌지 않고 매치 내내 줄어들기만 했다).
#
# 손패 복귀가 세 갈래 중 **가장 먼저**다 — 되돌아오는 카드는 discard 로도
# 소멸로도 가지 않는다.
func _dispose_used_card(cd: CardData, is_player: bool) -> void:
	var bump: int = _return_left_bump(cd)
	if bump >= 0:
		_return_card_to_hand_left(cd, is_player, bump)
		return
	if cd.keyword == "exhaust":
		return
	var discard: Array = _bs.player_discard if is_player else _bs.ai_discard
	discard.append(cd)


# `return_left[:N]` 절의 비용 증가분. 절이 없으면 -1 (= 손패로 돌아가지 않는다).
# 값이 없는 맨 `return_left` 는 0 — 비용은 그대로 두고 자리만 되돌린다.
func _return_left_bump(cd: CardData) -> int:
	if cd == null:
		return -1
	for clause in _parse_effect_chain(cd.effect):
		if String(clause["name"]) == "return_left":
			return max(0, int(clause.get("value", 0)))
	return -1


# 정밀 이동 (`return_left:N`) — 쓴 카드가 discard 를 건너뛰고 **손패 맨 왼쪽**
# 으로 돌아오며, 돌아온 그 카드의 비용만 N 오른다. `cd` 는 스타터 덱을 돌릴 때
# `make_card_copy` 로 뜬 시전자 전용 사본이므로, 이 증가는 그 한 장에만 남고
# 쓸 때마다 누적된다(0 → 1 → 2 …). 다른 카드는 건드리지 않는다 — 단계 전체에
# 비용을 얹는 `cost_inc_phase` 와는 별개의 노브다.
#
# 손패 상한은 보지 않는다. 이 카드는 손패를 나갔다가 되돌아오는 것이라 크기가
# 늘지 않고, 애초에 자기 차례에 들어온 카드는 `MAX_HAND_SIZE` 를 넘겨도
# 버리지 않는 것이 규칙이다(README: Hand overflow).
func _return_card_to_hand_left(cd: CardData, is_player: bool, bump: int) -> void:
	cd.cost = max(0, cd.cost + bump)
	if is_player:
		_bs.player_hand.insert(0, cd)
		spawn_card_node(cd, true)
	else:
		_bs.ai_hand.insert(0, cd)
		_bs.hud.update_ai_hand_visuals()


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

	_bs.blog.log_event("CARD", "%s plays [%s] effect=%s target=%s" % [
			"PLAYER" if is_player else "AI", cd.card_name, cd.effect,
			_target_str(target)])

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


# Debug-log helper: renders a resolved card target (PilotData / Vector2i / null)
# as a short string for BattleLogger.
func _target_str(target: Variant) -> String:
	if target == null:
		return "-"
	if target is Vector2i:
		return str(target)
	if target is PilotData:
		var p := target as PilotData
		return "%s@%s" % [_bs.pilot_label(p), str(p.grid_pos)]
	return str(target)


# Picks a target for an AI-played card. Mirrors the player-side targeting
# overlay rules but resolves to a random valid pick instead of opening UI.
# Returns PilotData (target=enemy/ally), Vector2i (target=location), or null.
func _ai_pick_target(cd: CardData, caster: PilotData,
		ally_team: int, enemy_team: int) -> Variant:
	if cd == null:
		return null
	match targeting_kind(cd):
		"pilot":
			var team: int = enemy_team if cd.target == "enemy" else ally_team
			var valid := compute_valid_pilot_targets(cd, caster, team)
			if valid.is_empty():
				return null
			return valid[randi() % valid.size()]
		"location":
			var valid_cells := compute_valid_location_targets(cd, caster)
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
		"strategy_on_kill":        return _effect_strategy_on_kill(value, is_player)
		"lane_stat":               return _effect_lane_stat(value, flags, caster)
		"growth":                  return _effect_growth_rate(value, flags, caster)
		"growth_until_phase":      return _effect_growth_until_phase(value, ally_team)
		"discard_hand":            return _effect_discard_hand(is_player)
		"discard_hand_draw":       return _effect_discard_hand_draw(is_player)
		"discard_right":           return _effect_discard_right(is_player, value)
		"discard_other_pilots":    return _effect_discard_other_pilots(flags,
				is_player, caster)
		"strategy_next_phase":     return _effect_strategy_next_phase(value, is_player)
		# 플레이어의 preserve 는 _process_pending_chain 이 오버레이로 가로채므로
		# 여기 오는 것은 AI(또는 오버레이가 없는 폴백)뿐이다.
		"preserve":                return _effect_preserve_random(is_player, value)
		"end_phase":               return _effect_end_phase()
		# 자리 되돌리기 / 비용 누적은 카드를 다 쓴 뒤 _dispose_used_card 가
		# 처리한다(chain 이 도는 동안은 카드가 손패 밖에 있으므로). 여기서는
		# 로그 한 줄만 남긴다.
		"return_left":             return "손패 복귀" if value <= 0 \
				else "손패 복귀 · 비용 +%d" % value
		_: return ""


func _effect_draw(is_player: bool, n: int) -> String:
	# No MAX_HAND_SIZE guard: a 드로우:N played during 작전 단계 is the side's own
	# turn, so it is allowed to overfill the hand. The overflow survives until
	# the turn ends — the first BATTLE auto-draw afterwards trims it back down
	# via _trim_hand_overflow. Only an exhausted deck+discard stops the draw.
	var drew: int = 0
	for i in n:
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
	# 공격 카드도 전장과 같은 명중 판정(hit/(hit+evasion))을 굴린다 —
	# `SimulationCore.roll_hit`. 빗나가면 데미지가 아예 없다.
	#   • pierce (필중)  — 판정을 건너뛰고 무조건 명중.
	#   • repeat (연속 공격) — 명중할 때마다 같은 공격을 한 번 더 굴린다.
	#     빗나가거나 대상이 쓰러지면 멈추고, 무한 루프 방지로
	#     MAX_ATTACK_REPEATS 타에서 끊는다.
	# 시전자가 없는 레거시 카드는 굴릴 스탯이 없으므로 항상 명중 처리.
	var pierce: bool = "pierce" in flags
	var repeat: bool = "repeat" in flags
	var hits: int = 0
	var total_dmg: int = 0
	# 판정 결과는 대상 파일럿 위에 그대로 떠오른다 — 빗나가면 MISS, 명중하면
	# 그 타격의 피해량. 연속 공격은 타수마다 하나씩, 조금씩 늦게 뜬다.
	var swings: int = 0
	while hits < MAX_ATTACK_REPEATS:
		var landed: bool = pierce or caster == null \
				or _bs.sim_core.roll_hit(caster, t)
		var delay: float = float(swings) * _bs.DMG_POPUP_STAGGER
		swings += 1
		if not landed:
			_bs.renderer.spawn_pilot_popup(t, "MISS", BattleRenderer.POPUP_MISS_COLOR, delay)
			break
		hits += 1
		var dealt: int = _apply_attack_damage(t, caster, n)
		total_dmg += dealt
		# dealt 는 보호막을 지나 HP 에 실제로 들어간 양이다. 보호막이 전부
		# 먹었으면 "-0" 대신 흡수로 읽히게 한다.
		if dealt > 0:
			_bs.renderer.spawn_pilot_popup(t, "-%d" % dealt,
					BattleRenderer.POPUP_DAMAGE_COLOR, delay)
		else:
			_bs.renderer.spawn_pilot_popup(t, "흡수",
					BattleRenderer.POPUP_SHIELD_COLOR, delay)
		if not repeat or not t.alive:
			break
	var tag: String = " (필중)" if pierce else ""
	if hits == 0:
		return "공격%s %s 빗나감" % [tag, _bs.pilot_label(t)]
	var hit_tag: String = " x%d" % hits if hits > 1 else ""
	return "공격%s%s %s -%d HP" % [tag, hit_tag, _bs.pilot_label(t), total_dmg]


# One landed swing of an attack card. Returns the **HP** damage dealt (what is
# left after 보호막 absorption, matching what the log line has always shown) so
# the caller can total it across a 연속 공격 chain.
#
# Damage = 시전자 ATK × value (value is the design unit, e.g. 공격:1 → 1×ATK).
# Mech ATK was scaled ×20 in the DB so a 1×ATK card hit lands at a meaningful
# share of pilot HP without a separate placeholder multiplier. Caster falls
# back to a flat 100 only when the card has no owner_pilot (legacy paths).
func _apply_attack_damage(t: PilotData, caster: PilotData, n: int) -> int:
	var atk_value: int = caster.atk if caster != null else 100
	var dmg: int = max(1, atk_value * n)
	var rolled: int = dmg
	# 보호막 absorbs first, HP next.
	if t.shield > 0:
		var absorbed: int = min(t.shield, dmg)
		t.shield -= absorbed
		dmg -= absorbed
	if dmg > 0:
		t.hp = max(0, t.hp - dmg)
	# 성장치는 **굴린 피해 전체**로 적립한다 — 보호막에 먹힌 몫도 기여다
	# (전장 · 교전 무대의 집계와 같은 규칙).
	_bs.score_pilot_damage(caster, rolled)
	if t.hp <= 0:
		_bs.mark_pilot_dead(t, caster)
	elif dmg > 0:
		_bs.anim_pilot_shake(t)
	return dmg


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
	# engage:N 의 N 은 **라운드 수** 그대로다 — 초로 환산하던 예전 규칙은 삭제됐다.
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
	_bs.blog.log_move(t, orig, t.grid_pos, "card-recall")
	_bs.anim_pilot_recall(t, orig)
	return "복귀 %s" % _bs.pilot_label(t)


# 결투 — opens a turn-based engage arena restricted to caster + picked enemy.
# No round budget is shown: neither side can disengage, so the fight runs until
# one of them is KO'd. TurnEngageSim.DUEL_MAX_ROUNDS is only a runaway cap.
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
# compute_valid_location_targets already validates the cell against
# cast_range; we just commit the new grid_pos and play the tween.
#
# 착지점이 **정글이거나 다른 레인의 통로**면 `RecallSystem.process_phase_end_recalls`
# 가 작전 단계 끝에 그 파일럿을 전장에서 이탈시킨다(만피가 될 때까지 복귀 대기).
# 자기 레인 위라면 아무리 깊어도 합법이다 — 스플릿 푸시는 살려 둔 설계다.
func _effect_move(caster: PilotData, picked: Variant) -> String:
	if not (picked is Vector2i) or caster == null:
		return "이동 (대상 없음)"
	var cell := picked as Vector2i
	if cell == caster.grid_pos:
		return "이동 %s (제자리)" % _bs.pilot_label(caster)
	var orig := caster.grid_pos
	caster.grid_pos = cell
	_bs.blog.log_move(caster, orig, cell, "card-move")
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


# ─── 성장 / 라인전 스탯 카드 ─────────────────────────────────────────────────
# 안전한 파밍 / 공격적인 라인전. 둘 다 **시전자 한 명**에게만 걸리고, 같은
# 필드를 두 번 건드리면 **덮어쓴다**(합산 아님). 3종짜리 라인전 풀에서 2장을
# 뽑는 구조라 같은 카드가 겹치기 쉬운데, 합산을 허용하면 +30% 스노볼이 그냥
# 운으로 굴러 나온다.

## `lane_stat:N|turns:T` — 시전자의 전장 명중 판정(hit / evasion)에 N% 배율.
## 만료는 SimulationCore.tick_growth_and_expiries 가 매 턴 확인한다.
func _effect_lane_stat(pct: int, flags: Array, caster: PilotData) -> String:
	if caster == null:
		return "라인전 스탯 (시전자 없음)"
	var turns: int = _flag_int(flags, "turns", 0)
	caster.lane_stat_mod = float(pct) / 100.0
	caster.lane_stat_expire_turn = (_bs.turn_count + turns) if turns > 0 else -1
	return "%s 라인전 스탯 %+d%% (%d턴)" % [_bs.pilot_label(caster), pct, turns]


## `growth:N|turns:T` — 시전자의 성장 **획득 배율**을 N% 올린다(성장률 자체가
## 아니라 그 배수다: +10% → 턴당 +1%p 가 +1.1%p 가 된다). 작전 단계 만료형
## (완벽한 마무리)과 같은 필드를 쓰므로 그쪽 표시는 함께 꺼 준다.
func _effect_growth_rate(pct: int, flags: Array, caster: PilotData) -> String:
	if caster == null:
		return "성장 (시전자 없음)"
	var turns: int = _flag_int(flags, "turns", 0)
	caster.growth_rate_mult        = 1.0 + float(pct) / 100.0
	caster.growth_rate_expire_turn = (_bs.turn_count + turns) if turns > 0 else -1
	caster.growth_until_phase      = false
	return "%s 성장 %+d%% (%d턴)" % [_bs.pilot_label(caster), pct, turns]


## `growth_until_phase:N` — 완벽한 마무리. 시전자 **팀 전원**의 성장 획득 배율을
## 올리고, 그 팀의 다음 작전 단계 진입 시 `_apply_phase_entry_carryovers` 가 걷는다.
func _effect_growth_until_phase(pct: int, ally_team: int) -> String:
	var count: int = 0
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.team != ally_team:
			continue
		p.growth_rate_mult        = 1.0 + float(pct) / 100.0
		p.growth_rate_expire_turn = -1
		p.growth_until_phase      = true
		count += 1
	return "아군 %d명 성장 %+d%% (다음 작전 단계까지)" % [count, pct]


# ─── 손패 조작 카드 ──────────────────────────────────────────────────────────
# 아래 강제 버리기들은 **계획 중시의 보존을 무시한다** — 보존은 상한 초과
# 자동 버리기(`_trim_hand_overflow`)로부터만 지켜 준다.

## Moves the whole hand to the discard pile. Returns how many cards moved.
func _discard_whole_hand(is_player: bool) -> int:
	var hand:    Array = _bs.player_hand    if is_player else _bs.ai_hand
	var discard: Array = _bs.player_discard if is_player else _bs.ai_discard
	var moved: int = hand.size()
	for raw in hand.duplicate():
		var cd := raw as CardData
		discard.append(cd)
		if is_player:
			_despawn_player_card_node(cd)
	hand.clear()
	return moved


## 완벽한 마무리의 첫 절 — 손패 전부 버리기.
func _effect_discard_hand(is_player: bool) -> String:
	var moved: int = _discard_whole_hand(is_player)
	_refresh_hand_after_bulk_change(is_player)
	return "손패 %d장 버리기" % moved


## 재고 — 손패를 전부 버리고 **버린 장수만큼** 새로 뽑는다. 손패 크기는 그대로고
## 내용만 갈린다(덱이 마르면 뽑은 만큼만).
func _effect_discard_hand_draw(is_player: bool) -> String:
	var moved: int = _discard_whole_hand(is_player)
	var drew: int = 0
	for _i in moved:
		var c := draw_card(is_player)
		if c == null:
			break
		if is_player:
			spawn_card_node(c)
		drew += 1
	_refresh_hand_after_bulk_change(is_player)
	return "손패 %d장 버리고 %d장 드로우" % [moved, drew]


## 과감한 정리 — 손패 **오른쪽**(가장 최근에 들어온 쪽) N장을 버린다.
func _effect_discard_right(is_player: bool, n: int) -> String:
	var hand:    Array = _bs.player_hand    if is_player else _bs.ai_hand
	var discard: Array = _bs.player_discard if is_player else _bs.ai_discard
	var moved: int = 0
	for _i in n:
		if hand.is_empty():
			break
		var cd := hand.pop_back() as CardData
		discard.append(cd)
		if is_player:
			_despawn_player_card_node(cd)
		moved += 1
	_refresh_hand_after_bulk_change(is_player)
	return "오른쪽 %d장 버리기" % moved


## 솔로 퍼포먼스 — 시전자 **본인 것이 아닌** 손패 카드를 전부 버리고, 버린 장당
## `strategy_each` 만큼 전략 점수를 받는다. 시전자가 없으면 "본인 카드"를 가릴
## 수 없으므로 아무것도 하지 않는다(손패 전멸 사고 방지).
func _effect_discard_other_pilots(flags: Array, is_player: bool,
		caster: PilotData) -> String:
	if caster == null:
		return "솔로 퍼포먼스 (시전자 없음)"
	var per: int = _flag_int(flags, "strategy_each", 0)
	var hand:    Array = _bs.player_hand    if is_player else _bs.ai_hand
	var discard: Array = _bs.player_discard if is_player else _bs.ai_discard
	var moved: int = 0
	for raw in hand.duplicate():
		var cd := raw as CardData
		if cd.owner_pilot == caster:
			continue
		hand.erase(cd)
		discard.append(cd)
		if is_player:
			_despawn_player_card_node(cd)
		moved += 1
	var gained: int = per * moved
	if gained > 0:
		if is_player:
			_bs.player_cost += gained
		else:
			_bs.ai_cost += gained
	_refresh_hand_after_bulk_change(is_player)
	return "다른 파일럿 카드 %d장 버리기 · 전략 점수 +%d" % [moved, gained]


## 계획 중시의 **AI / 폴백 경로** — 손패에서 무작위 N장을 보존 목록에 올린다.
## 플레이어는 `_process_pending_chain` 이 CardSelectOverlay 로 가로채므로 여기
## 오지 않는다.
func _effect_preserve_random(is_player: bool, n: int) -> String:
	var hand:      Array = _bs.player_hand      if is_player else _bs.ai_hand
	var preserved: Array = _bs.preserved_cards_p if is_player else _bs.preserved_cards_ai
	var bag: Array = hand.duplicate()
	bag.shuffle()
	var marked: int = 0
	for raw in bag:
		if marked >= n:
			break
		var cd := raw as CardData
		if preserved.has(cd):
			continue
		preserved.append(cd)
		marked += 1
	if is_player:
		highlight_affordable_cards()
	return "보존 %d장" % marked


## Repaints the hand after a clause moved several cards at once.
func _refresh_hand_after_bulk_change(is_player: bool) -> void:
	if is_player:
		relayout_hand(_bs.player_card_nodes)
		highlight_affordable_cards()
		update_deck_discard_labels()
	else:
		_bs.hud.update_ai_hand_visuals()


# ─── 지연 효과 카드 ──────────────────────────────────────────────────────────
## 아드레날린의 뒷절 — 다음 작전 단계 진입 시 정산될 전략 점수(음수 가능).
func _effect_strategy_next_phase(n: int, is_player: bool) -> String:
	if is_player:
		_bs.next_phase_strategy_p += n
	else:
		_bs.next_phase_strategy_ai += n
	return "다음 작전 단계 전략 점수 %+d" % n


## 계획 살인 — **선불 예약형**. 카드를 낸 시점에 현상금을 심어 두고,
## `BattleSim.mark_pilot_dead` 가 상대 팀 사망을 볼 때 한 번 지급하고 소모한다.
## 같은 단계에 두 장을 내도 큰 쪽 하나만 남는다(현상금은 처치 한 번분이다).
func _effect_strategy_on_kill(n: int, is_player: bool) -> String:
	if is_player:
		_bs.kill_bounty_p = maxi(_bs.kill_bounty_p, n)
	else:
		_bs.kill_bounty_ai = maxi(_bs.kill_bounty_ai, n)
	return "이번 단계 처치 시 전략 점수 +%d (예약)" % n


## 완벽한 마무리의 마지막 절 — 자기 작전 단계를 강제 종료한다. 실제 종료는
## 여기서 하지 않는다: 효과 체인이 도는 동안 카드는 손패 밖에 떠 있어서, 지금
## 단계를 닫으면 카드 소멸 / discard 라우팅 전에 문이 닫힌다. 플레이어는
## `_finalize_pending_play` 말미가, AI 는 `AiCardPlayer` 의 플레이 루프가
## `consume_end_phase_request()` 로 이 요청을 받아 간다.
func _effect_end_phase() -> String:
	_end_phase_requested = true
	return "작전 단계 종료"


## Pulls an int off a `flag:value` modifier attached to **this** clause.
## `_clause_int_flag` scans the whole chain instead and is kept for min_range,
## where the flag can only appear once anyway.
func _flag_int(flags: Array, flag_name: String, default_value: int) -> int:
	for f in flags:
		var fs: String = f as String
		if fs.begins_with(flag_name + ":"):
			return int(fs.substr(flag_name.length() + 1))
	return default_value


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
			# The node is about to be freed, so any selection pointing at it has
			# to go first — otherwise _selected_card dangles and the description
			# box / 확인 row outlive the card they belong to. (Reachable from
			# _trim_hand_overflow, whose auto-draw can fire on a card the player
			# left selected when the phase ended.)
			if _selected_card == c:
				deselect_current_card()
			_bs.player_card_nodes.erase(c)
			c.queue_free()
			return
