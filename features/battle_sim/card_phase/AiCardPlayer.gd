class_name AiCardPlayer
extends Node

# AI-side card play presentation layer. While the player phase ends, AI plays
# its affordable cards one by one — this node owns the brief central card
# animation that shows what the AI just played, plus the per-step pacing
# delays. Engage cards routed through here also open the same real-time
# EngageArena the player would see, so the AI's combat is fully visible.
#
# Lifecycle:
#   • CardPhaseManager.end_card_phase() awaits run_ai_plays(), which loops the
#     AI hand, picks an affordable card, applies its effect, and presents the
#     central animation between plays.
#   • Engage cards await EngagePhaseManager.engage_finished before continuing
#     to the next card so the modal completes before the next animation.

const SHOW_DURATION_SEC := 0.55     # full visibility hold per card
const FADE_IN_SEC       := 0.18
const FADE_OUT_SEC      := 0.22
const POST_GAP_SEC      := 0.14
const CENTER_POS        := Vector2(540.0, 760.0)
const SCALE_BIG         := Vector2(1.35, 1.35)
const SCALE_SMALL       := Vector2(0.85, 0.85)
# Fly-out from the AI hand peek to the screen centre. The popped card-back
# tweens its position + scale toward CENTER_POS while still showing the back,
# then a snap-flip swaps to the face-up data; finally it holds + fades out.
const FLY_FROM_HAND_SEC := 0.32
const FLIP_HALF_SEC     := 0.10

# 한 차례에 AI 가 낼 수 있는 최대 카드 수.
#
# 루프의 종료 조건은 "낼 수 있는 카드가 없을 때"인데, 비용을 쓰지 않으면서
# 손패를 회전시키는 카드가 그 조건을 영원히 미룰 수 있다 — 재고(비용 0, 손패를
# 전부 버리고 같은 수를 다시 뽑는다)가 대표적으로, 덱 + discard 가 마르기
# 전까지 무한히 다시 뽑힌다. 이 상한은 그 구조적 루프를 끊는 백스톱이지
# 밸런스 노브가 아니다 — 정상적인 손패라면 절대 닿지 않는다.
const MAX_PLAYS_PER_TURN := 12

# ─── 우선순위 점수제 ─────────────────────────────────────────────────────────
# AI 는 이제 낼 수 있는 카드 중 **무작위**가 아니라 **점수가 가장 높은** 한 장을
# 고른다. 목표는 강한 AI 가 아니라 **눈에 띄게 덜 헛도는** AI 다 — 예전에는
# 사거리 안에 적이 없는 공격 카드나 만피 아군에게 거는 회복이 무작위로 튀어나와,
# 상대 차례가 중앙 애니메이션만 돌고 아무 일도 일어나지 않는 구간이 됐다.
#
# 점수는 절 이름 하나로 정한다(`CardPhaseManager.card_clause_names`). 카드 한
# 장이 절을 여럿 달고 있으면 **가장 높은 절**이 그 카드의 성격이다 — 간보기는
# `attack;on_hit;engage;on_miss;strategy` 인데 그 카드가 하는 일은 공격이지
# 전략 점수가 아니다.
const CLAUSE_WEIGHT: Dictionary = {
	"execute": 5.0,        # 마무리 — 조건이 맞으면 그 자리에서 한 명이 사라진다
	"attack": 3.0,
	"attack_bounty": 3.0,
	"mutual_attack": 2.6,
	"engage": 2.5,
	"duel": 2.5,
	"taunt_all": 2.0,
	"advance": 1.6,
	"heal_pct": 1.4,       # 아래 `_support_bias` 가 상황을 본다
	"shield_atk": 1.4,
	"shield_pct": 1.4,
	"recall_ally": 1.4,
	"draw": 1.0,
	"search": 1.0,
	"search_card": 1.0,
	"search_discard": 1.0,
	"draw_discard": 1.0,
	"strategy": 1.0,
	"steal_camp": 1.2,
	"move": 0.6,
	"push": 0.6,
}
## 표에 없는 절의 기본 점수. 0 이 아니라 낮은 양수인 것은 "모르는 카드"가
## 아예 안 나가는 것보다 마지막에라도 나가는 쪽이 낫기 때문이다.
const CLAUSE_WEIGHT_DEFAULT: float = 0.5
## 비용 한 점당 깎이는 점수. 싼 카드를 먼저 내면 한 차례에 더 많은 카드가 나간다.
const COST_PENALTY: float = 0.15
## 동점을 가르는 흔들림. 없으면 같은 손패가 매번 같은 순서로 나가 상대 차례가
## 기계적으로 읽힌다.
const JITTER: float = 0.4
## 회복 · 보호막이 제값을 하는 아군 체력 비율. 이 위면 후순위로 밀린다.
const SUPPORT_HP_RATIO: float = 0.70
## 그 후순위의 크기. 낮추기만 하고 막지는 않는다 — 만피에 거는 보호막도
## 무의미하지는 않고, 손에 그것밖에 없을 수도 있다.
const SUPPORT_IDLE_PENALTY: float = 2.5

var _bs: BattleSim = null


func bind(bs: BattleSim) -> void:
	_bs = bs


# Loops AI plays for the duration of end_card_phase. Each card is presented
# in the centre with a fade-in / hold / fade-out tween before the effect
# applies; engage clauses then await the engage modal so the player sees the
# combat play out exactly as if they had cast the card.
func run_ai_plays() -> void:
	if _bs.ai_cost < _bs.PHASE_THRESHOLD:
		return
	var plays: int = 0
	while not _bs.ai_hand.is_empty():
		if plays >= MAX_PLAYS_PER_TURN:
			break
		plays += 1
		var pick: CardData = _pick_best_card()
		if pick == null:
			break
		var eff_cost: int = _bs.effective_cost_for(pick, false)
		_bs.ai_cost -= eff_cost
		# Consume the AI's pending engage discount on use so a follow-up
		# engage card pays full price.
		if _bs.engage_discount_ai > 0 and _bs.card_phase.card_has_engage(pick):
			_bs.engage_discount_ai = 0
		_bs.ai_hand.erase(pick)
		await _show_card_centre(pick)
		# 공격 카드는 명중 연출이 끝나야 반환된다 — 그래서 await 다. 연출이
		# 없는 카드는 그 자리에서 값을 돌려주므로 대기가 붙지 않는다.
		var log_msg: String = await _bs.card_phase.apply_and_dispose_ai_card(pick)
		if log_msg != "":
			_bs.last_log = log_msg
		_bs.hud.update_hud()
		_bs.renderer.queue_redraw()
		# The AI's engage / 결투 cards open the same real-time arena the player
		# would see. Gate on is_active() rather than on the card's effect chain
		# so 결투 (whose clause is `duel`, not `engage:N`) is awaited too —
		# otherwise the next AI play stomps the open arena.
		if _bs.engage_phase.is_active():
			await _bs.engage_phase.engage_finished
		# 완벽한 마무리 — 그 카드의 `end_phase` 절이 이 루프를 끝낸다. 아레나를
		# 기다린 **뒤**에 확인하는 것이 중요하다: 먼저 끊으면 카드가 연 교전이
		# 화면에 뜬 채로 상대 차례가 닫힌다.
		if _bs.card_phase.consume_end_phase_request():
			break
		await _bs.get_tree().create_timer(POST_GAP_SEC).timeout


## 지금 손패에서 **가장 점수가 높은** 한 장. 낼 수 있는 카드가 하나도 없으면
## null 이고, 그러면 호출 루프가 차례를 접는다.
func _pick_best_card() -> CardData:
	var best: CardData = null
	var best_score: float = -INF
	for raw in _bs.ai_hand:
		var cd := raw as CardData
		var sc: float = _score_card(cd)
		if sc <= -INF:
			continue
		if sc > best_score:
			best_score = sc
			best = cd
	return best


## 카드 한 장의 점수. `-INF` 는 "이 카드는 지금 낼 수 없다"이고 이유가 둘이다 —
## 지불 불가 / 시전자 사망 / 사용 불가 카드(`ai_can_play`), 그리고 **고를 대상이
## 없다**. 후자를 거르지 않으면 사거리 안에 적이 없는 공격 카드가 그대로 나가
## `_ai_pick_target` 이 null 을 돌려주고, 효과 절이 "대상 없음"을 로그에 남긴
## 채 비용만 빠진다.
func _score_card(cd: CardData) -> float:
	var cp: CardPhaseManager = _bs.card_phase
	if cd == null or cp == null or not cp.ai_can_play(cd):
		return -INF
	if cp.card_needs_target(cd) and cp.ai_target_for(cd, cd.owner_pilot) == null:
		return -INF
	var score: float = -INF
	for raw in cp.card_clause_names(cd):
		var clause: String = raw as String
		if clause.is_empty():
			continue
		var w: float = float(CLAUSE_WEIGHT.get(clause, CLAUSE_WEIGHT_DEFAULT))
		if clause == "heal_pct" or clause == "shield_atk" or clause == "shield_pct" \
				or clause == "recall_ally":
			w -= _support_bias()
		score = maxf(score, w)
	if score <= -INF:
		score = CLAUSE_WEIGHT_DEFAULT
	score -= COST_PENALTY * float(_bs.effective_cost_for(cd, false))
	return score + randf() * JITTER


## 회복 · 보호막이 지금 제값을 하는가. 팀에서 가장 다친 아군이 성한 편이면
## 그만큼 후순위로 민다 — 만피 다섯에게 거는 회복이 공격보다 먼저 나가는 것이
## 예전 무작위 픽에서 가장 눈에 띄는 헛수고였다.
func _support_bias() -> float:
	var worst: float = 1.0
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.team != 1 or not p.alive or p.max_hp <= 0:
			continue
		worst = minf(worst, float(p.hp) / float(p.max_hp))
	return 0.0 if worst < SUPPORT_HP_RATIO else SUPPORT_IDLE_PENALTY


# Pulls one card-back from the AI hand peek (rightmost), flies it from its
# hand position to screen centre, snap-flips to the played card's face,
# holds, and fades out. The hand visuals reflow as soon as the card is
# popped so the count peek matches `_bs.ai_hand` immediately.
#
# Falls back to the previous "spawn at centre" animation when the AI hand
# peek somehow has no node to pop (e.g., a stray play with empty visuals).
func _show_card_centre(cd: CardData) -> void:
	var node: Card = null
	var center_anchor: Vector2 = CENTER_POS - Vector2(Card.CARD_W * 0.5, Card.CARD_H * 0.5)

	if _bs.hud != null:
		node = _bs.hud.pop_ai_hand_card_node()
	if node != null:
		# Card was reparented to _bs.canvas with its hand-row position+scale
		# preserved by HudBuilder.pop_ai_hand_card_node(). Pivot the card on
		# its centre so the fly-out scale grows symmetrically.
		node.pivot_offset = Vector2(Card.CARD_W * 0.5, Card.CARD_H * 0.5)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in node.get_children():
			if child is Control:
				(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Phase 1 — fly to centre, scale up, **straighten out**, still showing
		# the back. 회전까지 함께 푸는 이유: 뽑혀 나온 카드는 상대 부채꼴이
		# 준 기울기(`HudBuilder._layout_ai_hand` 의 `rotation = -theta`)를 그대로
		# 달고 있어, 안 펴면 화면 한가운데에 비스듬하게 선 채로 뒤집힌다.
		var tw_fly := _bs.create_tween().set_parallel()
		tw_fly.tween_property(node, "global_position", center_anchor,
				FLY_FROM_HAND_SEC).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw_fly.tween_property(node, "scale", SCALE_BIG, FLY_FROM_HAND_SEC) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw_fly.tween_property(node, "rotation", 0.0, FLY_FROM_HAND_SEC) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		await tw_fly.finished
		if not is_instance_valid(node):
			return

		# Phase 2 — snap-flip: shrink x to 0, swap to face-up, grow back.
		var tw_flip_a := _bs.create_tween()
		tw_flip_a.tween_property(node, "scale",
				Vector2(0.0, SCALE_BIG.y), FLIP_HALF_SEC) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		await tw_flip_a.finished
		if not is_instance_valid(node):
			return
		# Swap visuals from card back → card front.
		node.setup(cd, false, true)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in node.get_children():
			if child is Control:
				(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tw_flip_b := _bs.create_tween()
		tw_flip_b.tween_property(node, "scale", SCALE_BIG, FLIP_HALF_SEC) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		await tw_flip_b.finished
	else:
		# Fallback: spawn at centre, fade in.
		node = _bs.CARD_SCENE.instantiate() as Card
		node.pivot_offset = Vector2(Card.CARD_W * 0.5, Card.CARD_H * 0.5)
		_bs.canvas.add_child(node)
		node.setup(cd, false, true)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in node.get_children():
			if child is Control:
				(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.global_position = center_anchor
		node.scale = SCALE_SMALL
		node.modulate = Color(1, 1, 1, 0)
		var tw_in := _bs.create_tween().set_parallel()
		tw_in.tween_property(node, "modulate", Color.WHITE, FADE_IN_SEC) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw_in.tween_property(node, "scale", SCALE_BIG, FADE_IN_SEC) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		await tw_in.finished

	await _bs.get_tree().create_timer(SHOW_DURATION_SEC).timeout

	if not is_instance_valid(node):
		return
	var tw_out := _bs.create_tween().set_parallel()
	tw_out.tween_property(node, "modulate", Color(1, 1, 1, 0), FADE_OUT_SEC) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw_out.tween_property(node, "scale", SCALE_SMALL, FADE_OUT_SEC) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await tw_out.finished
	if is_instance_valid(node):
		node.queue_free()
