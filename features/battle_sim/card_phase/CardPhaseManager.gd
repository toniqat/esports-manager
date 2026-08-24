class_name CardPhaseManager
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim

# Hand layout uses BS_HAND_WIDTH (inner) + BS_HAND_CARD_GAP (target gap) for
# adaptive spacing.

# ─── 손패 상태 ────────────────────────────────────────────────────────────────
# **카드 선택 상태는 없다.** 카드를 클릭해도 아무 일도 일어나지 않으며, 카드를
# 집는 유일한 조작은 **끌기**다 — 누른 채 `DRAG_THRESHOLD_PX` 넘게 움직이면
# 그때 비로소 카드가 손을 떠나고(`_begin_drag`), 그 순간이 곧 대상 지정 단계의
# 시작이다. 손을 떼면 드롭이 성립했든 빗나갔든 그 상태는 통째로 사라진다.
#
# 예전에는 "선택"이라는 중간 상태가 있었다: 클릭하면 카드가 리프트되고 대상
# 지정이 켜진 채 남아, 그 상태에서 다시 끌거나 다른 곳을 눌러 해제해야 했다.
# 조작이 둘로 갈려 있었고(클릭→끌기 / 클릭→클릭 해제), 카드를 낼 수 있는
# 경로는 어차피 드롭 하나뿐이라 중간 상태가 하는 일이 없었다.
var _description_box: Panel = null
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
# _push_focus_card) — NOT necessarily the hovered one, since a card being
# dragged outranks the cursor.
var _reflow_focus: Card = null
var _reordering: bool = false

# Mouse picking for the hand is owned by one transparent Control over the whole
# row rather than by the cards themselves — see _apply_hit_bands for why.
# `_hit_bands[i]` is the viewport-space [left, right] strip card `i` answers for.
var _hand_hit_layer: Control = null
var _hit_bands: Array[Vector2] = []

# ─── Description box ─────────────────────────────────────────────────────────
# 카드 설명은 **화면 상단 고정 위치**에 뜬다(예전에는 든 카드 좌/우 옆이었다).
# 두 가지가 그렇게 만들었다: (1) 카드를 끌어다 놓는 조작이 생기면서 카드를
# 따라다니는 상자가 커서 앞을 가로막았고, (2) 상자를 카드에 붙여 두면 손패
# 오른쪽 끝 카드에서는 상자가 화면 밖으로 밀려 반대쪽으로 튀었다. 상단 패널
# (HudBuilder.TOP_PANEL_H = 130) 바로 아래, 전장 상단(y 369)보다 위인 빈 띠에
# 가로 가운데 정렬로 앉는다.
#
# 뜨는 조건도 바뀌었다 — 이제 **가리키기만 해도** 뜬다. 어느 카드를 보여 줄지는
# 손패 포커스와 같은 질문이라 `_push_focus_card()` 하나가 답한다: 끌고 있는
# 카드가 있으면 그것, 없으면 커서 아래 카드.
const DESC_BOX_W   := 640.0
const DESC_BOX_H   := 150.0
const DESC_BOX_TOP := 142.0
## 지금 설명 상자가 보여 주고 있는 카드. 포커스가 실제로 바뀔 때만 다시 짓는다.
var _desc_card: Card = null

# ─── 드래그 앤 드롭 (카드를 집는 **유일한** 조작) ────────────────────────────
# 누르는 것만으로는 아무 일도 일어나지 않는다. 누른 채 `DRAG_THRESHOLD_PX` 넘게
# 움직여야 카드가 손을 떠나고, 그 순간 행이 그 카드를 중심으로 벌어지며 대상
# 지정 표시(딤 · 강조)가 켜진다. 손을 떼면 그 상태는 통째로 사라진다.
#
# **끌린 카드의 자세는 대상 유무가 가른다:**
#   • PILOT / LOCATION — 카드는 **움직이지 않는다**. 손패의 리프트 자세
#     (`Card.PRESS_LIFT`) 그대로 남고, 카드 위쪽 끝에서 커서까지 **조준 화살표**
#     (`CardDragArrow`, 2차 베지어)가 이어진다. 카드가 커서에 붙어 날아다니면
#     겨누려는 대상 — 커진 파일럿 초상 / 초록 유효 셀 — 을 카드가 자기 몸으로
#     덮어 버려, 정작 놓는 순간에 무엇 위에 있는지가 보이지 않는다.
#   • 그 밖의 카드 — 겨눌 대상이 없으므로 가릴 것도 없다. 카드는 **손패를 떠나
#     커서를 따라다니고**(`Card.follow_cursor`) 기울기가 곧게 펴진다. 원래
#     자리는 **빈 채로 유지된다** — `relayout_hand` 가 `is_dragging` 카드를
#     건너뛰므로 남은 카드는 자리를 지키고, 빗나간 드롭은 그 자리로 되돌아온다.
#
# 놓았을 때 카드가 나가는 조건도 같은 기준이다:
#   • PILOT / LOCATION — **대상 위에 놓아야** 나간다(커진 초상 / 초록 유효 셀).
#   • 그 밖의 카드      — 화면 한가운데 **드롭 존**에 놓으면 나간다.
#   • 버리기:N 픽 중    — 중앙 **버리기 구역**에 놓으면 버릴 카드로 넘어간다.
# 어느 쪽이든 확정은 `CardTargetingOverlay.confirm_with → _on_selection_confirm`
# **한 경로**를 지난다 — 비용 차감 / 카드 소비 / effect chain 이 두 벌 생기지
# 않도록. 빗나가면 카드는 그냥 제자리로 돌아온다.
## 이만큼 움직여야 클릭이 아니라 드래그로 읽는다.
const DRAG_THRESHOLD_PX := 10.0
## 드롭 존의 세로 크기 — 화면 높이 대비 비율. 가로는 화면 전체 폭이다.
const DROP_ZONE_H_RATIO := 0.40
const DROP_ZONE_FILL      := Color(1.00, 0.85, 0.30, 0.05)
const DROP_ZONE_FILL_HOT  := Color(1.00, 0.85, 0.30, 0.12)
const DROP_ZONE_BORDER     := Color(1.00, 0.85, 0.30, 0.45)
const DROP_ZONE_BORDER_HOT := Color(1.00, 0.92, 0.55, 0.95)
## 안내 문구를 구역 위쪽에 붙이는 거리(px). 카드가 커서를 따라다니던 시절에는
## 한가운데 두면 카드가 정확히 그 위에 앉아 글자를 반으로 갈랐다. 지금은 카드가
## 손패에 남지만, 구역 한가운데는 전장 한복판이라 문구가 타일 위에 겹쳐 읽히므로
## 여전히 위쪽 띠에 둔다.
const DROP_ZONE_LABEL_TOP := 22.0
const DROP_ZONE_LABEL_H   := 48.0
## 버리기:N 픽 중의 드롭 존 높이(px). `CardSelectOverlay.TO_DISCARD_CENTER_Y` 를
## 중심으로 잡히며, 이미 골라 둔 카드들이 늘어선 줄(카드 높이 220)을 넉넉히
## 감싼다 — 그 줄 위에 놓는 것이 곧 "여기에 더한다"로 읽혀야 하기 때문.
const DISCARD_ZONE_H := 440.0
## 조준 화살표의 시작점을 카드 위쪽 끝에서 **카드 안쪽으로** 밀어 넣는 거리.
## 화살표 노드는 손패 카드보다 뒤에 그려지므로, 이만큼 파묻힌 시작부는 카드에
## 가려 보이지 않고 화살이 카드 밑에서 뻗어 나온 것처럼 읽힌다.
const ARROW_TUCK_PX := 42.0

## 눌린 카드 — 아직 드래그로 승격되지 않은 상태. null 이면 버튼을 쥐고 있지 않다.
## 여기서 그냥 손을 떼면 **아무 일도 일어나지 않는다**(선택 상태가 없으므로).
var _press_card: Card = null
var _press_pos: Vector2 = Vector2.ZERO
## 지금 끌고 있는 카드. null 이면 드래그 중이 아니다. 손패에서 카드가 "활성"인
## 유일한 상태이며, 예전의 `_selected_card` 가 하던 일을 전부 이어받았다 —
## 포커스 / z-order / 대상 지정 / 드롭 확정이 모두 이 값을 본다.
var _drag_card: Card = null
## 끌린 카드가 커서를 따라다니는가(대상 지정이 아닌 카드). false 면 손패의
## 리프트 자세에 남고 조준 화살표가 대신 커서로 뻗는다.
var _drag_follows_cursor: bool = false
## 카드와 커서를 잇는 조준 화살표. 대상 지정 카드에서만 뜬다.
var _drag_arrow: CardDragArrow = null
var _drop_zone: Panel = null
var _drop_zone_label: Label = null

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

# 공격 카드(`attack:N`)의 돌진 연출이 도는 동안 켜진다. 한 장을 낸 뒤 연출이
# 끝나기 전에 다음 카드를 낼 수 없어야 한다는 것이 이 플래그의 전부다 — 손패는
# 딤드되고(`_is_player_input_blocked`), 턴 넘기기도 잠긴다
# (`can_end_card_phase`). AI 차례의 공격에도 똑같이 걸리지만, 그때는 이미
# `_ai_play_in_progress` 가 같은 두 곳을 막고 있으므로 사실상 플레이어 차례용이다.
var _attack_anim_active: bool = false

# True while the "당신의 차례" banner is sweeping in / holding / fading out.
# The hand stays dimmed and clicks are blocked until it clears so the player
# can't pre-empt the announcement.
var _player_turn_announce_in_progress: bool = false

# 마지막으로 차례를 잡은 팀 (0 = 플레이어, 1 = AI, -1 = 아직 아무도 안 잡음).
# 양 팀이 동시에 문턱 위에 있을 때 교대를 강제하는 유일한 상태 — 자세한 규칙은
# _next_turn_side() 주석 참조. 새 판마다 build_starter_decks 가 -1 로 되돌린다.
var _last_turn_side: int = -1

# 플레이어가 자기 차례를 넘긴 뒤, 다시 차례를 받기 전까지 서 있는 잠금.
# 카드를 한 장도 안 내고 넘겨도 되고 문턱 초과분만 소멸하므로, 넘긴 직후의
# 점수는 정확히 문턱에 걸려 있다 — 잠금이 없으면 다음 틱에 곧바로 자기 차례가
# 다시 열린다. 푸는 조건은 둘, **자동 드로우로 손패가 바뀌거나**(do_battle_turn)
# **상대가 한 번 차례를 가지거나**(_run_ai_turn) 다. 자세한 이유는
# _next_turn_side() 주석 참조.
var _player_pass_lock: bool = false

# 연속 공격(`attack:N|repeat`)이 명중을 이어갈 때 한 번의 사용으로 허용되는
# 최대 타수. 확률상 거의 닿지 않지만 무한 루프를 구조적으로 막는 상한이다.
const MAX_ATTACK_REPEATS: int = 5

## 직전 `draw_card` 가 손패의 같은 뭉치에 **흡수됐는가**. true 면 손패 크기가
## 늘지 않았고 새 카드 노드도 서지 않았으므로, 호출 측은 `spawn_card_node` 를
## 건너뛰어야 한다 — 스택 카드 전용 신호다.
var last_draw_merged: bool = false

## 지금 도는 효과 체인에서 **공격 절이 한 대라도 맞았는가.** `on_hit` /
## `on_miss` 가 읽는 유일한 값이고 공격 절이 결과를 여기에 적는다. 체인
## 하나짜리 수명이라 카드 한 장이 시작될 때 false 로 놓인다.
var _chain_hit: bool = false
## 지금 효과 체인이 도는 카드. 절이 **카드 자신**을 물어야 할 때 읽는다 —
## 스택 수(`|stack`)와 명중 수 연동 생성(`gen_hand:N|per_hit`)이 그것이다.
## 절 함수마다 카드를 인자로 끌고 다니면 서명이 열 개 넘게 늘어난다.
var _current_card: CardData = null
## 지금 체인이 겨누고 있는 대상 (PilotData / Vector2i / null). **플레이어와 AI 가
## 같은 값을 여기 둔다** — 플레이어 쪽 `_pending_play["target"]` 은 오버레이가
## 체인을 끊었다 이었다 하는 사정 때문에 존재하고, AI 쪽에는 `_pending_play`
## 자체가 없다. 절 구현이 대상을 물을 곳은 하나여야 한다.
var _current_target: Variant = null
## 직전 공격 절이 **몇 대 맞혔는가 / 몇을 눕혔는가.** `|per_hit` 을 단 뒤
## 절들이 읽는다(충전 · 카드 생성 · 회복 · 반응 장갑) — 그 절들은 자기가
## 때리지 않으므로 앞 절의 결과를 물어볼 곳이 필요하다.
var _last_attack_hits: int = 0
var _last_attack_kills: int = 0
## 지금 카드가 손패에서 몇 번째 자리에 있었는가. [명상] 이 "이 카드보다
## 왼쪽"을 세는 근거이고, 카드가 손패를 떠나기 직전에 찍힌다. -1 = 모름
## (AI 경로 · 손패 밖에서 발동한 카드).
var _current_card_index: int = -1
## 직전 `discard_left` 가 버린 장수. [명상] 의 `draw_discarded` 가 읽는다.
var _last_discarded_count: int = 0

# ─── Deck setup ───────────────────────────────────────────────────────────────
# Per-pilot 6-card draw: every pilot pulls 6 cards from the DB pool and tags them
# with itself as the 시전자. All 5 pilots' stacks shuffle together into the team
# deck — same logic for player and AI sides. Deck size is 5 × 6 = 30 per side.
#
# The 6 split into two halves that are drawn from different pools:
#   • 메크 카드 — **배정된 기체가 통째로 들고 온다.** `mech_cards.csv` 에서 그
#     기체의 행을 전부 집어 `count` 만큼 펼친 것이 이 절반이고, 그래서 장수가
#     기체마다 2~7장으로 다르다(덱 크기가 곧 기체 선택의 일부다). 아래
#     `MECH_CARDS_PER_PILOT` 는 **기체가 없을 때만** 쓰이는 폴백 상수로 남았다 —
#     match_ctx 없이 BattleSim.tscn 을 직접 돌리는 경로에서 cards.csv 의
#     `card_type = mech` 공용 카드 3장을 뽑는다.
#   • 파일럿 카드 3장 — `card_type = pilot`, and *which* 3 depends on the role:
#       정글러      → 정글 2 + 드로우 1
#       서포터      → 라인전 1 + 드로우 2
#       그 외 3인   → 라인전 2 + 드로우 1
const MECH_CARDS_PER_PILOT:  int = 3
const PILOT_CARDS_PER_PILOT: int = 3


func build_starter_decks() -> void:
	# Drop any drag state held over from the previous match (the game restart
	# path queue_frees player_card_nodes without touching the description box /
	# drag refs we manage here).
	deselect_current_card()
	_hide_description_box()
	_bs.player_deck.clear(); _bs.ai_deck.clear()
	_bs.player_discard.clear(); _bs.ai_discard.clear()
	# 새 판이면 배분 표도 백지에서 시작한다 — 재시작 경로가 같은 함수를 다시
	# 지나므로 비우지 않으면 이전 판의 PilotData 키가 남는다.
	_bs.starter_cards.clear()
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
	# 양 팀은 **빈 손**으로 시작한다. 손패는 `ECONOMY_START_TURN` 부터 도는 BATTLE
	# 자동 드로우로만 채워진다 — 그 전 구간은 카드가 아예 없는 순수 라인전이다.
	# 재시작 경로는 이미 비우고 들어오지만, 이전 판의 카드 노드가 남지 않도록
	# 여기서 한 번 더 확실히 비운다.
	_clear_hands()
	# 차례 교대 기록도 새 판에서는 백지 — 첫 선은 블루가 잡는다.
	_last_turn_side = -1
	_player_pass_lock = false


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
		# 상호 배타 장부는 **한 파일럿의 6장 전체**를 가로지른다 — 슬롯마다
		# 새로 만들면 메크 슬롯과 라인전 슬롯이 같은 그룹을 한 장씩 집어 갈 수
		# 있다. `_sample` 이 고른 카드의 그룹을 여기에 적어 나간다.
		var claimed: Dictionary = {}
		# 메크 카드는 **뽑는 것이 아니라 따라오는 것**이다 — 배정된 기체의 카드
		# 목록을 `count` 만큼 펼친 것이 곧 이 파일럿의 메크 절반이다. 기체가
		# 없을 때만(BattleSim.tscn 단독 실행) 예전처럼 공용 메크 카드 3장을
		# 뽑는 폴백으로 떨어진다.
		var mech_defs: Array = _mech_card_defs_for(p)
		var mech_picks: Array = []
		if mech_defs.is_empty():
			mech_picks = _sample(
					_cards_of_type(eligible, CardData.TYPE_MECH),
					MECH_CARDS_PER_PILOT, eligible, claimed)
		var pilot_picks: Array = []
		for slot in _pilot_slots_for(p):
			var cat: String = String(slot[0])
			var count: int  = int(slot[1])
			pilot_picks.append_array(_sample(
					_cards_in_category(eligible, cat), count, eligible, claimed))
		# 배분 표는 **덱에 들어간 사본**을 가리킨다 — 풀의 원본을 적어 두면 그
		# 카드의 비용 증가(정밀 이동의 `return_left`)처럼 사본에만 찍히는 값이
		# 상세 패널에서 안 보인다.
		var record: Dictionary = {"mech": [], "pilot": []}
		for def_raw in mech_defs:
			var def: Dictionary = def_raw as Dictionary
			# `count = 0` 인 카드는 덱에 들어가지 않는다 — 다른 효과가 만들어 줄
			# 때만 세상에 나오는 카드(승전보 · 철거 · 처형 · 락온 · 고통과 쾌감 ·
			# 단계 B/C)이고, 그래도 **배분 표에는 적는다**: 상세 패널의 메크 탭이
			# "이 기체가 무엇을 하는 기체인가"를 보여 주는 자리라, 조건부로만
			# 나오는 카드가 거기서 통째로 빠지면 기체를 반만 읽게 된다.
			var deck_copies: int = max(0, int(def.get("count", 1)))
			var shown: CardData = null
			for _i in deck_copies:
				var cd := make_mech_card(def)
				cd.owner_pilot = p
				out_deck.append(cd)
				if shown == null:
					shown = cd
			if shown == null:
				shown = make_mech_card(def)
				shown.owner_pilot = p
			record["mech"].append(shown)
		for src_raw in mech_picks:
			record["mech"].append(_deal_one(src_raw as CardData, p, out_deck))
		for src_raw in pilot_picks:
			record["pilot"].append(_deal_one(src_raw as CardData, p, out_deck))
		_bs.starter_cards[p] = record


## 이 파일럿에게 배정된 기체의 카드 행들. 기체가 없으면(match_ctx 없이
## BattleSim.tscn 을 직접 돌린 경우) 빈 배열이고, 호출 측이 공용 메크 카드
## 폴백으로 떨어진다.
func _mech_card_defs_for(p: PilotData) -> Array:
	var gm: Node = _bs.gm
	if gm == null:
		return []
	var pd: PlayerData = _bs.player_data_for(p)
	if pd == null or pd.assigned_mech == null:
		return []
	return gm.mech_cards_for(pd.assigned_mech.id)


## 풀의 원본 한 장을 시전자 사본으로 떠 덱에 넣고, 그 사본을 돌려준다.
func _deal_one(src: CardData, p: PilotData, out_deck: Array) -> CardData:
	var copy := make_card_copy(src)
	copy.owner_pilot = p
	out_deck.append(copy)
	return copy


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
##
## `claimed` is the pilot's 상호 배타 ledger (`excl_group` → true), shared across
## every slot of that one pilot and **mutated here**. A card whose group is
## already claimed is passed over on the first sweep; the repeat-fallback ignores
## the ledger, because a short deck is the worse failure of the two.
func _sample(src: Array, n: int, fallback: Array,
		claimed: Dictionary = {}) -> Array:
	if n <= 0:
		return []
	var bag: Array = (src if not src.is_empty() else fallback).duplicate()
	if bag.is_empty():
		return []
	bag.shuffle()
	var out: Array = []
	var relaxed: bool = false
	while out.size() < n:
		if bag.is_empty():
			# Pool smaller than the slot asks for (or emptied by the exclusion
			# sweep) — refill and allow repeats, exclusions no longer enforced.
			bag = (src if not src.is_empty() else fallback).duplicate()
			bag.shuffle()
			relaxed = true
		var cd := bag.pop_back() as CardData
		if not relaxed and not cd.excl_group.is_empty():
			if claimed.has(cd.excl_group):
				continue
			claimed[cd.excl_group] = true
		out.append(cd)
	return out


## Empties both hands and frees the player's card nodes, so a fresh match always
## starts from a genuinely empty hand. `_on_restart_pressed` already does this on
## its way in; this keeps the precondition local to the deck build.
func _clear_hands() -> void:
	for node in _bs.player_card_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_bs.player_card_nodes.clear()
	_bs.player_hand.clear()
	_bs.ai_hand.clear()


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
	cd.excl_group  = String(def.get("excl_group", ""))
	return cd


## `mech_cards.csv` 한 행 → CardData 한 장. `cards.csv` 쪽 행과 컬럼이 다르므로
## 팩토리도 따로다 — 저쪽에는 없는 `mech_id` / `count` / `trigger` 가 있고, 이쪽에는
## 없는 덱 슬롯 컬럼(card_type / card_cat / excl_group / scope / pool)이 있다.
##
## **시전자 제약은 붙지 않는다**(`scope = any`). 메크 카드의 임자는 배정된 기체가
## 정하므로 레인/정글 필터를 한 번 더 씌우면 정글러가 자기 기체 카드를 못 받는
## 자리가 생긴다 — 이동 카드를 들고 오는 메크가 여럿이다.
func make_mech_card(def: Dictionary) -> CardData:
	var cd := CardData.new(
			String(def.get("name", "?")),
			int(def.get("cost", 0)),
			String(def.get("description", "")))
	cd.uses         = 1
	cd.cast_method  = String(def.get("cast_method", "instant"))
	cd.target       = String(def.get("target", "hand"))
	cd.cast_range   = int(def.get("cast_range", 0))
	cd.area         = int(def.get("area", 0))
	cd.keyword      = String(def.get("keyword", ""))
	cd.effect       = String(def.get("effect", ""))
	cd.trigger      = String(def.get("trigger", ""))
	cd.scope        = CardData.SCOPE_ANY
	cd.pool         = 0
	cd.card_type    = CardData.TYPE_MECH
	cd.card_cat     = CardData.CAT_NONE
	cd.mech_card_id = int(def.get("id", -1))
	cd.mech_id      = int(def.get("mech_id", -1))
	return cd


## 메크 카드 한 장을 **행 id 로** 만든다. 효과가 카드를 지목해 만들 때
## (`gen_hand:13` / `gen_deck:39` / `search_card:7`) 쓰는 유일한 진입점이다.
## 알 수 없는 id 는 null — 카드 한 장을 못 만드는 것과 매치가 죽는 것은 무게가
## 다르므로 경고만 남긴다.
func make_mech_card_by_id(card_id: int, owner: PilotData) -> CardData:
	var gm: Node = _bs.gm
	if gm == null:
		return null
	var def: Dictionary = gm.mech_card_def(card_id)
	if def.is_empty():
		push_warning("CardPhaseManager: 메크 카드 id=%d 를 mech_cards 에서 찾지 못했다" % card_id)
		return null
	var cd := make_mech_card(def)
	cd.owner_pilot = owner
	return cd


# ─── 오브젝트 보상 카드 지급 ─────────────────────────────────────────────────
# 전령 / 용을 가져간 팀에게 카드를 쥐여 주는 두 진입점. 보상 카드는 `pool = 0`
# 이라 스타터 덱에는 절대 들어가지 않고, **오직 여기로만** 세상에 나온다.
#
# **보상 카드에는 시전자가 없다**(`owner_pilot == null`). 오브젝트는 팀이 먹은
# 것이지 누가 먹은 것이 아니고, 시전자를 붙이면 그 파일럿이 쓰러진 동안 보상이
# 통째로 잠긴다(카드 잠금은 시전자 생존을 본다). 대신 사거리 기준점이 사라지므로
# 대상 계산 쪽이 caster == null 을 "전장 전체"로 읽는다 —
# `compute_valid_pilot_targets` / `compute_valid_location_targets` 참조.

## cards.csv 의 한 행을 id 로 집어 시전자 없는 CardData 한 장을 만든다.
## 카드가 DB 에 없으면 null (게임을 세우지 않고 로그만 남긴다 — 보상을 못 받는
## 것과 매치가 죽는 것은 다른 무게다).
func make_objective_card(card_id: int) -> CardData:
	var gm: Node = _bs.gm
	if gm == null:
		return null
	for raw_def in gm.card_pool_bs:
		var def: Dictionary = raw_def as Dictionary
		if int(def.get("id", -1)) != card_id:
			continue
		var cd := _make_card_from_def(def)
		cd.owner_pilot = null
		return cd
	push_warning("CardPhaseManager: 보상 카드 id=%d 를 cards 테이블에서 찾지 못했다" % card_id)
	return null


## 보상 카드 `count` 장을 **손패로 곧장** 넣는다(전령). 손패 상한은 보지 않는다 —
## 자기 차례에 들어온 카드가 상한을 넘겨도 버리지 않는 기존 규칙과 같고, 어차피
## 전령 보상은 `보존` 키워드라 다음 자동 버리기도 이 카드를 건너뛴다.
## 실제로 들어간 장수를 돌려준다.
func grant_cards_to_hand(card_id: int, is_player: bool, count: int) -> int:
	var added: int = 0
	for _i in max(0, count):
		var cd := make_objective_card(card_id)
		if cd == null:
			break
		add_card_to_hand(cd, is_player)
		added += 1
	if added > 0:
		_refresh_hand_after_bulk_change(is_player)
		update_deck_discard_labels()
	return added


## 보상 카드 `count` 장을 **덱에 섞어 넣는다**(용). 맨 위에 쌓지 않는 이유는
## 5장이 한꺼번에 손에 들어오면 그 다음 몇 번의 드로우가 통째로 보상 카드가 되어
## 덱이 잠기기 때문이다 — 섞어 넣으면 경기 후반에 걸쳐 한 장씩 나온다.
## 실제로 들어간 장수를 돌려준다.
func grant_cards_to_deck(card_id: int, is_player: bool, count: int) -> int:
	var deck: Array = _bs.player_deck if is_player else _bs.ai_deck
	var added: int = 0
	for _i in max(0, count):
		var cd := make_objective_card(card_id)
		if cd == null:
			break
		deck.append(cd)
		added += 1
	if added > 0:
		deck.shuffle()
		update_deck_discard_labels()
	return added


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
	cd.excl_group  = src.excl_group
	cd.mech_card_id = src.mech_card_id
	cd.mech_id      = src.mech_id
	cd.trigger      = src.trigger
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
	# 오브젝트 결정 창 / 무대가 열려 있는 동안은 턴이 돌면 안 된다. BattleSim 이
	# 이미 틱을 붙잡고 있지만(`_battle_tick_held`), 상대 차례 가드와 같은 이유로
	# 여기에도 백스톱을 둔다 — 이 함수는 await 를 품고 있어 재진입 가능하다.
	if _bs.objective != null and _bs.objective.is_busy():
		return
	_bs.sim_core.simulate_turn()
	if _bs.game_over:
		return
	# **오브젝트는 차례와 상관없이 발생한다.** 그래서 카드 경제(전략 점수 회복 /
	# 자동 드로우)와 작전 단계 판정보다 **앞**에 온다 — 전령이 열리는 턴에
	# 마침 문턱을 넘었다고 해서 오브젝트가 한 턴 밀리면 안 된다. 결정 창과
	# 교전 무대가 여기서 통째로 await 되고, 끝난 뒤 평소의 턴 마무리가 이어진다.
	if _bs.objective != null:
		await _bs.objective.process_turn()
		if _bs.game_over:
			return
	# 카드 경제 게이트. `ECONOMY_START_TURN` 전까지는 전략 점수도 자동 드로우도
	# 멈춰 있다 — 개시 손패가 없으므로 그 구간은 **양 팀 다 빈 손**이고, 0턴에
	# 들어가 있는 것은 블루 선점 1점뿐이다. 초반 몇 턴은 카드 없이 라인전만
	# 하라는 규칙이다. 카운터 자체를 굴리지 않으므로 게이트가 풀리는 턴에 밀린
	# 회복이 한꺼번에 터지지도 않는다.
	#
	# `simulate_turn()` 이 자기 초입에서 `turn_count` 를 올리므로, 이 시점의
	# `turn_count` 는 **방금 끝난 턴의 번호**(1-based)다. 카운터는 개시 시
	# `INTERVAL - 1` 로 놓여 있어 게이트가 열리는 첫 턴에 곧바로 발동한다 —
	# ECONOMY_START_TURN = 10 이면 10턴째에 첫 회복 / 첫 드로우가 들어간다.
	if _bs.turn_count >= _bs.ECONOMY_START_TURN:
		_bs.cost_counter += 1
		if _bs.cost_counter >= _bs.COST_RECOVERY_INTERVAL:
			_bs.cost_counter = 0
			# **문턱 위에서는 회복하지 않는다.** 점수는 쓸 차례를 기다리는
			# 자원이지 쌓아 두는 자원이 아니다 — 이미 차례를 가질 수 있는
			# 쪽에 더 얹어 봐야 다음 차례에 쓸 수 없는 점수만 불어난다
			# (턴을 넘기면 문턱 초과분은 어차피 소멸한다, end_card_phase 참조).
			# 양 팀에 같은 규칙으로 건다.
			if _bs.player_cost < _bs.PHASE_THRESHOLD:
				_bs.player_cost += _bs.COST_RECOVERY
			if _bs.ai_cost < _bs.PHASE_THRESHOLD:
				_bs.ai_cost += _bs.COST_RECOVERY
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
				if not last_draw_merged:
					spawn_card_node(drawn)
				# 손패가 바뀌었다 — 카드 없이 넘긴 차례의 잠금이 풀린다.
				_player_pass_lock = false
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
## 진입한다 — 대신 플레이어 쪽에는 **패스 잠금**(`_player_pass_lock`)이 붙는다.
##
## **패스 잠금이 필요한 이유.** 턴 넘기기의 조건이 "카드를 한 장 이상 낼 것"
## 이었을 때는 그 규칙이 곧 "넘기고 나면 점수가 문턱 아래로 내려간다"의
## 보증이었다. 지금은 한 장도 안 내고 넘길 수 있고 문턱 초과분만 깎이므로,
## 넘긴 직후에도 점수는 정확히 문턱에 걸려 있다 — 규칙 1 대로라면 다음 틱
## (0.5초 뒤)에 "당신의 차례"가 다시 뜬다. 그래서 넘긴 쪽은 **손패가 바뀌거나
## 상대가 한 번 차례를 가질 때까지** 준비되지 않은 것으로 친다. 그 사이
## BATTLE 은 평소대로 흐른다.
func _next_turn_side() -> int:
	var player_ready: bool = _bs.player_cost >= _bs.PHASE_THRESHOLD \
			and not _player_pass_lock
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
## 효과다. `보존` 키워드를 단 카드(오브젝트 보상)도 같이 건너뛴다. 손패가 통째로
## 보존되는 경우에도 루프가 멈추도록 인덱스 스캔으로 돈다: 상한 초과가 남아도
## 무한 루프는 없다.
func _trim_hand_overflow(is_player: bool) -> int:
	var hand:    Array = _bs.player_hand    if is_player else _bs.ai_hand
	var discard: Array = _bs.player_discard if is_player else _bs.ai_discard
	_prune_preserved(is_player)
	var preserved: Array = _bs.preserved_cards_p if is_player else _bs.preserved_cards_ai
	var dropped: int = 0
	var i: int = 0
	while hand.size() > _bs.MAX_HAND_SIZE and i < hand.size():
		var oldest := hand[i] as CardData
		if preserved.has(oldest) or oldest.is_preserved_by_keyword():
			i += 1
			continue
		hand.remove_at(i)
		send_to_discard(oldest, discard)
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
	# 자기 차례가 열리면 패스 잠금은 그 역할을 다한 것이다 — 넘긴 뒤 다시
	# 여기까지 온 것 자체가 잠금이 풀렸다는 뜻이지만, 상태를 여기서 한 번 더
	# 백지로 돌려 다음 넘기기가 깨끗한 잠금으로 시작하게 한다.
	_player_pass_lock = false
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
## 자기 작전 단계가 닫힐 때 도는 스킬 정산 — 몰아치기의 충전이 비워지고
## 전투 명령의 단계 효과가 걷힌다. `end_card_phase`(플레이어)와 `_run_ai_turn`
## (AI)이 둘 다 마지막에 부른다.
func _notify_skill_phase_end(is_player: bool) -> void:
	# 메크 쪽 단계 정산 — 취약 각인이 걷히고 탈진이 풀린다.
	if _bs.mech_skill != null:
		_bs.mech_skill.on_phase_end(is_player)
	if _bs.skill != null:
		_bs.skill.on_phase_end(is_player)


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
	# The description box answers "what is the hand pointing at?", so it follows
	# the same gate: a dimmed hand has no focus to describe.
	_refresh_description_box()


# **자기 차례는 언제든 넘길 수 있다 — 카드를 한 장도 내지 않아도 된다.**
# 남는 조건은 전부 "지금 넘기면 무언가가 중간에 끊긴다"는 것뿐이다(모달 픽,
# 상대 차례, 돌진 연출, VS 확인 화면, 차례 배너).
#
# 규칙의 이력이 둘 있다. 처음에는 "점수를 문턱 아래로 내렸을 것"이었는데,
# 28장 중 9장이 0코스트라 낼 수 있는 카드가 전부 무료면 점수가 줄지 않아
# 턴을 영영 넘기지 못했다(작전 단계 동안 BATTLE 이 멈추므로 손패도 안 바뀐다).
# 그래서 "카드를 한 장 이상 냈을 것"으로 바뀌었고, 낼 게 하나도 없는 손만
# 예외로 통과시켰다. 지금은 그 예외가 규칙을 삼켰다 — 점수는 문턱 위인데
# 손에 낼 게 없거나, 그냥 지금은 쓰고 싶지 않은 경우가 실제로 흔하고,
# "무언가 하나는 내라"를 강제하면 아무 카드나 버리듯 내게 된다.
# 대신 넘긴 쪽은 `end_card_phase` 에서 문턱 초과분을 잃고 패스 잠금을 진다.
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
	# 공격 돌진 연출이 도는 동안에는 턴도 넘길 수 없다 — 연출 중간에 단계가
	# 닫히면 시전자가 파고든 자세 그대로 BATTLE 이 재개된다.
	if _attack_anim_active:
		return false
	# 전투 개시 VS 확인 화면도 마찬가지다 — 그 화면이 떠 있는 동안 카드는 이미
	# 손패를 떠나 `_pending_play` 에 매달려 있고 game_phase 는 아직 CARD_PHASE 라,
	# 여기서 단계를 닫으면 확인/취소를 기다리던 체인이 갈 곳을 잃는다.
	if _bs.engage_phase != null and _bs.engage_phase.is_intro_active():
		return false
	if _player_turn_announce_in_progress:
		return false
	return true


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
	if _bs.engage_phase != null and (_bs.engage_phase.is_active()
			or _bs.engage_phase.is_intro_active()):
		return false
	return true


# Ends the *player's* 작전 단계 and hands control back to BATTLE.
#
# 넘기는 순간 세 가지가 함께 일어난다.
#   1. **문턱 초과분 소멸** — 점수는 정확히 `PHASE_THRESHOLD` 로 깎인다. 차례를
#      쓰지 않고 넘긴 대가이고, 문턱 위에서 회복이 멈추는 규칙(do_battle_turn)과
#      짝을 이뤄 "점수는 쟁여 두는 자원이 아니다"를 만든다.
#   2. **패스 잠금** — 손패가 바뀌거나 상대가 한 번 차례를 갖기 전까지 내 차례는
#      다시 열리지 않는다 (`_player_pass_lock`, `_next_turn_side` 주석 참조).
#   3. **상대가 문턱 위면 그 자리에서 상대 차례** — 다음 BATTLE 틱을 기다리지
#      않는다. 내 점수와는 무관하다(내 차례는 방금 끝났으므로).
#      `_ai_turn_ready()` 로 묻는 것은 "낼 카드도 있는가"까지 포함하기
#      위해서다 — 점수만 보고 부르면 아무것도 안 하는 "상대 차례" 배너가 뜬다.
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
	var burned: int = maxi(0, _bs.player_cost - _bs.PHASE_THRESHOLD)
	if burned > 0:
		_bs.player_cost = _bs.PHASE_THRESHOLD
	_player_pass_lock = true
	# 계획 살인의 예약은 그 작전 단계 안에서만 유효하다 — 안 터졌으면 사라진다.
	_bs.kill_bounty_p = 0
	_notify_skill_phase_end(true)
	_bs.blog.log_event("PHASE", "작전 단계 종료 → BATTLE (남은 %d점%s)"
			% [_bs.player_cost, "" if burned == 0 else ", 초과 %d점 소멸" % burned])
	_bs.renderer.queue_redraw()
	_bs.hud.update_hud()
	_apply_hand_dim_state()
	# 상대가 이미 문턱 위라면 곧바로 상대 차례로 넘어간다.
	if _ai_turn_ready():
		_last_turn_side = 1
		await _run_ai_turn()


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
# re-announce "상대 차례" every single tick and play nothing. The affordability
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
	_notify_skill_phase_end(false)
	# 플레이어와 같은 규칙 — 차례를 놓는 쪽은 문턱 초과분을 잃는다.
	var burned: int = maxi(0, _bs.ai_cost - _bs.PHASE_THRESHOLD)
	if burned > 0:
		_bs.ai_cost = _bs.PHASE_THRESHOLD
	# 상대가 차례를 가졌으니 플레이어의 패스 잠금이 풀린다.
	_player_pass_lock = false
	_bs.blog.log_event("PHASE", "상대 차례 종료 → BATTLE (남은 %d점%s)"
			% [_bs.ai_cost, "" if burned == 0 else ", 초과 %d점 소멸" % burned])
	_ai_play_in_progress = false
	highlight_affordable_cards()
	_bs.renderer.queue_redraw()
	_bs.hud.update_hud()


# ─── Card draw ────────────────────────────────────────────────────────────────
# ─── 스택 (핸드에서 뭉치는 카드) ─────────────────────────────────────────────
# `스택` 키워드를 단 카드는 손패에서 같은 카드끼리 **한 장으로** 뭉친다. 뭉친
# 카드는 손패 배열에 **한 항목**으로만 존재하고 `stack_count` 가 몇 장인지를
# 들고 있으므로, 손패 크기 · 상한 초과 정리 · 부채꼴 레이아웃 · 히트 밴드가
# 전부 그 뭉치를 한 장으로 센다 — 그 셋을 따로 고칠 필요가 없다는 것이 이
# 표현을 고른 이유다.
#
# 뭉치는 곳은 손패뿐이다. 덱과 버린 더미에는 낱장으로 눕고(`send_to_discard`),
# 손패로 들어올 때 다시 뭉친다.

## 손패에 이미 서 있는 같은 뭉치. 없으면 null.
func _stack_partner_in_hand(cd: CardData, hand: Array) -> CardData:
	if cd == null or not cd.is_stackable():
		return null
	for raw in hand:
		var other := raw as CardData
		if other != cd and other.stacks_with(cd):
			return other
	return null


## 카드 한 장을 손패에 넣는 **유일한 진입점**. 뭉칠 수 있으면 뭉치고(그때는
## 노드를 새로 세우지 않고 이미 서 있는 카드의 `xN` 배지만 올린다), 아니면
## 평소대로 손패에 앉히고 노드를 세운다.
##
## 새 카드가 실제로 손패 한 자리를 차지했으면 true, 뭉쳐서 흡수됐으면 false.
## 드로우 연출을 걸지 말지를 호출 측이 이 값으로 가른다.
func add_card_to_hand(cd: CardData, is_player: bool, at_left: bool = false) -> bool:
	if cd == null:
		return false
	var hand: Array = _bs.player_hand if is_player else _bs.ai_hand
	var partner: CardData = _stack_partner_in_hand(cd, hand)
	if partner != null:
		partner.stack_count += cd.stack_count
		if is_player:
			refresh_stack_node(partner)
		return false
	if at_left:
		hand.insert(0, cd)
	else:
		hand.append(cd)
	if is_player:
		spawn_card_node(cd, at_left)
	else:
		_bs.hud.update_ai_hand_visuals()
	return true


## 이 카드의 손패 노드에 뭉치 표시를 다시 그린다. 노드가 없으면(AI 쪽 · 아직
## 안 선 카드) 조용히 넘어간다.
func refresh_stack_node(cd: CardData) -> void:
	for raw in _bs.player_card_nodes:
		var c := raw as Card
		if c.data == cd:
			c.refresh_stack_badge()
			return


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
	if draw_disc > 0 and card.is_playable():
		card.cost = max(0, card.cost - draw_disc)
	# 뽑힌 카드가 손패의 같은 뭉치에 흡수되면 손패 크기가 늘지 않는다 —
	# `last_draw_merged` 가 그 신호이고, 호출 측은 이 값을 보고 드로우 연출을
	# 건너뛴다(카드 노드가 새로 서지 않으므로 날아올 카드가 없다).
	hand.append(card)
	var partner: CardData = _stack_partner_in_hand(card, hand)
	last_draw_merged = partner != null
	if partner != null:
		hand.erase(card)
		partner.stack_count += card.stack_count
		if is_player:
			refresh_stack_node(partner)
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
## **버린 더미 숫자는 배열보다 늦게 따라온다.** 카드가 손패에서 떨어지고
## (`Card.DISCARD_FADE_SEC`) 그 다음 잔상이 뭉치 위로 내려앉아 착지를 마친
## 시점에야 장수가 오른다 — 그래서 `_discard_pending`(아직 화면에 안 들어온
## 장수)을 빼고 표시한다. 줄어드는 쪽(리셔플)은 즉시 반영된다.
func update_deck_discard_labels() -> void:
	if _reshuffle_tween != null and _reshuffle_tween.is_running():
		_reshuffle_tween.kill()
	_deck_displayed    = float(_bs.player_deck.size())
	_notice_discard_gain()
	_discard_displayed = float(_bs.player_discard.size() - _discard_pending)
	_refresh_count_labels()


## Tween: discard `old_discard → new_discard` and deck `0 → new_deck` in
## parallel over BS_RESHUFFLE_TWEEN_DUR. Called when draw_card reshuffles.
func _animate_reshuffle_counts(old_discard: int, new_deck: int, new_discard: int) -> void:
	if _reshuffle_tween != null and _reshuffle_tween.is_running():
		_reshuffle_tween.kill()
	# 리셔플은 버린 더미를 통째로 덱으로 되돌리는 동작이라, 지연 정산을 기다리는
	# 장수가 남아 있으면 트윈이 끝난 뒤 유령 장수가 다시 더해진다.
	_discard_seen    = new_discard
	_discard_pending = 0
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
	# 뭉치는 소수 카운트를 그대로 받는다 — 리셔플 트윈이 도는 동안 두께(층 수)도
	# 숫자와 같은 곡선으로 자라고 줄어든다.
	if _bs.pile_deck != null:
		_bs.pile_deck.set_count(_deck_displayed)
	if _bs.pile_discard != null:
		_bs.pile_discard.set_count(_discard_displayed)


# ─── 버린 더미 착지 연출 ──────────────────────────────────────────────────────
# 버린 더미가 카드를 받는 자리는 일곱 군데다(카드 사용 / 버리기:N / 상한 초과
# 정리 / 과감한 정리 …). 일곱 군데를 전부 부르는 대신 **장수가 늘어난 것을
# 한 곳에서 알아챈다** — `update_deck_discard_labels` 은 어차피 그 일곱 군데가
# 모두 지나는 자리이고(숫자가 안 바뀌면 화면도 안 바뀐다), 리셔플처럼 장수가
# 줄어드는 경우는 델타가 음수라 저절로 걸러진다.
##
## 손패에서 떨어지는 카드와 착지를 잇는 지연(s). **손패 카드의 낙하가 완전히
## 끝난 뒤**에 더미가 받는다 — 한 장의 카드가 손에서 떨어져 더미로 들어가는
## 한 동작이 되도록 두 연출을 겹치지 않고 이어 붙인 것이다. (예전에는 0.16초
## 라 카드가 아직 반쯤 떨어지는 중에 더미가 먼저 받아, 같은 카드가 두 군데에
## 동시에 있었다.)
const PILE_LAND_DELAY_SEC := Card.DISCARD_FADE_SEC
## 한 번에 몇 장까지 잔상을 띄울 것인가. 리셔플 직후처럼 한꺼번에 열 장 넘게
## 들어오면 잔상이 겹쳐 뭉개지기만 한다.
const PILE_LAND_MAX_GHOSTS := 3

## 직전에 본 버린 더미 장수 — 델타를 재는 기준.
var _discard_seen: int = 0
## 배열에는 들어왔지만 **아직 화면에 반영하지 않은** 장수. 잔상이 다 내려앉는
## 순간 `_commit_discard_gain` 이 이만큼 털어 내고, 그때 숫자와 뭉치 두께가
## 함께 오른다. 표시값은 언제나 `배열 크기 - 이 값`이다.
var _discard_pending: int = 0


func _notice_discard_gain() -> void:
	var now: int = _bs.player_discard.size()
	var gained: int = now - _discard_seen
	_discard_seen = now
	if gained < 0:
		# 줄어들었다 = 리셔플. 밀린 정산을 붙들고 있을 이유가 없다.
		_discard_pending = 0
		return
	if gained == 0:
		# 장수가 그대로면 아무 일도 없었다 — **밀린 정산은 건드리지 않는다.**
		# 이 함수는 `update_deck_discard_labels` 이 불릴 때마다 도는데 그 대부분은
		# 델타 0 인 단순 갱신이고(드로우 / 손패 재배치 / HUD 갱신 …), 여기서
		# `_discard_pending` 을 0 으로 밀면 다음 갱신 한 번에 지연이 통째로
		# 날아가 잔상이 채 내려앉기도 전에 숫자가 올라간다(실측으로 잡은 버그).
		return
	if _bs.pile_discard == null:
		# HUD 가 아직 없으면 연출도 없다 — 지연 없이 그대로 반영한다.
		return
	var ghosts: int = mini(gained, PILE_LAND_MAX_GHOSTS)
	_discard_pending += gained
	_bs.pile_discard.play_burst(true, ghosts, PILE_LAND_DELAY_SEC)
	# 마지막 잔상이 완전히 내려앉는 시점 = 착지 지연 + (장수-1)×스태거 + 잔상 1장.
	_commit_discard_gain(gained, PILE_LAND_DELAY_SEC
			+ float(ghosts - 1) * CardPileStack.GHOST_STAGGER_SEC
			+ CardPileStack.GHOST_SEC)


## 잔상이 다 내려앉은 뒤에 장수를 실제로 올린다. 트윈이 아니라 타이머로 기다리는
## 것은 드로우 인트로와 같은 이유다 — 도중에 노드가 사라져도 코루틴이 매달리지
## 않는다. `await` 없이 호출한다(불꽃놀이처럼 던져 두는 코루틴).
func _commit_discard_gain(n: int, wait: float) -> void:
	var tree := get_tree()
	if tree != null:
		await tree.create_timer(wait).timeout
	if not is_instance_valid(_bs):
		return
	_discard_pending = maxi(0, _discard_pending - n)
	# 리셔플 트윈이 도는 중이면 표시값의 주인은 그쪽이다 — 여기서 덮어쓰면
	# 되돌아가는 숫자가 한 프레임 튄다.
	if _reshuffle_tween != null and _reshuffle_tween.is_running():
		return
	_discard_displayed = float(_bs.player_discard.size() - _discard_pending)
	_refresh_count_labels()


# ─── Card node helpers ────────────────────────────────────────────────────────
## Builds the visual node for a card that just entered the player's hand.
##
## `at_left` puts it at the **head** of `player_card_nodes` instead of the tail,
## i.e. the leftmost slot of the fan — `relayout_hand` reads position purely
## from the array index, so this one flag is the whole "손패 맨 왼쪽" rule
## (정밀 이동 / `return_left`). Callers must insert into `_bs.player_hand` at the
## matching end; the two arrays are kept in the same order.
##
## `animate` decides whether the card plays the 드로우 인트로 (뒷면으로 화면
## 왼쪽에서 날아와 뒤집히며 안착 — `_play_draw_intro`). Two callers turn it off:
##   • `at_left` 복귀(정밀 이동) — 그 카드는 뽑힌 것이 아니라 **손패 왼쪽으로
##     되돌아오는** 것이라, 오른쪽 끝으로 날아가는 연출이 방향부터 어긋난다.
##   • `_restore_from_snapshot` — 취소 롤백은 손패를 통째로 다시 세우는
##     작업이라, 연출을 태우면 되돌린 손패 전체가 새로 뽑힌 것처럼 보인다.
func spawn_card_node(cd: CardData, at_left: bool = false,
		animate: bool = true) -> void:
	var node := _bs.CARD_SCENE.instantiate() as Card
	node.pivot_offset = Vector2(80.0, 110.0)
	_bs.canvas.add_child(node)
	# The hand's hit layer picks the mouse for every card in the row, so the
	# cards themselves must not — an overlapping card that claims its own rect
	# steals its neighbour's only clickable pixels (see _apply_hit_bands).
	_set_subtree_mouse_ignore(node)
	var intro: bool = animate and not at_left
	if intro:
		# 뒷면으로, 화면 왼쪽 바깥에서 출발한다. `relayout_hand` 가 건너뛰도록
		# 배열에 들어가기 **전에** intro_active 를 세운다.
		node.intro_active = true
		node.setup(cd, true, false)
		node.position = node.layout_position_from_global(_draw_entry_position())
	else:
		node.global_position = _bs.BS_HAND_CENTER  # start at hand center for spring-in
		node.setup(cd, true, true)
	# Hover brings the card to the top of the hand z-order and opens the
	# description box. `card_clicked` is deliberately left unwired: a click on a
	# hand card does nothing now — picking a card up is a drag, and the drag is
	# routed by the hit layer, not by the card.
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
	if intro:
		_play_draw_intro(node)


# ─── 드로우 인트로 ────────────────────────────────────────────────────────────
# 뽑힌 카드는 곧바로 자기 슬롯에 나타나지 않는다. **뒷면인 채로 화면 왼쪽 바깥
# 에서 나타나 손패 오른쪽 끝(= 새 카드가 앉을 자리) 위로 날아간 뒤, 그 자리에서
# 뒤집혀 내용을 드러내며 슬롯에 안착한다.** 세 박자가 각각 답하는 질문이 다르다:
# 어디서 왔는가(덱 = 왼쪽 카운터 쪽) → 어디에 앉는가(행의 오른쪽 끝) → 무엇인가
# (뒤집혀 드러나는 앞면).
#
# 연출이 도는 동안 그 카드는 `Card.intro_active` 라 **레이아웃 · 호버 · 잡기가
# 전부 비켜 간다** — 나머지 손패는 이미 새 카드 몫까지 자리를 좁힌 채 기다린다
# (`relayout_hand` 은 스폰 즉시 총 장수로 돌았고, 인트로 카드만 건너뛴다).
## 왼쪽 바깥 출발점이 화면 밖으로 얼마나 더 나가 있는가(px).
const DRAW_ENTRY_PAD_PX := 140.0
## 왼쪽 바깥 → 손패 오른쪽 끝까지 날아가는 시간(s).
const DRAW_FLY_SEC := 0.28
## 뒤집는 지점이 최종 슬롯보다 위로 뜨는 높이(px). 뒤집기를 슬롯 **위**에서
## 하는 이유는 그래야 뒤집힌 카드가 행 뒤로 숨지 않고 온전히 보이기 때문이고,
## 마지막 안착(슬롯으로 내려앉기)이 눈에 보이는 동작으로 남기 때문이다.
const DRAW_FLIP_LIFT_PX := 78.0
## 같은 프레임에 여러 장이 뽑힐 때(개시 5장 / 드로우:N / 재고) 출발 시각에 주는
## 간격(s). 없으면 다섯 장이 정확히 겹쳐 날아가 한 장처럼 보인다.
const DRAW_STAGGER_SEC := 0.07

## 지금 인트로가 걸려 있는 카드 수 — 스태거 간격을 이 값으로 잰다.
var _draw_intro_active: int = 0


## 뒷면 카드가 나타나는 화면 왼쪽 바깥 지점(뷰포트 좌표, 카드 좌상단 기준).
func _draw_entry_position() -> Vector2:
	return Vector2(-Card.CARD_W - DRAW_ENTRY_PAD_PX, _bs.BS_HAND_CENTER.y)


## 드로우 인트로 본체. `spawn_card_node` 가 fire-and-forget 으로 부른다.
##
## 각 박자를 **트윈의 `finished` 가 아니라 타이머로** 기다린다: 카드가 도중에
## free 되면(재시작 / 스냅샷 롤백 / 상한 초과 정리) 그 트윈의 `finished` 는
## 영영 오지 않아 코루틴이 매달린 채 카운터를 붙잡는다.
func _play_draw_intro(node: Card) -> void:
	_draw_intro_active += 1
	var delay: float = float(_draw_intro_active - 1) * DRAW_STAGGER_SEC
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	# ⓪ 덱 뭉치에서 카드 한 장이 떠오르며 사라진다 — 이 카드가 **어디서 왔는지**
	#    를 말하는 박자다. 다 사라지기를 기다리지 않고, 알파가
	#    `GHOST_HANDOFF_ALPHA` 만큼 남은 시점에 왼쪽 진입이 이어받는다: 완전히
	#    사라진 뒤에 시작하면 한 장이 두 번 나온 것처럼 끊겨 보인다.
	if _intro_alive(node) and _bs.pile_deck != null:
		_bs.pile_deck.play_pop()
		await get_tree().create_timer(CardPileStack.ghost_handoff_delay()).timeout
	# ① 왼쪽 바깥 → 손패 오른쪽 끝 위
	if _intro_alive(node):
		var total: int = _bs.player_card_nodes.size()
		var staging: Vector2 = slot_position(total - 1, total) \
				+ Vector2(0.0, -DRAW_FLIP_LIFT_PX)
		# 비행은 레이아웃 트윈(`Card.tween_to`)을 그대로 쓴다 — 카드 자신이 쥐고
		# 있는 트윈이라야 버리기 연출(`begin_discard_fx`)이 걷어 낼 수 있다.
		# 상한 초과 정리는 **가장 오래된 카드**를 버리는데, 그 카드가 아직 날아오는
		# 중일 수 있고, 그때 죽지 않은 비행 트윈이 남으면 떨어지는 카드를 도로
		# 손패 쪽으로 끌어올린다. 기울기는 0 으로 두고 날아온 뒤 안착에서 받는다.
		# EASE_IN_OUT / SINE 인 이유: 1200px 를 0.28초에 지나는 이동이라 앞이 무거운
		# 감속 곡선(EASE_OUT + CUBIC)에서는 첫 프레임에 이미 화면 오른쪽 끝에 닿아
		# "왼쪽에서 왔다"가 읽히지 않았다(실측: 0.10초에 77% 주파). 대칭 곡선이
		# 가로지르는 구간을 눈에 남긴다.
		node.tween_to(staging, 0.0, Vector2.ONE, DRAW_FLY_SEC,
				Tween.EASE_IN_OUT, Tween.TRANS_SINE)
		await get_tree().create_timer(DRAW_FLY_SEC).timeout
	# ② 그 자리에서 뒤집어 앞면을 드러낸다
	if _intro_alive(node):
		node.play_flip_reveal()
		await get_tree().create_timer(Card.FLIP_HALF_SEC * 2.0).timeout
	# ③ 손패에 넘겨 슬롯으로 안착시킨다
	if _intro_alive(node):
		node.intro_active = false
		relayout_hand(_bs.player_card_nodes)
		highlight_affordable_cards()
	elif is_instance_valid(node):
		node.intro_active = false
	_draw_intro_active = max(0, _draw_intro_active - 1)


## 인트로를 계속 진행해도 되는가 — 노드가 살아 있고 아직 손패의 일원인가.
func _intro_alive(node: Card) -> bool:
	return is_instance_valid(node) and node.intro_active \
			and _bs.player_card_nodes.has(node)


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


## The card the row currently spreads around: the **dragged** card if there is
## one, otherwise the card under the cursor.
##
## A dragged card is the hand's focus in exactly the same way a hovered one is —
## the row must open around it and stay open while the cursor walks out over the
## battlefield. Routing both states through this one accessor is also what makes
## the lift reversible: the focus card's own push offset is 0, so its pushed slot
## *is* its resting slot, and grab → drop can't leave it displaced by a stale
## push from whichever card happened to be hovered first.
func _push_focus_card() -> Card:
	if _drag_card != null and is_instance_valid(_drag_card) \
			and _bs.player_card_nodes.has(_drag_card):
		return _drag_card
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
		# A dragged card is owned by the cursor, not by the layout — every pass
		# has to leave its position alone until the drop resolves. A card still
		# playing its 드로우 인트로 is owned by the intro for the same reason.
		if node == skip or node.is_dragging or node.intro_active:
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
## card is actually being dragged — so it can't swallow anything the cards
## weren't covering anyway. The player 전략 포인트 도넛 clears its top edge by 28px.
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
	var lift: float = Card.PRESS_LIFT if _drag_card != null else 0.0
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


## The hand's whole pointer story: hover, click-to-select, and the drag.
##
## While a button is held the layer keeps Godot's mouse focus, so motion and the
## release keep arriving **even once the cursor has left the layer's rect** —
## that is what lets a card be dragged out over the battlefield and dropped on a
## pilot. Nothing else on screen has to cooperate.
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
	if _press_card != null:
		# Holding a card: far enough from the press point promotes it to a drag,
		# and from then on the card rides the cursor instead of the hover bands.
		if _drag_card == null and p.distance_to(_press_pos) > DRAG_THRESHOLD_PX:
			_begin_drag(p)
		if _drag_card != null:
			_update_drag(p)
	else:
		_update_hover_at(p)

	var pressed: bool  = false
	var released: bool = false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			pressed  = mb.pressed
			released = not mb.pressed
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		pressed  = st.pressed
		released = not st.pressed
	if not pressed and not released:
		return
	# The release is accepted so a drop over the battlefield doesn't also read as
	# a stray battlefield press; the press for symmetry, since the same gesture
	# owns both ends.
	_hand_hit_layer.accept_event()
	if released:
		_finish_press(p)
		return
	_update_hover_at(p)
	# Remember which card the finger went down on. **Nothing else happens yet** —
	# a press with no motion is not an action any more, so there is no state to
	# undo when the player simply lets go.
	_press_card = _grabbable_card_at(p)
	_press_pos = p


## The card a press at `p` could pick up, or null. Mirrors the gates
## `_begin_drag` would apply, so a press that can never become a drag doesn't
## even record itself.
func _grabbable_card_at(p: Vector2) -> Card:
	if _bs.game_phase != GameEnums.BattlePhase.CARD_PHASE:
		return null
	if _is_player_input_blocked():
		return null
	var card := _hand_card_at(p)
	if card == null or not is_instance_valid(card):
		return null
	# 아직 날아오는 중인 카드는 잡을 수 없다 — 인트로가 위치를 쥐고 있어서
	# 리프트 자세를 세워 봐야 다음 프레임에 덮어써진다.
	if card.intro_active:
		return null
	return card if _bs.player_card_nodes.has(card) else null


## Button released. Either the drag lands (and maybe plays the card), or the
## cursor never left the press point and this was a plain click — which now does
## nothing at all.
func _finish_press(p: Vector2) -> void:
	var was_dragging: bool = _drag_card != null
	_press_card = null
	if was_dragging:
		_end_drag(p)


func _on_hit_layer_mouse_exited() -> void:
	# A dragged card owns the cursor — the row must not re-evaluate hover from a
	# cursor that has simply walked off the hand on its way to the battlefield.
	if _drag_card != null:
		return
	_update_hover_at(Vector2(-1e9, -1e9))


# ─── Drag ────────────────────────────────────────────────────────────────────

## True while a card is being dragged out of the hand.
func is_dragging_card() -> bool:
	return _drag_card != null


## Promotes the held press into a real drag. **This is where a card becomes
## "active"** — the row spreads around it, the 대상 지정 오버레이 comes up, and
## the card takes one of the two held poses (see the 드래그 앤 드롭 header).
func _begin_drag(p: Vector2) -> void:
	var card: Card = _press_card
	if card == null or not is_instance_valid(card) \
			or not _bs.player_card_nodes.has(card):
		_press_card = null
		return
	if _bs.game_phase != GameEnums.BattlePhase.CARD_PHASE \
			or _is_player_input_blocked():
		_press_card = null
		return
	# 비용 -1 카드는 애초에 손을 떠나지 않는다 — 놓을 곳이 없는 카드를 끌어낼 수
	# 있으면 매번 제자리로 돌아오는 헛동작만 남는다. 단 **버리기 픽 중에는**
	# 끌린다: 못 내는 카드라고 못 버리는 것은 아니다.
	if not card.data.is_playable() and not _in_discard_pick_mode():
		_press_card = null
		return
	_drag_card = card
	# set_dragging locks in the "lifted highest of all" look (1.2× + tallest
	# shadow) so the card holds that pose once the cursor walks off the row. It
	# kills the layout tween on the way in, so whichever pose we choose below is
	# asserted fresh rather than left frozen mid-flight.
	card.set_dragging(true)
	# The whole row re-spreads around the new focus, exactly as a hover would.
	# `relayout_hand` skips `is_dragging` cards, so the grabbed card's own slot
	# is simply left empty — the neighbours hold station.
	relayout_hand(_bs.player_card_nodes, card)
	# 버리기 픽 중에는 카드가 낼 대상이 없다 — 중앙 버리기 구역에 놓는 것이
	# 유일한 행동이므로 대상 지정 오버레이는 켜지 않는다.
	if _in_discard_pick_mode() or _bs.targeting_overlay == null:
		_drag_follows_cursor = true
	else:
		_bs.targeting_overlay.start_card_selection(card.data,
				Callable(self, "_on_selection_confirm"))
		_refresh_play_allowed()
		_drag_follows_cursor = not _card_uses_drag_arrow(card)
	if _drag_follows_cursor:
		card.begin_free_drag()
	else:
		_pose_selected_card(card)
	_show_drop_zone(card)
	_refresh_description_box()
	_update_drag(p)


func _update_drag(p: Vector2) -> void:
	if _drag_card == null or not is_instance_valid(_drag_card):
		return
	if _drag_follows_cursor:
		_drag_card.follow_cursor(p)
	_update_drag_arrow(p, _update_drop_feedback(p))


## Live feedback under the cursor: the cyan pending-pick ring for target cards,
## the lit drop zone for the rest. Returns **true when dropping right here would
## actually play the card** — the 조준 화살표 recolours off that answer.
func _update_drop_feedback(p: Vector2) -> bool:
	var to: CardTargetingOverlay = _bs.targeting_overlay
	if to == null or _drag_card == null:
		return false
	# 버리기 픽 중에는 대상 지정이 없다 — 버리기 구역 하나가 유일한 드롭 지점.
	if _in_discard_pick_mode():
		var in_zone: bool = drop_zone_rect().has_point(p) \
				and _bs.card_select_overlay.can_pick_for_discard()
		_set_drop_zone_hot(in_zone)
		return in_zone
	match targeting_kind(_drag_card.data):
		"pilot":
			var picked: PilotData = to.hit_test_pilot_at(p)
			to.preview_drag_target(picked)
			return picked != null
		"location":
			var cell: Variant = to.hit_test_cell_at(p)
			to.preview_drag_target(cell)
			return cell != null
		_:
			var hot: bool = drop_zone_rect().has_point(p)
			_set_drop_zone_hot(hot)
			return hot


# ─── 조준 화살표 ─────────────────────────────────────────────────────────────

## 화살표를 다는 카드인가. 대상 지정 카드(PILOT / LOCATION)만이다 — 대상이 없는
## 카드는 겨눌 곳이 아니라 구역에 놓는 것이라 드롭 존이 이미 그 신호다.
func _card_uses_drag_arrow(card: Card) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	if _in_discard_pick_mode():
		return false
	var kind: String = targeting_kind(card.data)
	return kind == "pilot" or kind == "location"


## 카드 위쪽 끝 → 커서. 시작점은 카드 **자신의 위쪽 축** 위에서 잡으므로
## 부채꼴에서 기울어 있는 카드는 그 기울기대로 화살을 쏜다. `ARROW_TUCK_PX`
## 만큼 카드 안으로 파묻어 두면 화살표 노드가 카드보다 뒤에 그려지는 덕에
## 시작부가 카드에 가려 화살이 카드 밑에서 뻗어 나온 것처럼 읽힌다.
func _update_drag_arrow(cursor: Vector2, hot: bool) -> void:
	if not _card_uses_drag_arrow(_drag_card):
		_hide_drag_arrow()
		return
	_build_drag_arrow()
	var card: Card = _drag_card
	# 카드의 시각 중심은 회전/스케일에 불변인 `position + pivot_offset` 이다
	# (Card.tween_to 주석 참조). 위쪽 끝까지의 거리만 현재 스케일을 탄다.
	var centre: Vector2 = _card_layout_global(card) + card.pivot_offset
	var up := Vector2(0.0, -1.0).rotated(card.rotation)
	var reach: float = maxf(0.0, Card.CARD_H * 0.5 * card.scale.y - ARROW_TUCK_PX)
	_drag_arrow.aim(centre + up * reach, up, cursor, hot)


func _build_drag_arrow() -> void:
	if _drag_arrow != null and is_instance_valid(_drag_arrow):
		return
	_drag_arrow = CardDragArrow.new()
	_drag_arrow.name = "CardDragArrow"
	_drag_arrow.visible = false
	_bs.canvas.add_child(_drag_arrow)
	# 맨 아래 자식 = 손패 카드와 모든 HUD 위젯보다 뒤. 카드는 _reorder_hand_nodes
	# 가 매번 자식 목록의 끝으로 올리므로 이 자리는 계속 유지된다. 드롭 존도
	# 같은 자리를 쓰지만 둘은 동시에 뜨지 않는다(화살표 = 대상 지정 카드,
	# 드롭 존 = 그 나머지).
	_bs.canvas.move_child(_drag_arrow, 0)


func _hide_drag_arrow() -> void:
	if _drag_arrow != null and is_instance_valid(_drag_arrow):
		_drag_arrow.stop()


## Button released with a drag in flight. Either the drop resolves into a play
## (the node is already gone by the time `_try_drop_play` returns true) or the
## card simply goes home — **a missed drop costs nothing**, since neither the
## cost nor the card ever left the hand.
func _end_drag(p: Vector2) -> void:
	var card: Card = _drag_card
	_hide_drop_zone()
	_hide_drag_arrow()
	if card == null or not is_instance_valid(card):
		_drag_card = null
		_drag_follows_cursor = false
		_clear_targeting()
		return
	# Drop the held pose first: `add_card_to_discard` re-poses the node into the
	# centred 버리기 fan, and `relayout_hand` skips anything still flagged
	# `is_dragging`. The hover flag goes with it — a card that leaves the hand
	# (into the 버리기 fan) is no longer covered by `_update_hover_at`'s sweep,
	# so a stale hover would strand it at 1.2× over there. If the cursor really
	# is back on it, the `_update_hover_at` below re-hovers it.
	card.set_dragging(false)
	card.set_hovered(false)
	# `_drag_card` stays live across the drop so `_on_selection_confirm` — which
	# the confirm path calls back into synchronously — can find the card it is
	# committing.
	var _played: bool = _try_drop_play(card, p)
	_drag_card = null
	_drag_follows_cursor = false
	_clear_targeting()
	# Refresh the cursor's card first so the reflow below resolves to the right
	# focus, then lay the whole row out — that is what walks a missed card back
	# into its slot (and closes nothing, since the slot was held empty for it).
	_update_hover_at(p)
	relayout_hand(_bs.player_card_nodes)
	_refresh_description_box()


## Resolves what dropping `card` at `p` means. Returns true when the drop was
## consumed — a card played (node already freed) or, in 버리기 픽 mode, a card
## moved into the to-discard row.
func _try_drop_play(card: Card, p: Vector2) -> bool:
	# 버리기:N 픽 — 카드가 하는 일은 "버릴 카드로 넘긴다" 하나뿐이라 대상 지정
	# 경로를 아예 타지 않는다.
	if _in_discard_pick_mode():
		if not drop_zone_rect().has_point(p):
			return false
		if not _bs.card_select_overlay.can_pick_for_discard():
			return false
		_bs.card_select_overlay.add_card_to_discard(card)
		return true
	var to: CardTargetingOverlay = _bs.targeting_overlay
	if to == null:
		return false
	match targeting_kind(card.data):
		"pilot":
			var picked: PilotData = to.hit_test_pilot_at(p)
			return picked != null and to.confirm_with(picked)
		"location":
			var cell: Variant = to.hit_test_cell_at(p)
			return cell != null and to.confirm_with(cell)
		_:
			# No target to aim at, so the centre drop zone *is* the "play it"
			# gesture.
			return drop_zone_rect().has_point(p) and to.confirm_with(null)


## Drops any in-flight drag without playing the card. Called from the paths that
## tear the drag down out from under it (phase end, restart, forced teardown).
func _cancel_drag() -> void:
	if _drag_card != null and is_instance_valid(_drag_card):
		_drag_card.set_dragging(false)
	_drag_card = null
	_drag_follows_cursor = false
	_press_card = null
	_hide_drop_zone()
	_hide_drag_arrow()


## Tears down the 대상 지정 오버레이 if it is still up. Idempotent — the confirm
## path tears itself down before calling back, so this is usually a no-op there.
func _clear_targeting() -> void:
	if _bs.targeting_overlay != null:
		_bs.targeting_overlay.clear_selection()


## The card's layout position in viewport space — the same convention
## `slot_position` / `Card.tween_to` use (unrotated, unscaled top-left).
func _card_layout_global(card: Card) -> Vector2:
	var parent_ci := card.get_parent() as CanvasItem
	if parent_ci == null:
		return card.position
	return parent_ci.get_global_transform_with_canvas() * card.position


## Poses `card` in the aimed (lifted) pose at its own slot — the 대상 지정 카드
## pose, where the card stays in the hand and only the 조준 화살표 travels.
func _pose_selected_card(card: Card) -> void:
	var idx := _bs.player_card_nodes.find(card)
	if idx < 0:
		return
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
	card.tween_to(lifted, rot, Vector2.ONE,
			_bs.BS_HAND_SPRING_DURATION,
			_bs.BS_HAND_TWEEN_EASE, _bs.BS_HAND_TWEEN_TRANS)


# ─── 드롭 존 ─────────────────────────────────────────────────────────────────

## 대상이 없는 카드를 놓아서 내는 중앙 구역: 화면 세로 중앙을 기준으로 화면
## 높이의 `DROP_ZONE_H_RATIO` 만큼, 가로는 전체 폭.
##
## 버리기:N 픽 중에는 같은 구역이 **버리기 구역**이 된다 — 이미 골라 둔 카드가
## 늘어선 줄(`CardSelectOverlay.TO_DISCARD_CENTER_Y`)을 중심으로 잡히므로 "그
## 줄 위에 얹는다"로 읽힌다.
func drop_zone_rect() -> Rect2:
	var vp: Vector2 = _bs.canvas.get_viewport().get_visible_rect().size
	if _in_discard_pick_mode():
		return Rect2(0.0,
				CardSelectOverlay.TO_DISCARD_CENTER_Y - DISCARD_ZONE_H * 0.5,
				vp.x, DISCARD_ZONE_H)
	var h: float = vp.y * DROP_ZONE_H_RATIO
	return Rect2(0.0, vp.y * 0.5 - h * 0.5, vp.x, h)


## 드래그를 시작할 때 구역을 띄운다 — **대상 지정 카드에는 띄우지 않는다**:
## 그 카드들의 드롭 지점은 대상 그 자체라, 구역까지 깔면 "여기 놓으면 되나"로
## 읽혀 오해만 부른다.
func _show_drop_zone(card: Card) -> void:
	if _card_uses_drag_arrow(card):
		return
	_build_drop_zone()
	_drop_zone_label.text = "여기에 놓아 버리기" if _in_discard_pick_mode() \
			else "여기에 놓아 사용"
	# 버리기 픽 중에는 `CardSelectOverlay._battle_dim` 이 같은 캔버스의 자식
	# 인덱스 0 을 차지하고 있다 — 구역을 0 에 두면 그 딤 **아래**로 들어가 통째로
	# 눌려 보이지 않는다. 딤 바로 위(1)로 올린다.
	var back_idx: int = 1 if _in_discard_pick_mode() else 0
	_bs.canvas.move_child(_drop_zone,
			mini(back_idx, maxi(0, _bs.canvas.get_child_count() - 1)))
	var r := drop_zone_rect()
	_drop_zone.position = r.position
	_drop_zone.size     = r.size
	_drop_zone_label.position = Vector2(0.0, DROP_ZONE_LABEL_TOP)
	_drop_zone_label.size     = Vector2(r.size.x, DROP_ZONE_LABEL_H)
	_drop_zone.visible = true
	_set_drop_zone_hot(false)


func _build_drop_zone() -> void:
	if _drop_zone != null and is_instance_valid(_drop_zone):
		return
	_drop_zone = Panel.new()
	_drop_zone.name = "CardDropZone"
	_drop_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drop_zone.visible = false
	_bs.canvas.add_child(_drop_zone)
	# Behind every HUD element and every card — it is a backdrop, not a widget.
	_bs.canvas.move_child(_drop_zone, 0)

	_drop_zone_label = Label.new()
	_drop_zone_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drop_zone_label.text = "여기에 놓아 사용"
	_drop_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drop_zone_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_drop_zone_label.add_theme_font_size_override("font_size", 34)
	_drop_zone_label.add_theme_color_override("font_outline_color",
			Color(0.0, 0.0, 0.0, 0.85))
	_drop_zone_label.add_theme_constant_override("outline_size", 6)
	_drop_zone.add_child(_drop_zone_label)


func _set_drop_zone_hot(hot: bool) -> void:
	if _drop_zone == null or not is_instance_valid(_drop_zone):
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = DROP_ZONE_FILL_HOT if hot else DROP_ZONE_FILL
	sb.border_color = DROP_ZONE_BORDER_HOT if hot else DROP_ZONE_BORDER
	sb.border_width_top    = 3
	sb.border_width_bottom = 3
	sb.border_width_left   = 0
	sb.border_width_right  = 0
	_drop_zone.add_theme_stylebox_override("panel", sb)
	if _drop_zone_label != null:
		_drop_zone_label.add_theme_color_override("font_color",
				Color(1.0, 0.95, 0.65) if hot else Color(0.85, 0.82, 0.70, 0.65))


func _hide_drop_zone() -> void:
	if _drop_zone != null and is_instance_valid(_drop_zone):
		_drop_zone.visible = false


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
## The dragged card — or, failing that, the card under the cursor — is then
## raised above all of them, so a card the player is pointing at is never
## covered by its right-hand neighbours (including right after a drop, while the
## cursor is still sitting on it).
func _reorder_hand_nodes() -> void:
	if _reordering:
		return
	var top: Card = _drag_card
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
		# 비용 -1 은 **낼 수 없는 카드**다(캐시 · 계시 · 약자 멸시 · 밸런스).
		# 점수가 얼마든 지불 불가로 잠가 두면 슬래브가 덮이고 드래그도 거부된다 —
		# 그 카드들은 손에 들고 있는 것만으로 일하기 때문에, 잠기는 것이 곧
		# "이건 내는 카드가 아니다" 라는 안내가 된다.
		c.set_affordable(c.data.is_playable() and eff <= _bs.player_cost)
		# 시전자가 쓰러져 있으면 카드도 같이 잠긴다 — 카드 전체가 어두워지고
		# 부활까지 남은 턴이 한가운데 크게 찍힌다.
		c.set_respawn_turns(respawn_turns_for(c.data))
		# 계획 중시로 보존된 카드는 시안 테두리를 두른다 — 사용 가능 여부와는
		# 무관한 별개의 표시라 슬래브와 겹쳐 떠도 서로를 가리지 않는다.
		# `보존` 키워드 카드는 계획 중시로 보존된 카드와 같은 시안 테두리를
		# 두른다 — 플레이어에게 두 보존은 "이 카드는 버려지지 않는다" 한 가지
		# 의미이고, 수명이 다르다는 것은 카드 텍스트가 말한다.
		c.set_preserved(_bs.preserved_cards_p.has(c.data)
				or c.data.is_preserved_by_keyword())
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
	# between playable and not, so the drop gate re-reads it here too.
	_refresh_play_allowed()


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
## availability all have to hold. Gates the drop.
func card_is_playable(cd: CardData) -> bool:
	if cd == null:
		return false
	if respawn_turns_for(cd) > 0:
		return false
	if _bs.effective_cost_for(cd, true) > _bs.player_cost:
		return false
	return card_has_valid_targets(cd)


## Pushes the "is the held card playable?" verdict into the targeting overlay,
## which ANDs it with "has a target been picked yet?" to decide whether a drop is
## allowed to commit.
func _refresh_play_allowed() -> void:
	if _bs.targeting_overlay == null:
		return
	if _drag_card == null or not is_instance_valid(_drag_card):
		return
	_bs.targeting_overlay.set_play_allowed(card_is_playable(_drag_card.data))


# ─── Hover / hand focus ───────────────────────────────────────────────────────
# Hover feedback (brightness modulate) lives in Card.gd. CardPhaseManager owns
# the z-ordering, the held-card pose, and the description box.

func on_card_hovered(card: Card) -> void:
	# Tracked before the guards so the pointer stays accurate even when the
	# hover arrives while a card is held or a modal owns the screen.
	_hovered_card = card
	if _bs.game_phase != GameEnums.BattlePhase.CARD_PHASE:
		return
	if _is_player_input_blocked():
		return
	# No drag check here: _push_focus_card is the single home of the "the held
	# card outranks the cursor" rule, and _apply_hand_reflow no-ops when the
	# focus hasn't actually moved.
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
	# The description box reads the same focus, so it rides the same coalesced
	# pass — and it is refreshed *before* the early-out below, because a hover
	# that doesn't move the row (one arriving while a card is held) still has to
	# leave the box showing the right card.
	_refresh_description_box()
	var focus := _push_focus_card()
	# Nothing to do when the row already matches the focus — this is what stops
	# the enter/exit churn a reorder provokes from looping forever, and it is
	# also what makes hovering around while a card is held a no-op (the held card
	# stays the focus, so `focus` never changes).
	if focus == _reflow_focus:
		return
	# The **new** focus card must be laid out with everyone else. Its slot under
	# the new focus is its resting slot (own push = 0), but it is almost never
	# sitting there: the previous focus had pushed it aside, and skipping it left
	# it stranded at that stale offset — a card hovered right after its neighbour
	# stayed displaced by up to a full push (+26.9px at 8 cards, ~60px at the
	# 12-card cap), so it read as mis-hovered. Only the *dragged* card is skipped
	# (`relayout_hand` would skip it anyway on `is_dragging`); the hovered card's
	# scale is untouched by `tween_to`, so the layout spring can't fight the
	# hover tween.
	relayout_hand(_bs.player_card_nodes, _drag_card)


# Player can't pick / hover hand cards while the search-pick modal owns the
# screen or while the AI's async play loop is in flight. The targeting overlay
# is deliberately NOT in this list — targeting only exists while a card is being
# dragged, and the drag owns the pointer anyway. Discard mode is the other
# exception: the overlay's whole job is to let the player pull cards out of the
# hand, and that is now a drag onto the 버리기 구역.
func _is_player_input_blocked() -> bool:
	if _ai_play_in_progress:
		return true
	# 돌진 연출이 끝나야 다음 카드를 낼 수 있다.
	if _attack_anim_active:
		return true
	# 전투 개시 VS 확인 화면 — game_phase 는 아직 CARD_PHASE 이므로 손패가
	# 스스로 딤되지 않는다.
	if _bs.engage_phase != null and _bs.engage_phase.is_intro_active():
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


## Forcibly drops whatever the hand is holding — an in-flight drag and the
## targeting state that came with it. Nothing to refund: the cost is only spent
## on a committed drop, so a card torn out of a drag has never left the hand.
##
## Public because every path that pulls the rug out from under the hand calls it
## (phase end, restart, engage arena opening, 숨김 in the 버리기 overlay, a hand
## card being despawned). Idempotent.
##
## (The name survives from the click-to-select era; there is no selection any
## more, but every caller means exactly this.)
func deselect_current_card() -> void:
	var had: bool = _drag_card != null or _press_card != null
	_cancel_drag()
	_clear_targeting()
	if not had:
		return
	# Reflow the whole row — the released card INCLUDED. One pass places every
	# card off the same hover state, so the returning card can't land on a slot
	# that disagrees with the row it's landing in.
	relayout_hand(_bs.player_card_nodes)
	# The focus falls back to whatever the cursor is on (often the same card),
	# so the box follows rather than blinking out and back.
	_refresh_description_box()


## True while a 버리기:N pick overlay owns the hand. In that state dragging a
## card onto the centred 버리기 구역 is the only thing a card can do — the
## targeting overlay never comes up.
func _in_discard_pick_mode() -> bool:
	return _bs.card_select_overlay != null \
			and _bs.card_select_overlay.is_discard_mode()


# ─── Selection confirm (from CardTargetingOverlay) ───────────────────────────
## 드롭이 확정됐다. `picked` is the resolved target — PilotData for PILOT,
## Vector2i for LOCATION, null for PREVIEW / INSTANT cards. Only now is the
## cost deducted and the card consumed.
func _on_selection_confirm(picked: Variant) -> void:
	if _drag_card == null or not is_instance_valid(_drag_card):
		return
	var card := _drag_card
	# Re-check rather than trusting the drop gate: a battle tick can't fire
	# during 작전 단계, but an engage resolved from an earlier card in the same
	# phase can have killed the 시전자 or drained the points since.
	if not card_is_playable(card.data):
		# The overlay has already torn itself down by the time it calls us, so
		# the drag can't be left holding a dead targeting state.
		deselect_current_card()
		return
	# Tear down drag state BEFORE handing the node to the play path, which frees
	# it — the dangling reference must never escape this function. (`_end_drag`
	# clears `_drag_card` again on its way out; both are guarded.)
	_hide_description_box()
	_drag_card = null
	_play_card_direct(card, picked)


# ─── Description box ─────────────────────────────────────────────────────────

## Brings the box in line with the current hand focus (selected card, else the
## card under the cursor). The box sits at a fixed spot on screen, so nothing
## has to move when the focus stays put — only a change of card rebuilds it.
##
## Hovering is enough to open it: the box is far from the hand and out of the
## drag's way, so there is no reason to make the player commit to a selection
## just to read what a card does.
func _refresh_description_box() -> void:
	var focus: Card = _push_focus_card()
	if focus != null and (_bs.game_phase != GameEnums.BattlePhase.CARD_PHASE
			or _is_player_input_blocked()):
		focus = null
	if focus == null:
		_hide_description_box()
		return
	if focus == _desc_card and _description_box != null \
			and is_instance_valid(_description_box):
		return
	_show_description_box(focus)


func _show_description_box(card: Card) -> void:
	_hide_description_box()
	if card == null or not is_instance_valid(card) or card.data == null:
		return

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
	# 화면 상단 고정 — 상단 패널 아래, 전장 위의 빈 띠에 가로 가운데 정렬.
	var screen_w: float = _bs.canvas.get_viewport().get_visible_rect().size.x
	box.position = Vector2((screen_w - DESC_BOX_W) * 0.5, DESC_BOX_TOP)
	# 상자는 읽기 전용이라 마우스를 먹지 않는다 — 그 자리(전장 상단)를 지나가는
	# 드래그가 상자에 걸려 멈추면 안 된다. 안에 든 버튼(버리기)은 자기 픽을
	# 그대로 받는다: 부모가 IGNORE 여도 자식은 따로 히트 테스트된다.
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

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

	# **This box has no buttons.** It is a read-out, not a control surface:
	# playing a card is a drop, and so is picking one for 버리기:N. The old
	# "카드 내기" and "버리기" buttons both went with the selection state that
	# used to make them reachable.
	_bs.canvas.add_child(box)
	_description_box = box
	_desc_card = card


func _hide_description_box() -> void:
	if _description_box != null and is_instance_valid(_description_box):
		_description_box.queue_free()
	_description_box = null
	_desc_card = null


# Player play path, entered only from a committed drop — by which point the
# target (if the card wanted one) is already resolved, so nothing here opens a
# picker.
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
	# [명상] 이 "이 카드보다 왼쪽"을 세려면 손패에서 빠지기 **전**의 자리를
	# 알아야 한다 — 체인이 도는 동안 카드는 이미 손패 밖이기 때문이다.
	_current_card_index = _bs.player_hand.find(cd)
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
	_chain_hit = false
	_current_card = cd
	_current_target = pre_target
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
	# 시전자 없는 카드(오브젝트 보상)는 사거리라는 개념이 없다 — 아래 compute_*
	# 헬퍼가 caster == null 을 "전장 전체가 사거리"로 읽는다. 교전(preview)만은
	# 시전자 칸을 중심으로 참가자를 모으므로 여전히 시전자를 요구한다.
	match targeting_kind(cd):
		"pilot":
			# `pilot` 은 아군과 적을 **둘 다** 고를 수 있다(매혹) — 어느 쪽이든
			# 하나라도 있으면 낼 수 있는 카드다.
			if cd.target == "pilot":
				return not (compute_valid_pilot_targets(cd, caster, 0)
						+ compute_valid_pilot_targets(cd, caster, 1)).is_empty()
			var team_filter: int = 1 if cd.target == "enemy" else 0
			return not compute_valid_pilot_targets(cd, caster, team_filter).is_empty()
		"location":
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
		# `foe` — 적 파일럿 **또는** 포탑. 두 종류를 한 문장으로 부르는 메크
		# 카드가 열 장이 넘어서, 대상 지정은 둘 다 서 있을 수 있는 **칸**을
		# 고르게 하고 "그 칸의 무엇을 때리는가"는 공격 절이 정한다
		# (`_foe_at_cell` — 파일럿이 먼저다).
		if cd.target == "foe":
			return "location"
	return "none"


# Pilots within hex range of caster, on the requested team, alive. Honours the
# `min_range` flag (e.g. 저격: range 6 with min_range:2 → cells 2..6 hexes
# from caster). Returns an Array of PilotData.
#
# **시전자가 없으면 사거리 판정을 통째로 건너뛴다** — 오브젝트 보상 카드([용
# 보상])는 누구의 카드도 아니므로 잴 기준점이 없다. 예전에는 여기서 빈 배열을
# 돌려줬는데, 그러면 `card_has_valid_targets` 가 거짓이 되어 카드가 손패에서
# 영영 잠긴다.
func compute_valid_pilot_targets(cd: CardData, caster: PilotData,
		team: int) -> Array:
	var out: Array = []
	var unbounded: bool = caster == null
	var max_r: int = max(0, cd.cast_range)
	var min_r: int = _clause_int_flag(cd.effect, "min_range", 0)
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive or p.team != team:
			continue
		if not unbounded:
			var d: int = _bs.hex_grid.hex_distance(caster.grid_pos, p.grid_pos)
			if d > max_r:
				continue
			if d < min_r:
				continue
		out.append(p)
	return out


# Cells within hex range of caster (alive cells only). 약탈 (steal_camp)
# runs on its own rule set — see compute_steal_camp_targets.
#
# **절 검사가 시전자 검사보다 앞에 온다.** [전령 제압](`turret_damage`)은
# 시전자가 없는 카드이고 대상은 시전자 위치와 무관한 "최외곽 적 포탑"이라,
# caster == null 로 먼저 걷어 내면 그 카드는 영영 낼 수 없는 카드가 된다.
# 시전자 기준 반경으로 떨어지는 것은 아래의 일반 경로뿐이다.
func compute_valid_location_targets(cd: CardData, caster: PilotData) -> Array:
	var out: Array = []
	# Inspect the effect chain for clauses that constrain the legal set.
	# 메크 카드의 세 가지 대상 종류. 절이 아니라 `target` 컬럼이 정하므로
	# 절 검사보다 앞에 온다.
	if cd.target == "foe":
		return compute_foe_targets(cd, caster)
	if cd.target == "turret_outer":
		return compute_turret_damage_targets(cd, caster)
	if cd.target == "turret_any":
		return compute_any_enemy_turret_targets(caster)
	for clause in _parse_effect_chain(cd.effect):
		var cname: String = String(clause.get("name", ""))
		if cname == "turret_damage":
			return compute_turret_damage_targets(cd, caster)
		if cname == "steal_camp":
			return compute_steal_camp_targets(caster)
		if cname == "move" and "own_jungle" in (clause.get("flags", []) as Array):
			return compute_own_jungle_targets(caster)
	if caster == null:
		return out
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


## [전령 제압](`turret_damage:N`)의 유효 대상 — **레인별로 살아 있는 가장 바깥
## 적 포탑**이 서 있는 칸. 사거리는 보지 않는다(오브젝트 보상 카드는 시전자가
## 없어 잴 기준점이 없다).
##
## 판정은 `SimulationCore.outermost_enemy_turrets` 하나를 지난다 — 화면에서
## 초록으로 열리는 칸과 실제로 피해가 들어가는 포탑이 같은 목록에서 나온다.
func compute_turret_damage_targets(cd: CardData, caster: PilotData) -> Array:
	var out: Array = []
	if _bs.sim_core == null:
		return out
	var team: int = caster.team if caster != null else card_team(cd)
	for raw in _bs.sim_core.outermost_enemy_turrets(team):
		out.append((raw as TurretData).grid_pos)
	return out


## 이 카드가 **어느 팀의 것인가** (0 = 플레이어, 1 = AI). 시전자가 있으면 그
## 팀이고, 없으면(오브젝트 보상 카드) 카드가 들어 있는 더미로 가린다.
##
## AI 쪽 더미 세 곳을 다 보는 이유는 대상 계산이 불리는 시점이 하나가 아니기
## 때문이다 — 플레이어의 드래그 미리보기(손패), AI 의 사전 대상 선택(손패),
## 사용 가능 판정(손패). 어디에도 없으면 플레이어 것으로 읽는다: 시전자 없는
## 카드가 더미 밖에 떠 있는 유일한 순간은 플레이어가 이미 낸 직후다.
func card_team(cd: CardData) -> int:
	if cd == null:
		return 0
	if cd.owner_pilot != null:
		return cd.owner_pilot.team
	if _bs.ai_hand.has(cd) or _bs.ai_deck.has(cd) or _bs.ai_discard.has(cd):
		return 1
	return 0


# 약탈의 유효 대상 — **적 팀이 소유한 정글 셀 중 캠프가 차 있는 것**. 시전자
# 사거리는 보지 않는다(카드의 cast_range 는 99).
#
# 규칙이 두 번 바뀌었다. 처음에는 "사거리(1) 안의 적 소유 정글 셀"이었는데,
# 정글은 레인에서 떨어져 있고 레인 파일럿은 정글 셀에 들어가지도 못하므로
# 유효 대상이 사실상 항상 비어 있었다 — 카드가 영영 사용 불가였다. 그 다음이
# "아군 정글과 인접한 적 정글 셀"(전선을 한 칸씩 미는 규칙)이었다.
#
# **지금은 훔치는 것이 타일이 아니라 그 칸의 수입이다.** 그래서 조건도 소유
# 지도가 아니라 **캠프가 차 있는가** 하나로 옮겨 갔다 — 비어 있는 칸을 고를 수
# 있으면 그 자리가 곧 헛치기이고, 화면의 아웃라인(`BattleRenderer._draw_jungle_camps`)
# 이 이미 어느 칸에 값이 남아 있는지를 말해 주고 있다. 인접 조건이 없으므로
# 정글 반대편의 살진 캠프도 노릴 수 있다: 그 원격성이 이 카드의 값이다.
## `target = foe` 의 유효 칸 — 사거리 안에서 **적 파일럿이 서 있거나 살아 있는
## 적 포탑이 선** 칸 전부. 파일럿과 포탑을 한 목록에 담는 대신 칸을 고르게 하는
## 이유는 대상 지정 오버레이가 초상화(PILOT)와 칸(LOCATION) 둘 중 하나만 다룰 수
## 있고, 포탑에는 초상화가 없기 때문이다.
func compute_foe_targets(cd: CardData, caster: PilotData) -> Array:
	var out: Array = []
	if caster == null:
		return out
	var enemy_team: int = 1 - caster.team
	var max_r: int = maxi(0, cd.cast_range)
	var seen: Dictionary = {}
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive or p.team != enemy_team:
			continue
		if _bs.hex_grid.hex_distance(caster.grid_pos, p.grid_pos) > max_r:
			continue
		seen[p.grid_pos] = true
	for raw in _bs.turrets:
		var td := raw as TurretData
		if not td.alive or td.team != enemy_team:
			continue
		if _bs.hex_grid.hex_distance(caster.grid_pos, td.grid_pos) > max_r:
			continue
		seen[td.grid_pos] = true
	for cell in seen.keys():
		out.append(cell)
	return out


## `target = turret_any` — 살아 있는 적 포탑이 선 칸 전부. 사거리를 보지 않는다
## ([철거] 는 전장 어디든 겨눈다).
func compute_any_enemy_turret_targets(caster: PilotData) -> Array:
	var out: Array = []
	if caster == null:
		return out
	for raw in _bs.turrets:
		var td := raw as TurretData
		if td.alive and td.team != caster.team:
			out.append(td.grid_pos)
	return out


func compute_steal_camp_targets(caster: PilotData) -> Array:
	var out: Array = []
	if caster == null or _bs.sim_core == null:
		return out
	var enemy_team: int = 1 - caster.team
	for raw_cell in _bs.jungle_camps.keys():
		var cell := raw_cell as Vector2i
		if int(_bs.neutral_zone_cells.get(cell, -2)) != enemy_team:
			continue
		if not _bs.sim_core.camp_charged(cell):
			continue
		out.append(cell)
	return out


# 정글 파밍(`move|own_jungle`)의 유효 대상 — **시전자 팀이 소유한 정글 셀**
# 전부. 약탈과 마찬가지로 `cast_range` 는 보지 않는다(카드의 cast_range 는 99):
# 정글러는 자기 정글 어디로든 붙을 수 있어야 하고, 사거리로 묶으면 정글 반대편
# 캠프가 영영 닿지 않는다. 제자리 셀은 뺀다 — 이동이 no-op 이 되기 때문.
#
# 소유 판정은 `neutral_zone_cells` 를 그대로 읽는다 — 정글러가 밟아 점령한 칸도
# T1 파괴 보상으로 넘어온 칸도 그 자리에서 목표가 된다.
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
		if ename == "search_discard":
			# 묘지 탐색 — 찾기와 같은 그리드를 **버린 더미** 위에 편다.
			_pending_play["clauses"] = clauses
			_bs.card_select_overlay.start_search(n,
					_on_graveyard_overlay_complete,
					_on_overlay_cancel, _bs.player_discard)
			return
		if ename == "preserve":
			_pending_play["clauses"] = clauses
			_bs.card_select_overlay.start_preserve(n,
					_on_preserve_overlay_complete,
					_on_overlay_cancel)
			return
		# `on_hit` / `on_miss` — 앞선 공격 절이 한 대라도 맞았는가로 체인의
		# **나머지를 통째로** 가른다. 절 하나에 조건을 매다는 대신 체인을 두
		# 토막으로 자르는 이유는 카드가 요구하는 문장이 언제나 "명중 시 A,
		# 빗나갈 시 B" 두 갈래이기 때문이다 — 갈래마다 절이 여럿이라(간보기는
		# 명중 쪽에 전투 개시가, 빗나감 쪽에 전략 점수가 온다) 절 단위
		# 플래그로는 그 묶음을 표현할 수 없다.
		if ename == "on_hit" or ename == "on_miss":
			var want_hit: bool = ename == "on_hit"
			if _chain_hit != want_hit:
				var other: String = "on_miss" if want_hit else "on_hit"
				while not clauses.is_empty():
					var peek: Dictionary = clauses[0] as Dictionary
					if String(peek.get("name", "")) == other:
						break
					clauses.pop_front()
			continue
		# 공격 절은 돌진 연출이 끝날 때까지 매달린다 — 그동안 손패 입력과 턴
		# 넘기기가 잠기고(`_attack_anim_active`), 체인의 나머지와
		# `_finalize_pending_play` 는 그 뒤에 이어진다. 호출 측 넷은 전부 이
		# 호출이 마지막 문장이라 fire-and-forget 으로 두어도 순서가 어긋나지
		# 않는다.
		var msg: String = await _apply_single_effect(clause, true,
				_pending_play["caster"],
				int(_pending_play["ally_team"]),
				int(_pending_play["enemy_team"]),
				_pending_play.get("target", null))
		# 연출이 도는 사이 오버레이 취소 같은 경로가 _pending_play 를 비웠다면
		# 이어 붙일 자리가 없다.
		if _pending_play.is_empty():
			return
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
		send_to_discard(pick_raw as CardData, _bs.player_discard)
	(_pending_play["log_lines"] as Array).append("버리기 %d" % picks.size())
	relayout_hand(_bs.player_card_nodes)
	update_deck_discard_labels()
	_bs.hud.update_hud()
	_process_pending_chain()


# Search complete: the picks are still in the deck — move them to the hand and
# resume the chain. Like 드로우:N, a 찾기 resolved during 작전 단계 may overfill
# the hand; the next BATTLE auto-draw trims it back to MAX_HAND_SIZE.
## 묘지 탐색 확정 — 고른 카드를 **버린 더미**에서 빼 손패로 올린다. 찾기와
## 다른 것은 어느 더미에서 빼느냐 하나뿐이라 나머지 흐름은 그대로 공유한다.
func _on_graveyard_overlay_complete(picks: Array) -> void:
	if _pending_play.is_empty():
		return
	var taken: int = 0
	for pick_raw in picks:
		var cd: CardData = pick_raw as CardData
		_bs.player_discard.erase(cd)
		add_card_to_hand(cd, true)
		taken += 1
	(_pending_play["log_lines"] as Array).append("묘지 탐색 %d장" % taken)
	update_deck_discard_labels()
	_process_pending_chain()


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
	# Drop any in-flight drag before tearing down nodes — _drag_card may point
	# at a node we're about to free.
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
	# 롤백은 손패를 통째로 다시 세우는 작업이므로 드로우 인트로를 태우지 않는다 —
	# 되돌린 카드가 전부 새로 뽑힌 것처럼 왼쪽에서 날아 들어오면 "취소" 가 아니라
	# "새 손패" 로 읽힌다.
	for raw_cd in _bs.player_hand:
		spawn_card_node(raw_cd as CardData, false, false)
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
	# 완벽한 마무리 — 체인이 다 돌고 `_dispose_used_card` 까지 끝난 **뒤**라야
	# 단계를 닫을 수 있다. 체인 도중에 닫으면 카드가 손패 밖에 떠 있는 채로
	# 문이 닫혀 discard 로도 소멸로도 가지 못한다.
	if consume_end_phase_request():
		end_card_phase()


# 카드 한 장이 실제로 나갔다는 유일한 신호이기도 하다 — 파일럿 스킬의
# `on_card_played`(퍼포먼스의 충전)가 여기서 걸린다. 손패를 떠나는 모든 경로가
# 이 함수를 지나므로 플레이어 카드와 AI 카드가 같은 박자로 센다.
#
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
	if _bs.skill != null:
		_bs.skill.on_card_played(cd, is_player)
	# 메크 쪽 카드 훅 — 무념의 충전과 [캐시] 의 성장치 배당이 여기서 걸린다.
	if _bs.mech_skill != null:
		_bs.mech_skill.on_card_played(cd, is_player)
	if bump >= 0:
		_return_card_to_hand_left(cd, is_player, bump)
		return
	if cd.has_keyword(CardData.KW_EXHAUST):
		return
	var discard: Array = _bs.player_discard if is_player else _bs.ai_discard
	send_to_discard(cd, discard)


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
	var msg: String = await apply_card_effect(cd, false)
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
	_chain_hit = false
	_current_card = cd
	_current_target = target
	var skip_to: String = ""
	for clause in clauses:
		var cname: String = String(clause.get("name", ""))
		if skip_to != "":
			if cname != skip_to:
				continue
			skip_to = ""
		# 플레이어 쪽 `_process_pending_chain` 과 같은 두 갈래 규칙이다 —
		# 저쪽은 오버레이 때문에 체인을 배열로 들고 있고 이쪽은 한 번에
		# 도는 것뿐이라 표현만 다르다.
		if cname == "on_hit" or cname == "on_miss":
			var want_hit: bool = cname == "on_hit"
			if _chain_hit != want_hit:
				skip_to = "on_miss" if want_hit else "on_hit"
			continue
		# 공격 절은 돌진 연출을 기다린다 — AI 도 같은 연출을 쓰므로
		# AiCardPlayer 의 플레이 루프가 그만큼 늦게 다음 카드로 넘어간다.
		var msg: String = await _apply_single_effect(clause, is_player, caster,
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
		# 유일하게 기다려야 하는 절 — 돌진 연출이 끝나야 다음 절/다음 카드로
		# 넘어간다. 이 await 하나가 _process_pending_chain / apply_card_effect /
		# AiCardPlayer.run_ai_plays 를 줄줄이 코루틴으로 만든다(모두 await 로
		# 받는다).
		"attack":   return await _effect_attack(value, flags, caster, enemy_team,
				_as_pilot(selected_target))
		"shield_pct": return _effect_shield_pct(value, ally_team,
				_as_pilot(selected_target))
		"recall_ally": return _effect_recall_ally(ally_team,
				_as_pilot(selected_target))
		"exhaust_choice": return _effect_exhaust_choice(is_player, value)
		# 교전 두 절도 기다린다 — 제출 직후에 참가자 명단(VS)을 띄우고 확인을
		# 받기 때문. 공격 절과 같은 이유로 체인 전체가 코루틴이 된다.
		"engage":   return await _effect_engage(value, flags, caster, is_player)
		"duel":     return await _effect_duel(caster,
				_as_pilot(selected_target), is_player)
		"move":                    return _effect_move(caster, selected_target)
		"steal_camp":              return _effect_steal_camp(selected_target, caster)
		"cost_reduce_engage":      return _effect_cost_reduce_engage(value, is_player)
		"cost_reduce_hand":        return _effect_cost_reduce_hand(value, is_player)
		"cost_reduce_draw_phase":  return _effect_cost_reduce_draw_phase(value, is_player)
		"cost_inc_phase":          return _effect_cost_inc_phase(value, is_player)
		"advance":                 return _effect_advance(value, caster)
		"strategy_on_kill":        return _effect_strategy_on_kill(value, is_player)
		"lane_stat":               return _effect_lane_stat(value, flags, caster)
		"growth":                  return _effect_growth_rate(value, flags, caster)
		"growth_perm":             return _effect_growth_perm(value, ally_team,
				_as_pilot(selected_target), caster)
		"turret_damage":           return _effect_turret_damage(value, ally_team,
				caster, selected_target)
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
		# ── 메크 카드 절 ─────────────────────────────────────────────────────
		# 아래는 전부 `mech_cards.csv` 만 쓰는 절이다. 이름을 위쪽 공용 절과
		# 겹치지 않게 지은 것은 의도된 것으로, 카드 한 장의 절 목록만 보고도
		# "이건 기체가 주는 카드"임이 읽히게 하려는 것이다.
		"heal_pct":        return _effect_heal_pct(value, flags, caster, ally_team,
				_as_pilot(selected_target))
		"max_hp":          return _effect_max_hp(value, flags, caster, ally_team,
				_as_pilot(selected_target))
		"atk_add":         return _effect_atk_add(value, flags, caster, ally_team,
				_as_pilot(selected_target))
		"shield_atk":      return _effect_shield_atk(value, flags, caster, ally_team,
				_as_pilot(selected_target))
		"reactive_armor":  return _effect_reactive_armor(value, flags, caster,
				ally_team, _as_pilot(selected_target))
		"charge":          return _effect_charge(value, flags, caster)
		"score_cost":      return _effect_score_cost(value, caster)
		"growth_eff":      return _effect_growth_eff(value, ally_team, caster,
				_as_pilot(selected_target))
		"gen_hand":        return _effect_gen_card(value, flags, caster, is_player, true)
		"gen_deck":        return _effect_gen_card(value, flags, caster, is_player, false)
		"search_card":     return _effect_search_card(value, flags, caster, is_player)
		"search_discard":  return _effect_search_discard(value, is_player)
		"draw_discard":    return _effect_draw_discard(value, flags, is_player)
		"push":            return _effect_push(value, flags, caster)
		"move_target":     return _effect_move_target(value, caster,
				_as_pilot(selected_target))
		"move_to_target":  return _effect_move_to_target(caster,
				_as_pilot(selected_target))
		"pull_to_caster":  return _effect_pull_to_caster(flags, caster, enemy_team)
		"mark_target":     return _effect_mark_target(value, caster,
				_as_pilot(selected_target))
		"track":           return _effect_track(value, caster,
				_as_pilot(selected_target))
		"link_engage":     return _effect_link_engage(caster,
				_as_pilot(selected_target))
		"stun_next":       return _effect_stun_next(_as_pilot(selected_target))
		"no_engage_phase": return _effect_no_engage_phase(_as_pilot(selected_target))
		"dmg_taken":       return _effect_dmg_taken(value, _as_pilot(selected_target))
		"bounty":          return _effect_bounty(value, _as_pilot(selected_target))
		"growth_link":     return _effect_growth_link(value, caster,
				_as_pilot(selected_target))
		"discard_left":    return _effect_discard_left(is_player)
		"draw_discarded":  return _effect_draw_discarded(is_player)
		"execute":         return _effect_execute(value, flags, caster, selected_target)
		"attack_bounty":   return await _effect_attack_bounty(value, caster,
				_as_pilot(selected_target))
		"mutual_attack":   return await _effect_mutual_attack(value, caster,
				_as_pilot(selected_target))
		"taunt_all":       return await _effect_taunt_all(caster, enemy_team)
		# 핸드 상주 카드(비용 -1)의 표지 절. 낼 수 없는 카드라 여기까지 올 일이
		# 없지만, 절을 비워 두면 CSV 오타와 구분되지 않으므로 이름을 남긴다.
		"hand_passive":    return ""
		# ── 아직 배선되지 않은 절 (2단계) ────────────────────────────────────
		# 단계 B / 단계 C 는 교전 결과에 따라 다음 카드를 갈아 끼우고 강화 3택
		# 모달을 띄운다 — 카드 한 장이 자기 다음 상태를 고르는 유일한 자리라
		# 전용 UI 를 요구한다. 절 이름만 먼저 잡아 두고 로그 한 줄만 남긴다.
		"phase_b":         return "단계 B 결과 정산 (미구현)"
		"phase_c":         return "강화 선택 (미구현)"
		_: return ""



## 대상 인자를 PilotData 로 **안전하게** 읽는다. `x as PilotData` 는 x 가
## Object 가 아닐 때(예: `target = foe` 카드가 넘기는 Vector2i) 런타임 오류를
## 낸다 — 대상이 칸일 수도 있는 절이 생기면서 `as` 를 그대로 쓸 수 없게 됐다.
func _as_pilot(v: Variant) -> PilotData:
	if v is PilotData:
		return v as PilotData
	return null

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
		if is_player and not last_draw_merged:
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
		var bag: Array = _discardable(hand)
		if bag.is_empty():
			break
		var pick := bag[randi() % bag.size()] as CardData
		hand.erase(pick)
		send_to_discard(pick, discard)
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


## 공격 절. 예전에는 "적 하나를 한 번 때린다"였고 지금도 기본형은 그대로지만,
## 메크 카드가 대상 집합을 아홉 가지로 넓혔다 — 플래그가 그 집합을 정한다.
##
##   |all           전장 내 모든 적 파일럿                 (천둥 폭풍)
##   |random        무작위 적 파일럿 (스택 수만큼 뽑는다)  (전장 강타)
##   |self_range:N  시전자 기준 N칸 내 모든 적과 포탑      (테러 · 초고출력 …)
##   |area:N        지정 대상 기준 N칸 내 모든 적과 포탑   (정밀 폭격 · 파괴)
##   |damaged       이번 작전 단계에 이 메크가 때린 적 전부 (락온 · 신속)
##   |line          아군 HQ ~ 지정 포탑까지의 레인 전부     (꿰뚫는 번개)
##   |turret_only   지정한 적 포탑 하나                     (철거)
##   |stack         **같은 대상을 스택 수만큼 반복해서** 때린다 (미사일)
##   |pierce |repeat  예전 그대로 (필중 / 명중마다 반복)
##
## 대상은 PilotData 이거나 TurretData 다. 둘을 가르는 자리는 피해를 넣는 두
## 함수뿐이고 나머지 흐름(명중 판정 · 돌진 연출 · 팝업)은 공유한다.
func _effect_attack(n: int, flags: Array, caster: PilotData, enemy_team: int,
		picked: PilotData = null) -> String:
	_last_attack_hits = 0
	_last_attack_kills = 0
	var victims: Array = _resolve_attack_victims(flags, caster, enemy_team, picked)
	if victims.is_empty():
		return "공격 (대상 없음)"
	var pierce: bool = "pierce" in flags
	var repeat: bool = "repeat" in flags
	# `|stack` 은 대상을 늘리는 것이 아니라 **같은 대상을 반복**한다. 대상 쪽을
	# 늘리는 것은 `|random` 쪽이고, 둘이 같은 카드에 붙으면(전장 강타) 이미
	# 대상 목록이 스택 수만큼이므로 반복은 1 로 둔다.
	var swings_each: int = 1
	if "stack" in flags and not ("random" in flags):
		swings_each = maxi(1, _stack_of_current_card())
	var animated: bool = caster != null and caster.alive and _bs.renderer != null
	if animated:
		_set_attack_anim_active(true)
	var total_dmg: int = 0
	var missed: int = 0
	for victim_raw in victims:
		for _swing in swings_each:
			var landed: bool = pierce or caster == null or _roll_against(caster, victim_raw)
			if animated:
				await _bs.anim_pilot_lunge(caster, _lunge_anchor(victim_raw))
			if not landed:
				missed += 1
				_popup_on(victim_raw, "MISS", BattleRenderer.POPUP_MISS_COLOR)
				if animated:
					await _bs.anim_pilot_lunge_return(caster)
				continue
			var dealt: int = _deal_damage_to(victim_raw, caster, n)
			total_dmg += dealt
			_last_attack_hits += 1
			if dealt > 0:
				_popup_on(victim_raw, "-%d" % dealt, BattleRenderer.POPUP_DAMAGE_COLOR)
			else:
				_popup_on(victim_raw, "흡수", BattleRenderer.POPUP_SHIELD_COLOR)
			if not _is_alive(victim_raw):
				_last_attack_kills += 1
			if animated:
				await _bs.anim_pilot_lunge_return(caster)
			# 연속 공격은 **같은 대상**에 대해서만 이어진다 — 명중할 때마다 한
			# 번 더 굴리고, 빗나가거나 대상이 쓰러지면 멈춘다.
			if repeat:
				var extra: int = 0
				while extra < MAX_ATTACK_REPEATS - 1 and _is_alive(victim_raw):
					if not (pierce or caster == null or _roll_against(caster, victim_raw)):
						break
					if animated:
						await _bs.anim_pilot_lunge(caster, _lunge_anchor(victim_raw))
					var again: int = _deal_damage_to(victim_raw, caster, n)
					total_dmg += again
					_last_attack_hits += 1
					_popup_on(victim_raw, "-%d" % again, BattleRenderer.POPUP_DAMAGE_COLOR)
					if animated:
						await _bs.anim_pilot_lunge_return(caster)
					extra += 1
			if not _is_alive(victim_raw):
				break
	if animated:
		_set_attack_anim_active(false)
	_chain_hit = _last_attack_hits > 0
	var tag: String = " (필중)" if pierce else ""
	if _last_attack_hits == 0:
		return "공격%s 전부 빗나감 (%d회)" % [tag, missed]
	return "공격%s %d대상 %d타 -%d HP" % [
			tag, victims.size(), _last_attack_hits, total_dmg]


## 이 카드의 스택 수. 카드가 없으면(패시브가 직접 부른 공격) 1.
func _stack_of_current_card() -> int:
	if _current_card == null:
		return 1
	return maxi(1, _current_card.stack_count)


## 공격 절이 실제로 때릴 것들. 원소는 PilotData 또는 TurretData.
func _resolve_attack_victims(flags: Array, caster: PilotData, enemy_team: int,
		picked: PilotData) -> Array:
	var out: Array = []
	if "turret_only" in flags:
		var cell: Variant = _pending_target_cell()
		var td: TurretData = null
		if cell is Vector2i and _bs.sim_core != null:
			td = _bs.sim_core.turret_at_cell(cell as Vector2i)
		if td != null and td.alive and td.team == enemy_team:
			out.append(td)
		return out
	if "line" in flags:
		return _line_victims(caster, enemy_team)
	if "damaged" in flags:
		if _bs.mech_skill != null and caster != null:
			for raw in (_bs.mech_skill.damaged_this_phase.get(caster, []) as Array):
				var p := raw as PilotData
				if p.alive and p.team == enemy_team:
					out.append(p)
		return out
	if "all" in flags:
		for raw in _bs.pilots:
			var p := raw as PilotData
			if p.alive and p.team == enemy_team:
				out.append(p)
		return out
	if "random" in flags:
		var bag: Array = []
		for raw in _bs.pilots:
			var p := raw as PilotData
			if p.alive and p.team == enemy_team:
				bag.append(p)
		if bag.is_empty():
			return out
		var picks: int = 1
		if "stack" in flags:
			picks = _stack_of_current_card()
		for _i in picks:
			out.append(bag[randi() % bag.size()])
		return out
	var self_r: int = _flag_int(flags, "self_range", -1)
	if self_r >= 0 and caster != null:
		return _victims_around(caster.grid_pos, self_r, enemy_team)
	var area_r: int = _flag_int(flags, "area", -1)
	if area_r >= 0:
		var origin: Vector2i = Vector2i(-999, -999)
		if picked != null:
			origin = picked.grid_pos
		elif _pending_target_cell() is Vector2i:
			origin = _pending_target_cell() as Vector2i
		if origin == Vector2i(-999, -999):
			return out
		return _victims_around(origin, area_r, enemy_team)
	# 기본형 — 지정한 적 하나. 지정이 없거나 이미 쓰러졌으면 아무나 하나.
	# 대상이 셀로 들어오는 카드(적 또는 포탑을 한 칸에서 고르는 `foe` 계열)는
	# 그 칸에 선 적 파일럿을 먼저 보고, 없으면 포탑을 본다.
	if picked != null and picked.alive and picked.team == enemy_team:
		out.append(picked)
		return out
	var cell2: Variant = _pending_target_cell()
	if cell2 is Vector2i:
		var v: Variant = _foe_at_cell(cell2 as Vector2i, enemy_team)
		if v != null:
			out.append(v)
			return out
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.alive and p.team == enemy_team:
			out.append(p)
			break
	return out


## 한 칸에 선 "적 또는 포탑". 파일럿이 먼저다 — 같은 칸에 둘 다 있으면 카드를
## 겨눈 사람이 보고 있던 것은 얼굴이지 건물이 아니다.
func _foe_at_cell(cell: Vector2i, enemy_team: int) -> Variant:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.alive and p.team == enemy_team and p.grid_pos == cell:
			return p
	if _bs.sim_core != null:
		var td: TurretData = _bs.sim_core.turret_at_cell(cell)
		if td != null and td.alive and td.team == enemy_team:
			return td
	return null


## `origin` 에서 `radius` 칸 안의 적 파일럿과 적 포탑 전부.
func _victims_around(origin: Vector2i, radius: int, enemy_team: int) -> Array:
	var out: Array = []
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.alive and p.team == enemy_team \
				and _bs.hex_grid.hex_distance(origin, p.grid_pos) <= radius:
			out.append(p)
	for raw in _bs.turrets:
		var td := raw as TurretData
		if td.alive and td.team == enemy_team \
				and _bs.hex_grid.hex_distance(origin, td.grid_pos) <= radius:
			out.append(td)
	return out


## 꿰뚫는 번개 — **아군 HQ 쪽 끝부터 지정한 포탑 칸까지**의 레인 통로에 서 있는
## 적과 포탑 전부. 앞뒤는 `SimulationCore.lane_corridor_order` 가 정한다(팀0 HQ
## 쪽부터 번호가 매겨져 있다) — 팀0 은 번호가 작은 쪽이 자기 진영이므로 지정한
## 칸의 번호 **이하**를, 팀1 은 **이상**을 쓸어 담는다.
func _line_victims(caster: PilotData, enemy_team: int) -> Array:
	var out: Array = []
	var cell: Variant = _pending_target_cell()
	if not (cell is Vector2i) or caster == null or _bs.sim_core == null:
		return out
	var target_cell := cell as Vector2i
	var td: TurretData = _bs.sim_core.turret_at_cell(target_cell)
	if td == null:
		return out
	var order: Dictionary = _bs.sim_core.lane_corridor_order(td.lane)
	if not order.has(target_cell):
		return out
	var limit: int = int(order[target_cell])
	var ally_team: int = 1 - enemy_team
	var band: Dictionary = {}
	for raw_cell in order.keys():
		var c := raw_cell as Vector2i
		var o: int = int(order[c])
		if ally_team == 0 and o <= limit:
			band[c] = true
		elif ally_team == 1 and o >= limit:
			band[c] = true
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.alive and p.team == enemy_team and band.has(p.grid_pos):
			out.append(p)
	for raw in _bs.turrets:
		var t := raw as TurretData
		if t.alive and t.team == enemy_team and band.has(t.grid_pos):
			out.append(t)
	return out


## 이번 카드가 고른 셀(LOCATION 대상). 파일럿을 고른 카드에서는 null.
func _pending_target_cell() -> Variant:
	if _current_target is Vector2i:
		return _current_target
	return null




func _is_alive(victim: Variant) -> bool:
	if victim is PilotData:
		return (victim as PilotData).alive
	if victim is TurretData:
		return (victim as TurretData).alive
	return false


## 명중 판정. 포탑은 굴리지 않는다 — 전장 규칙에서도 파일럿→포탑 피해는
## 무판정이다(`SimulationCore._resolve_turret_combat`).
func _roll_against(caster: PilotData, victim: Variant) -> bool:
	if victim is TurretData:
		return true
	return _bs.sim_core.roll_hit(caster, victim as PilotData)


## 돌진 연출이 향할 곳. 포탑은 초상화가 없으므로 연출을 걸지 않는다.
func _lunge_anchor(victim: Variant) -> PilotData:
	if victim is PilotData:
		return victim as PilotData
	return null


func _popup_on(victim: Variant, text: String, color: Color) -> void:
	if _bs.renderer == null or not (victim is PilotData):
		return
	_bs.renderer.spawn_pilot_popup(victim as PilotData, text, color, 0.0)


func _deal_damage_to(victim: Variant, caster: PilotData, n: int) -> int:
	if victim is TurretData:
		return _apply_attack_damage_turret(victim as TurretData, caster)
	return _apply_attack_damage(victim as PilotData, caster, n)


## 파일럿 스킬 / 메크 패시브가 직접 거는 한 방(계시 · 무념). 카드 체인 밖이라
## 연출도 팝업도 없이 판정과 피해만 굴린다 — 화면에는 결과(체력 · 킬로그)만
## 남는다.
func deal_simple_attack(caster: PilotData, target: PilotData, n: int) -> int:
	if caster == null or target == null or not target.alive:
		return 0
	if not _bs.sim_core.roll_hit(caster, target):
		return 0
	return _apply_attack_damage(target, caster, n)


## 파일럿→포탑 카드 피해. 전장과 같은 **고정값**(`PILOT_STRUCTURE_DMG`)을 쓴다 —
## `atk` 비례로 두면 성장이 공격력을 ×3 까지 미는 후반에 카드 한 장이 포탑을
## 통째로 지운다(전장 공성이 고정 피해로 바뀐 것과 같은 이유다).
func _apply_attack_damage_turret(td: TurretData, caster: PilotData) -> int:
	var dmg: int = maxi(1, _bs.PILOT_STRUCTURE_DMG)
	var log_lines: Array = []
	# 철거 · 정산 · 스프라이트 해제까지 전부 그 함수 한 곳이 한다 — [전령 제압]
	# 이 이미 쓰고 있는 경로이고, 여기서 따로 처리하면 포탑이 무너지는 자리가
	# 둘로 갈린다.
	_bs.sim_core.apply_card_turret_damage(td, dmg, caster, log_lines)
	if _bs.renderer != null:
		_bs.renderer.queue_redraw()
	return dmg

# One landed swing of an attack card. Returns the **HP** damage dealt (what is
# left after 보호막 absorption, matching what the log line has always shown) so
# the caller can total it across a 연속 공격 chain.
#
# Damage = 시전자 ATK × value (value is the design unit, e.g. 공격:1 → 1×ATK).
# Mech ATK was scaled ×20 in the DB so a 1×ATK card hit lands at a meaningful
# share of pilot HP without a separate placeholder multiplier. Caster falls
# back to a flat 100 only when the card has no owner_pilot (legacy paths).
## 돌진 연출 잠금의 양쪽 가장자리. 플래그만 세우면 이미 화면에 떠 있는 손패 딤과
## 턴 넘기기 버튼은 다음 갱신까지 옛 상태로 남으므로, 두 소비자를 여기서 함께
## 깨운다. `_apply_hand_dim_state` 를 직접 부르는 것은 `highlight_affordable_cards`
## 가 아직 정리되지 않은 플레이 중간 상태(방금 free 된 카드 노드)를 훑기 때문이다.
func _set_attack_anim_active(active: bool) -> void:
	if _attack_anim_active == active:
		return
	_attack_anim_active = active
	_apply_hand_dim_state()
	if _bs.hud != null:
		_bs.hud.update_hud()


func _apply_attack_damage(t: PilotData, caster: PilotData, n: int) -> int:
	var atk_value: int = caster.atk if caster != null else 100
	var dmg: int = max(1, atk_value * n)
	# 불안정한 대포 — 주는 쪽 / 받는 쪽 배율. 전장 자동 교전과 같은 규칙이다.
	if _bs.skill != null:
		dmg = maxi(1, roundi(float(dmg)
				* _bs.skill.damage_out_mult(caster)
				* _bs.skill.damage_in_mult(t)))
	# 메크가 거는 받는-피해 배율(취약 · 죽음의 손가락 · 목표)과 반응 장갑.
	# **반응 장갑이 보호막보다 먼저다** — 90%를 깎고 남은 10%를 보호막이 받는
	# 순서라야 두 방어가 겹쳐 읽힌다(반대로 두면 보호막이 온전한 피해를 먼저
	# 먹고 장갑은 잔량에만 걸려 사실상 아무 일도 하지 않는다).
	if _bs.mech_skill != null:
		dmg = maxi(1, roundi(float(dmg) * _bs.mech_skill.damage_taken_mult(t, caster)))
		if _bs.mech_skill.consume_reactive_armor(t):
			dmg = maxi(1, roundi(float(dmg) * (1.0 - MechSkillSystem.REACTIVE_ARMOR_CUT)))
	var rolled: int = dmg
	# 보호막 absorbs first, HP next.
	if t.shield > 0:
		var absorbed: int = min(t.shield, dmg)
		t.shield -= absorbed
		dmg -= absorbed
	if dmg > 0:
		t.hp = max(0, t.hp - dmg)
	# 피해는 **피해자의 장부**에 적힌다 — 성장치는 그 대상이 실제로 쓰러질 때
	# 현상금을 나누며 정산된다(전장 · 교전 무대와 같은 규칙). 적는 값은 굴린
	# 피해 전체다: 보호막에 먹힌 몫도 기여다.
	_bs.record_pilot_damage(caster, t, rolled)
	# 몰아치기 — **명중한 공격 카드**만 충전한다(빗나간 타격은 `_effect_attack`
	# 이 여기까지 오지 않는다).
	if _bs.skill != null:
		_bs.skill.on_attack_hit(caster)
	# 메크 쪽 명중 훅 — 취약 각인 · 조준 보정 · 영혼 수확 · 고통과 쾌감이
	# 여기서 걸리고, "이번 단계에 때린 적" 명단도 여기서 쌓인다.
	if _bs.mech_skill != null:
		_bs.mech_skill.on_card_attack_hit(caster, t, dmg)
		# 계시 — 적이 **카드로** 맞을 때마다 그 카드를 안 낸 계시 보유자가
		# 한 대 얹는다. 자기 자신은 제외돼 있어 연쇄가 닫힌다.
		_bs.mech_skill.on_card_damage_for_revelation(t, caster)
	if t.hp <= 0:
		_bs.mark_pilot_dead(t, caster)
	elif dmg > 0:
		# 공격 카드 전용 세기 — 전장 자동 교전보다 훨씬 격렬하다.
		_bs.anim_pilot_shake(t, _bs.ANIM_SHAKE_CARD_DUR, _bs.ANIM_SHAKE_CARD_AMP_PX)
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


## 전투 개시 — **카드를 제출한 이 시점**에 참가자 명단(VS 화면)이 뜨고, 확인을
## 받은 뒤에야 아레나가 열린다.
##
## 명단이 카드를 **고르는** 순간이 아니라 여기 붙는 이유는 `EngageIntro` 머리말
## 참고. 이 절이 `await` 를 물면서 `_apply_single_effect` → `_process_pending_chain`
## / `apply_card_effect` → `AiCardPlayer.run_ai_plays` 가 줄줄이 코루틴이 되는데,
## 공격 절(`_effect_attack`)이 이미 같은 이유로 그렇게 되어 있어 새로 생기는
## 계약은 없다.
##
## **취소는 카드 제출 자체를 무른다** — `_on_overlay_cancel` 이 `_play_card_direct`
## 가 떠 둔 스냅샷(손패 / 덱 / 비용 / engage 할인)을 통째로 복원하므로, 버리기 /
## 찾기 오버레이의 취소와 완전히 같은 경로다. 그 뒤 빈 문자열을 돌려주면
## `_process_pending_chain` 이 `_pending_play` 가 비었음을 보고 체인을 접는다.
func _effect_engage(rounds: int, flags: Array, caster: PilotData,
		is_player: bool) -> String:
	# 시전자 없는 카드(레거시 fallback)는 전투 자체가 의미가 없음. 이 경우는
	# 효과 체인 줄에 안내만 남기고 통과.
	if caster == null or rounds <= 0:
		return "전투 개시 (시전자 없음)"
	var exclude_lane: bool = "exclude_lane" in flags
	# 메크 카드가 무대의 **중심**과 **반경**을 바꾼다.
	#   |at_target   지정한 적 주변에서 연다        (돌격 · 강습 · 간보기)
	#   |at_marked   목표가 찍힌 적 주변에서 연다   (단계 B)
	#   |self_range:N 시전자 중심 반경 N            (우세한 전장 3 · 개시 2 …)
	#   |charge_rounds 라운드 수를 영혼 포식 충전으로 갈음한다 (전쟁의 사슬)
	var center: Vector2i = Vector2i(-999, -999)
	var radius: int = maxi(1, _flag_int(flags, "self_range", 1))
	if "at_target" in flags:
		if _current_target is PilotData:
			center = (_current_target as PilotData).grid_pos
	elif "at_marked" in flags:
		for raw in _bs.pilots:
			var p := raw as PilotData
			if p.alive and p.marked_by == caster:
				center = p.grid_pos
				break
	if "charge_rounds" in flags and _bs.mech_skill != null:
		rounds = maxi(1, _bs.mech_skill.chain_rounds(caster))
	if rounds <= 0:
		return "전투 개시 (라운드 0)"
	var sides: Array = _bs.engage_phase.engage_sides(caster, exclude_lane,
			center, radius)
	var t0: Array = sides[0]
	var t1: Array = sides[1]
	# 한쪽이라도 비면 start_engage 가 어차피 no-op 이므로 명단을 띄우지 않는다.
	if t0.is_empty() or t1.is_empty():
		return "전투 개시 (대상 부족)"
	var who: String = "" if is_player else " (AI)"
	# AI 가 낸 카드는 플레이어가 무를 수 있는 것이 아니므로 확인만 뜬다.
	var ok: bool = await _bs.engage_phase.prompt_engage(t0, t1, rounds,
			"전투 개시%s" % who, is_player)
	if not ok:
		_on_overlay_cancel()
		return ""
	# Both player and AI plays open the arena so the engage is visible —
	# AiCardPlayer awaits engage_finished between AI plays so the
	# back-to-back animations don't stomp each other.
	_bs.engage_phase.start_engage(caster, rounds, exclude_lane,
			Callable(self, "_on_engage_finished"), center, radius)
	var tag: String = " (레인 제외)" if exclude_lane else ""
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
## 결투 — 1:1. 전투 개시와 같은 VS 확인 화면을 지난다(참가자는 두 명뿐).
## `pool = 0` 이라 지금은 아무에게도 지급되지 않지만, 되살아났을 때 개시 흐름이
## 전투 개시와 갈라지지 않도록 같은 경로에 태워 둔다.
func _effect_duel(caster: PilotData, picked: PilotData,
		is_player: bool) -> String:
	if caster == null or picked == null:
		return "결투 (대상 없음)"
	var who: String = "" if is_player else " (AI)"
	var t0: Array = [caster] if caster.team == 0 else [picked]
	var t1: Array = [picked] if caster.team == 0 else [caster]
	var ok: bool = await _bs.engage_phase.prompt_engage(t0, t1,
			TurnEngageSim.DUEL_MAX_ROUNDS, "결투%s" % who, is_player)
	if not ok:
		_on_overlay_cancel()
		return ""
	_bs.engage_phase.start_duel(caster, picked,
			Callable(self, "_on_engage_finished"))
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
	# 위치 고정(파일럿 스킬)이 걸린 파일럿은 자리에서 못 뜬다 — 그 스킬이 파는
	# 것이 "안 움직이는 대신 더 번다"이므로 이동 카드로 빠져나갈 수 있으면
	# 대가가 사라진다.
	if _bs.skill != null and _bs.skill.blocks_move(caster):
		return "이동 (위치 고정)"
	var cell := picked as Vector2i
	if cell == caster.grid_pos:
		return "이동 %s (제자리)" % _bs.pilot_label(caster)
	var orig := caster.grid_pos
	caster.grid_pos = cell
	_bs.blog.log_move(caster, orig, cell, "card-move")
	_bs.anim_pilot_move(caster, orig)
	# **내려앉은 칸의 캠프는 그 자리에서 먹는다.** 턴 루프의 정산
	# (`process_jungle_camps`)까지 기다리면 카드를 낸 순간과 수확 사이가 몇 초
	# 벌어져 "카드를 냈는데 아무 일도 안 일어난" 것으로 보이고, 그 사이에 적
	# 정글러가 같은 칸을 밟으면 통째로 뺏긴다. 정산 자체는 턴 루프와 같은
	# 함수라 값도 재생성 시계도 어긋날 수 없다.
	var msg: String = "이동 %s → (%d,%d)" % [_bs.pilot_label(caster), cell.x, cell.y]
	if _bs.sim_core.harvest_camp_under(caster):
		msg += " · 캠프 +%.2fk" % _bs.SCORE_JUNGLE_CAMP
	return msg


# 약탈 — 적 소유 정글 칸의 **차 있는 캠프**를 원격으로 가로챈다. 타일 주인은
# 그대로다: 바뀌는 것은 그 칸의 재생성 시계와 시전자의 성장치뿐이라, 적 정글러는
# 다음 재생성까지 그 칸을 빈손으로 지나간다.
#
# 정산은 `SimulationCore.steal_camp_point` 한 곳이고 값과 재생성 시계가 밟아서
# 먹는 것과 같다 — 카드 한 장이 "발로 밟은 한 번"을 거리 무시로 사는 것이다.
func _effect_steal_camp(picked: Variant, caster: PilotData) -> String:
	if not (picked is Vector2i) or caster == null:
		return "약탈 (대상 없음)"
	var cell := picked as Vector2i
	if not _bs.sim_core.steal_camp_point(cell, caster):
		return "약탈 실패 (캠프 없음)"
	return "약탈 (%d,%d) +%.2fk" % [cell.x, cell.y, _bs.SCORE_JUNGLE_CAMP]


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


## `growth_perm:N` — [용 보상]. **지정한 아군 파일럿 한 명**의 성장 적립 배율에
## N%p 를 **영구로 누적**한다. 만료도 해제도 없다.
##
## `growth_rate_mult`(안전한 파밍 / 완벽한 마무리가 서로 덮어쓰는 슬롯)이 아니라
## `growth_rate_bonus` 에 얹는 이유가 그 누적이다 — 슬롯에 넣으면 용을 다섯 번
## 먹어도 +10% 에서 멈추고, 그 뒤에 라인전 카드 한 장이 그걸 지운다.
##
## 대상이 없으면(파일럿이 그 사이 쓰러졌다) 아무 일도 하지 않는다. 카드 자체는
## 이미 소비된 뒤이므로 여기서 되돌릴 것은 없다.
## `growth_perm:N` — 지정 아군의 성장 적립 배율을 **영구**로 N% 올린다(누적).
##
## 대상이 안 찍힌 카드는 **시전자 자신**에게 건다 — [핫핸드]가 그 경우다(대상
## 지정이 없는 `instant` 카드라 `picked` 가 언제나 null 로 들어온다). 용 보상은
## `target=ally` 라 언제나 찍힌 대상이 들어오므로 이 폴백을 타지 않는다.
func _effect_growth_perm(pct: int, ally_team: int, picked: PilotData,
		caster: PilotData = null) -> String:
	var target: PilotData = picked if picked != null else caster
	if target == null or not target.alive or target.team != ally_team:
		return "성장 효율 (대상 없음)"
	target.growth_rate_bonus += float(pct) / 100.0
	_bs.blog.log_event("GROWTH", "%-4s 성장 효율 %+d%% (영구, 누적 %+d%%)" % [
			_bs.pilot_label(target), pct,
			roundi(target.growth_rate_bonus * 100.0)])
	return "%s 성장 효율 %+d%% (영구)" % [_bs.pilot_label(target), pct]


## `turret_damage:N` — [전령 제압]. 찍은 칸의 포탑에 **명중 판정 없이** N 피해.
##
## 유효 대상은 `compute_turret_damage_targets` 가 이미 최외곽 포탑으로 좁혀 두지만
## 여기서 한 번 더 확인한다: 카드를 든 뒤 확정 전까지 전장 턴이 돌 수는 없어도,
## 같은 작전 단계 안에서 앞서 낸 카드(전진 / 공격)가 그 포탑을 무너뜨렸을 수는
## 있다. 그러면 이 절은 조용히 아무것도 하지 않는다.
func _effect_turret_damage(n: int, ally_team: int, caster: PilotData,
		picked: Variant) -> String:
	if n <= 0 or not (picked is Vector2i):
		return "포탑 피해 (대상 없음)"
	var td: TurretData = _bs.sim_core.turret_at_cell(picked as Vector2i)
	if td == null or td.team == ally_team:
		return "포탑 피해 (대상 없음)"
	if not _bs.sim_core.outermost_enemy_turrets(ally_team).has(td):
		return "포탑 피해 (최외곽 포탑 아님)"
	var log_lines: Array = []
	_bs.sim_core.apply_card_turret_damage(td, n, caster, log_lines)
	_bs.renderer.queue_redraw()
	return "T%d %s 포탑 −%d" % [td.tier, _bs.LANE_NAMES[td.lane], n]


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
# 아래 강제 버리기들은 **계획 중시의 보존을 무시한다** — 그 보존(`preserve:N`
# 효과, `BattleSim.preserved_cards_*`)은 상한 초과 자동 버리기로부터만 지켜 준다.
#
# **`보존` 키워드는 다르다.** 카드 자신이 달고 있는 것이라 강제 버리기도 뚫지
# 못한다 — 그래서 이 절 전체가 `_discardable()` 로 손패를 거른다. 오브젝트
# 보상은 한 매치에 한 장 나오는 카드이므로 재고 한 번에 날아가면 안 된다.

## 버려지는 카드 한 장을 더미로 보낸다 — **버리기의 유일한 출구**다.
##
## `휘발성`(`KW_VOLATILE`)을 단 카드는 더미에 앉지 않고 그 자리에서 사라진다.
## 파일럿 스킬이 손패에 직접 만들어 준 카드들이 그것이라, 안 쓰고 버려도 덱이
## 불어나지 않는다 — 스킬은 카드를 **주는** 것이지 덱을 키우는 것이 아니다.
## 더미에 실제로 들어갔으면 true.
##
## 호출 측은 손패에서 빼는 것까지만 하고 이 함수에 넘긴다. 카드 노드를 지우는
## 것(`_despawn_player_card_node`)은 어느 쪽이든 똑같이 필요하므로 여기서 하지
## 않는다.
func send_to_discard(cd: CardData, discard: Array) -> bool:
	if cd == null:
		return false
	if cd.is_volatile():
		return false
	# 무념(암살 T)은 "카드를 사용하거나 버릴 때마다" 충전한다. 낸 카드는
	# `_dispose_used_card` 가 이미 세었으므로(그 경로도 결국 여기로 온다)
	# 지금 도는 카드만 빼면 두 번 세지 않는다.
	if _bs.mech_skill != null and cd != _current_card:
		_bs.mech_skill.on_card_discarded(cd, discard == _bs.player_discard)
	discard.append(cd)
	# **뭉치는 손패에서만 뭉쳐 있다.** 더미로 내려앉는 순간 다시 낱장으로
	# 흩어진다 — 그러지 않으면 리셔플 한 번에 덱 장수가 뭉친 만큼 줄고, 다음에
	# 뽑을 때 한 장을 뽑았는데 세 장이 들어오는 일이 생긴다. 흩어진 낱장들은
	# 손패로 돌아올 때 `add_card_to_hand` 가 다시 뭉쳐 준다.
	var extra: int = cd.stack_count - 1
	cd.stack_count = 1
	for _i in max(0, extra):
		var copy := make_card_copy(cd)
		copy.stack_count = 1
		discard.append(copy)
	return true


## 지금 버릴 수 있는 손패 카드들 — `보존` 키워드를 단 카드는 빠진다.
## 강제 버리기 계열이 전부 이 한 함수를 지나므로 규칙이 한 군데에만 산다.
func _discardable(hand: Array) -> Array:
	var out: Array = []
	for raw in hand:
		var cd := raw as CardData
		if cd != null and cd.is_preserved_by_keyword():
			continue
		out.append(cd)
	return out


## Moves the whole hand to the discard pile. Returns how many cards moved.
## `보존` 키워드 카드는 손패에 그대로 남는다.
func _discard_whole_hand(is_player: bool) -> int:
	var hand:    Array = _bs.player_hand    if is_player else _bs.ai_hand
	var discard: Array = _bs.player_discard if is_player else _bs.ai_discard
	var moved: int = 0
	for raw in _discardable(hand):
		var cd := raw as CardData
		hand.erase(cd)
		send_to_discard(cd, discard)
		if is_player:
			_despawn_player_card_node(cd)
		moved += 1
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
		if is_player and not last_draw_merged:
			spawn_card_node(c)
		drew += 1
	_refresh_hand_after_bulk_change(is_player)
	return "손패 %d장 버리고 %d장 드로우" % [moved, drew]


## 과감한 정리 — 손패 **오른쪽**(가장 최근에 들어온 쪽) N장을 버린다.
## `보존` 키워드 카드는 건너뛰고 그 다음 카드를 대신 버린다(자리를 지킨 채 남는다).
func _effect_discard_right(is_player: bool, n: int) -> String:
	var hand:    Array = _bs.player_hand    if is_player else _bs.ai_hand
	var discard: Array = _bs.player_discard if is_player else _bs.ai_discard
	var moved: int = 0
	var scan: int = hand.size() - 1
	for _i in n:
		while scan >= 0 and (hand[scan] as CardData).is_preserved_by_keyword():
			scan -= 1
		if scan < 0:
			break
		var cd := hand[scan] as CardData
		hand.remove_at(scan)
		scan -= 1
		send_to_discard(cd, discard)
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
		# 시전자가 없는 카드(오브젝트 보상)는 "다른 파일럿의 카드"가 아니다 —
		# 애초에 주인이 없으므로 이 카드가 걷어 갈 대상이 아니고, `보존`
		# 키워드도 강제 버리기를 막는다.
		if cd.owner_pilot == null or cd.is_preserved_by_keyword():
			continue
		hand.erase(cd)
		send_to_discard(cd, discard)
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
			# The node is about to be freed, so any drag pointing at it has to go
			# first — otherwise _drag_card dangles and the description box /
			# targeting overlay outlive the card they belong to.
			if _drag_card == c or _press_card == c:
				deselect_current_card()
			_bs.player_card_nodes.erase(c)
			play_discard_fx(c)
			return


## 손패를 떠나 버려지는 카드의 연출 — 아래로 내려가며 사라진 뒤 스스로 free
## 된다. 노드는 **호출 전에 이미 `player_card_nodes` 에서 빠져 있어야 한다**:
## 연출이 도는 0.3초 동안 레이아웃 · 호버 · 히트 밴드가 그 카드를 여전히 손패의
## 일원으로 세면 남은 카드들이 빈자리를 메우지 못한다.
##
## `CardSelectOverlay._commit_discard` 도 이 함수를 쓴다 — 버리기:N 으로 화면
## 중앙에 늘어세운 카드들이 확정될 때 같은 연출로 내려간다.
func play_discard_fx(node: Card) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.begin_discard_fx()


# ═══ 메크 카드 절 ═══════════════════════════════════════════════════════════
# 아래는 전부 `mech_cards.csv` 만 쓰는 절이다. 공용 카드(cards.csv)는 하나도
# 건드리지 않으므로, 이 블록을 통째로 들어내도 예전 카드들은 그대로 돈다.
#
# 절 이름이 공용 쪽과 겹치지 않는 것은 의도된 것이다 — 카드 한 장의 `effect`
# 문자열만 보고도 "이건 기체가 주는 카드"임이 읽혀야 하고, 겹치는 이름은
# 나중에 한쪽 규칙을 고칠 때 다른 쪽을 조용히 함께 바꾼다.

## `|self` 가 붙었으면 시전자, 아니면 지정한 아군. 지정이 비었으면 가장 체력이
## 적은 아군으로 떨어진다 — AI 경로가 대상을 못 고르는 카드에서도 절이 no-op 이
## 되지 않게 하려는 것이고, 보호(`shield_pct`)가 이미 쓰는 규칙과 같다.
func _ally_subject(flags: Array, caster: PilotData, ally_team: int,
		picked: PilotData) -> PilotData:
	if "self" in flags:
		return caster
	if picked != null and picked.alive and picked.team == ally_team:
		return picked
	var best: PilotData = null
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.alive and p.team == ally_team:
			if best == null or p.hp < best.hp:
				best = p
	return best


## `|per_hit` 이 붙었으면 직전 공격 절의 명중 수, 아니면 1. 0 을 돌려줄 수 있다
## (한 대도 못 맞힌 공격 뒤의 절은 아무 일도 하지 않는 것이 옳다).
func _repeat_count(flags: Array) -> int:
	if "per_hit" in flags:
		return _last_attack_hits
	if "per_kill" in flags:
		return _last_attack_kills
	if "stack" in flags:
		return _stack_of_current_card()
	return 1


func _effect_heal_pct(pct: int, flags: Array, caster: PilotData,
		ally_team: int, picked: PilotData) -> String:
	var t: PilotData = _ally_subject(flags, caster, ally_team, picked)
	if t == null:
		return "회복 (대상 없음)"
	var times: int = _repeat_count(flags)
	if times <= 0:
		return ""
	var healed: int = 0
	for _i in times:
		var amount: int = int(t.max_hp * pct / 100)
		var before: int = t.hp
		t.hp = mini(t.max_hp, t.hp + amount)
		healed += t.hp - before
	return "회복 +%d %s" % [healed, _bs.pilot_label(t)]


## 최대 체력 영구 증가. `bonus_max_hp` 로 들어가야 성장 재계산에 지워지지 않는다
## — 늘어난 만큼 현재 체력도 함께 오른다(`refresh_growth_stats` 가 그렇게 한다).
func _effect_max_hp(amount: int, flags: Array, caster: PilotData,
		ally_team: int, picked: PilotData) -> String:
	var t: PilotData = _ally_subject(flags, caster, ally_team, picked)
	if t == null:
		return "최대 체력 (대상 없음)"
	t.bonus_max_hp += amount * maxi(1, _repeat_count(flags))
	_bs.refresh_growth_stats(t)
	return "최대 체력 +%d %s" % [amount, _bs.pilot_label(t)]


func _effect_atk_add(amount: int, flags: Array, caster: PilotData,
		ally_team: int, picked: PilotData) -> String:
	var t: PilotData = _ally_subject(flags, caster, ally_team, picked)
	if t == null:
		return "공격력 (대상 없음)"
	t.bonus_atk_flat += amount * maxi(1, _repeat_count(flags))
	_bs.refresh_growth_stats(t)
	return "공격력 +%d %s" % [amount, _bs.pilot_label(t)]


## 시전자 **공격력의 N%** 만큼 보호막. 보호(`shield_pct`)가 대상의 최대 체력을
## 기준으로 삼는 것과 대비되는데, 지원 Q 의 두 장은 "이 기체가 얼마나 센가"를
## 파는 카드라서 기준점이 시전자 쪽이어야 한다.
##
## 걸어 준 보호막은 **누가 걸었는지 기억된다**(`MechSkillSystem.shield_source`) —
## 수호 연계 패시브가 그 아군의 공격에 편승할 근거가 그 표다.
func _effect_shield_atk(pct: int, flags: Array, caster: PilotData,
		ally_team: int, picked: PilotData) -> String:
	if caster == null:
		return "보호막 (시전자 없음)"
	var amount: int = int(caster.atk * pct / 100)
	var targets: Array = []
	if "all_allies" in flags:
		for raw in _bs.pilots:
			var p := raw as PilotData
			if p.alive and p.team == ally_team:
				targets.append(p)
	else:
		var t: PilotData = _ally_subject(flags, caster, ally_team, picked)
		if t != null:
			targets.append(t)
	if targets.is_empty():
		return "보호막 (대상 없음)"
	for raw in targets:
		var p := raw as PilotData
		p.shield += amount
		if _bs.mech_skill != null:
			_bs.mech_skill.shield_source[p] = caster
	return "보호막 +%d ×%d" % [amount, targets.size()]


func _effect_reactive_armor(n: int, flags: Array, caster: PilotData,
		ally_team: int, picked: PilotData) -> String:
	var t: PilotData = _ally_subject(flags, caster, ally_team, picked)
	if t == null:
		return "반응 장갑 (대상 없음)"
	var add: int = n * maxi(0, _repeat_count(flags))
	if add <= 0:
		return ""
	t.reactive_armor += add
	return "반응 장갑 +%d %s" % [add, _bs.pilot_label(t)]


## 메크 패시브 충전. `|per_hit` 이면 직전 공격의 명중 수만큼.
func _effect_charge(n: int, flags: Array, caster: PilotData) -> String:
	if caster == null or _bs.mech_skill == null:
		return ""
	var add: int = n * maxi(0, _repeat_count(flags))
	if add <= 0:
		return ""
	var gained: int = _bs.mech_skill.add_charge(caster, add)
	return "충전 +%d (%d/%d)" % [gained,
			_bs.mech_skill.charge_of(caster),
			_bs.mech_skill.max_charge_of(caster)]


## 성장 점수를 **소모**한다. 시트의 "성장 점수 100" 은 게임 안의 `1.00k` 이고,
## 그 환산은 `MechSkillSystem.SCORE_COST_UNIT` 한 곳에만 적혀 있다.
##
## [밸런스] 를 손에 들고 있으면 같은 기체의 카드는 이 비용을 내지 않는다 —
## 카드 한 장이 다른 카드들의 가격표를 지우는 유일한 자리다.
func _effect_score_cost(n: int, caster: PilotData) -> String:
	if caster == null:
		return ""
	if _bs.mech_skill != null and _bs.mech_skill.score_cost_waived(_current_card):
		return "성장 점수 면제 (밸런스)"
	var cost: float = float(n) * MechSkillSystem.SCORE_COST_UNIT
	_bs.add_score(caster, -cost)
	return "성장 점수 −%.2fk" % cost


## 성장 **효율**(적립 배율)을 전장 이탈까지 올린다. 누적되는 몫이라
## `growth_rate_bonus` 에 얹는다 — 카드끼리 덮어쓰는 `growth_rate_mult` 슬롯에
## 넣으면 라인전 카드 한 장이 이 효과를 지운다(용 보상과 같은 이유).
func _effect_growth_eff(pct: int, ally_team: int, caster: PilotData,
		picked: PilotData) -> String:
	var t: PilotData = _ally_subject([], caster, ally_team, picked)
	if t == null:
		return "성장 효율 (대상 없음)"
	t.growth_rate_bonus += float(pct) / 100.0
	return "성장 효율 %+d%% %s" % [pct, _bs.pilot_label(t)]


## 메크 카드를 **만든다**. `to_hand` 면 손패로, 아니면 덱에 섞어서.
##   |per_hit   직전 공격의 명중 수만큼
##   |per_kill  직전 공격에서 눕힌 수만큼
##   |temp      만들어진 카드에 `소멸 · 휘발성`을 덧입힌다 (정밀 폭격의 미사일)
func _effect_gen_card(card_id: int, flags: Array, caster: PilotData,
		is_player: bool, to_hand: bool) -> String:
	var times: int = maxi(0, _repeat_count(flags))
	if times <= 0 or caster == null:
		return ""
	var made: int = 0
	var label: String = ""
	for _i in times:
		var cd: CardData = make_mech_card_by_id(card_id, caster)
		if cd == null:
			break
		if "temp" in flags:
			cd.keyword = _merge_keywords(cd.keyword,
					[CardData.KW_EXHAUST, CardData.KW_VOLATILE])
		label = cd.card_name
		if to_hand:
			add_card_to_hand(cd, is_player)
		else:
			var deck: Array = _bs.player_deck if is_player else _bs.ai_deck
			deck.append(cd)
		made += 1
	if made == 0:
		return ""
	if not to_hand:
		var deck2: Array = _bs.player_deck if is_player else _bs.ai_deck
		deck2.shuffle()
	update_deck_discard_labels()
	return "[%s] %s %d장 생성" % [label, "핸드" if to_hand else "덱", made]


## 키워드 목록에 없는 것만 덧붙인다. `|` 로 구분된 목록이라 문자열을 이어 붙이는
## 것만으로는 중복이 생긴다.
func _merge_keywords(base: String, add: Array) -> String:
	var have: Array = []
	for raw in base.split("|", false):
		var k: String = (raw as String).strip_edges()
		if not k.is_empty():
			have.append(k)
	for raw in add:
		var k: String = raw as String
		if not have.has(k):
			have.append(k)
	return "|".join(have)


## 덱에서 **특정 카드**를 찾아 손패로. `|count:N` 으로 장수를 정하며 기본 1장.
## 찾기(`search:N`)가 아무 카드나 고르게 하는 것과 달리 이쪽은 카드가 지목돼
## 있으므로 모달이 없다 — 고를 것이 없는 선택은 클릭 한 번을 버리는 일이다.
func _effect_search_card(card_id: int, flags: Array, caster: PilotData,
		is_player: bool) -> String:
	var want: int = maxi(1, _flag_int(flags, "count", 1))
	var deck: Array = _bs.player_deck if is_player else _bs.ai_deck
	var taken: int = 0
	var label: String = ""
	for i in range(deck.size() - 1, -1, -1):
		if taken >= want:
			break
		var cd := deck[i] as CardData
		if cd.mech_card_id != card_id:
			continue
		if caster != null and cd.owner_pilot != caster:
			continue
		deck.remove_at(i)
		label = cd.card_name
		add_card_to_hand(cd, is_player)
		taken += 1
	update_deck_discard_labels()
	if taken == 0:
		return "탐색 (덱에 없음)"
	return "[%s] %d장 탐색" % [label, taken]


## 묘지 탐색의 **AI / 폴백 경로**. 플레이어는 `_process_pending_chain` 이
## 오버레이로 가로채므로 여기 오지 않는다.
func _effect_search_discard(n: int, is_player: bool) -> String:
	var discard: Array = _bs.player_discard if is_player else _bs.ai_discard
	var taken: int = 0
	for _i in n:
		if discard.is_empty():
			break
		var cd := discard.pop_back() as CardData
		add_card_to_hand(cd, is_player)
		taken += 1
	update_deck_discard_labels()
	return "묘지 탐색 %d장" % taken


## 묘지 **드로우** — 고르지 않고 위에서부터 N장. 탐색과 다른 것은 선택의 유무다.
## `|cost_reduce:N` 이 붙으면 그렇게 올라온 카드만 비용이 내려간다(변덕).
func _effect_draw_discard(n: int, flags: Array, is_player: bool) -> String:
	var discard: Array = _bs.player_discard if is_player else _bs.ai_discard
	var cut: int = _flag_int(flags, "cost_reduce", 0)
	var taken: int = 0
	for _i in n:
		if discard.is_empty():
			break
		var cd := discard.pop_back() as CardData
		if cut > 0 and cd.is_playable():
			cd.cost = maxi(0, cd.cost - cut)
		add_card_to_hand(cd, is_player)
		taken += 1
	update_deck_discard_labels()
	if cut > 0:
		return "묘지 드로우 %d장 (비용 −%d)" % [taken, cut]
	return "묘지 드로우 %d장" % taken


## 밀기 — 전진과 같은 미니틱을 N번 돌린다. `|bonus_clear:N` 은 "도중에 적을 한
## 번도 만나지 않았으면" 얹는 추가 걸음이고, 판정은 밀고 난 뒤 시전자 칸에 적이
## 있는지로 갈음한다.
func _effect_push(steps: int, flags: Array, caster: PilotData) -> String:
	if caster == null or not caster.alive or steps <= 0:
		return "밀기 (시전자 없음)"
	var log_lines: Array = []
	_bs.sim_core.advance_pilot(caster, steps, log_lines)
	var bonus: int = _flag_int(flags, "bonus_clear", 0)
	var clear: bool = true
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.alive and p.team != caster.team and p.grid_pos == caster.grid_pos:
			clear = false
			break
	if bonus > 0 and clear:
		_bs.sim_core.advance_pilot(caster, bonus, log_lines)
		return "밀기 %d (+%d 추가)" % [steps, bonus]
	return "밀기 %d" % steps


## 최면 — **적을** 자기 HQ 쪽으로 N칸 민다. 시전자가 아니라 대상이 움직이는
## 유일한 이동 절이라, 전진과 같은 미니틱을 대상 기준으로 돌린다.
func _effect_move_target(steps: int, caster: PilotData,
		picked: PilotData) -> String:
	if picked == null or not picked.alive or caster == null:
		return "이동 (대상 없음)"
	var log_lines: Array = []
	_bs.sim_core.advance_pilot(picked, steps, log_lines)
	return "%s 이동 %d" % [_bs.pilot_label(picked), steps]


## 질풍 — 시전자가 **대상의 칸으로** 뛰어든다. 시트의 "작전 단계가 끝나면 이전
## 위치로 복귀"는 2단계로 미뤄 둔다(복귀 예약을 들고 있을 자리가 아직 없다) —
## 지금은 뛰어들기만 하고 그 자리에 남는다.
func _effect_move_to_target(caster: PilotData, picked: PilotData) -> String:
	if caster == null or picked == null or not caster.alive:
		return "이동 (대상 없음)"
	if _bs.skill != null and _bs.skill.blocks_move(caster):
		return "이동 (위치 고정)"
	var orig := caster.grid_pos
	if orig == picked.grid_pos:
		return ""
	caster.grid_pos = picked.grid_pos
	_bs.blog.log_move(caster, orig, caster.grid_pos, "card-dive")
	_bs.anim_pilot_move(caster, orig)
	return "돌입 → %s" % _bs.pilot_label(picked)


## 매혹적인 침공 / 사형 선고 — 적을 **시전자 칸으로** 끌어온다.
## `|self_range:N` 이 붙으면 그 반경 안의 적 전부, 없으면 지정한 하나.
func _effect_pull_to_caster(flags: Array, caster: PilotData,
		enemy_team: int) -> String:
	if caster == null or not caster.alive:
		return "끌어오기 (시전자 없음)"
	var radius: int = _flag_int(flags, "self_range", -1)
	var moved: int = 0
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive or p.team != enemy_team:
			continue
		if radius >= 0:
			if _bs.hex_grid.hex_distance(caster.grid_pos, p.grid_pos) > radius:
				continue
		elif not _is_pending_target(p):
			continue
		if p.grid_pos == caster.grid_pos:
			continue
		var orig := p.grid_pos
		p.grid_pos = caster.grid_pos
		_bs.blog.log_move(p, orig, p.grid_pos, "card-pull")
		_bs.anim_pilot_move(p, orig)
		moved += 1
	return "끌어오기 %d명" % moved


func _is_pending_target(p: PilotData) -> bool:
	return _current_target == p


## 단계 A 의 목표 — 이 적이 **시전자에게** 받는 피해가 오른다. 한 명만 지목할 수
## 있고 새로 찍으면 앞의 것을 덮는다(전장에 목표가 둘이면 단계 B 가 어느 쪽으로
## 열릴지 정할 수 없다).
func _effect_mark_target(pct: int, caster: PilotData,
		picked: PilotData) -> String:
	if picked == null or caster == null:
		return "목표 (대상 없음)"
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.marked_by == caster:
			p.marked_by = null
			p.marked_bonus = 0.0
	picked.marked_by = caster
	picked.marked_bonus = float(pct) / 100.0
	return "목표 %s (+%d%%)" % [_bs.pilot_label(picked), pct]


## 추적 — 이 적이 전투에 들어가면 시전자도 함께 끌려 들어간다. 만료 턴을 함께
## 적어 두고 `MechSkillSystem.tick_expiries` 가 걷는다.
func _effect_track(turns: int, caster: PilotData, picked: PilotData) -> String:
	if picked == null or caster == null:
		return "추적 (대상 없음)"
	picked.tracked_by.append({
		"pilot": caster,
		"expire_turn": _bs.turn_count + turns,
	})
	return "추적 %s (%d턴)" % [_bs.pilot_label(picked), turns]


## 결속 — 시전자가 싸울 때 이 아군도 무대에 선다. 방향이 한쪽뿐인 것이 요점이다
## (지정한 아군이 싸울 때 시전자가 끌려가지는 않는다).
func _effect_link_engage(caster: PilotData, picked: PilotData) -> String:
	if caster == null or picked == null:
		return "결속 (대상 없음)"
	caster.engage_link = picked
	return "결속 → %s" % _bs.pilot_label(picked)


func _effect_stun_next(picked: PilotData) -> String:
	if picked == null:
		return "강타 (대상 없음)"
	picked.stun_charge = true
	return "강타 %s" % _bs.pilot_label(picked)


func _effect_no_engage_phase(picked: PilotData) -> String:
	if picked == null:
		return "탈진 (대상 없음)"
	picked.engage_locked = true
	return "탈진 %s (이번 작전 단계)" % _bs.pilot_label(picked)


func _effect_dmg_taken(pct: int, picked: PilotData) -> String:
	if picked == null:
		return "받는 피해 (대상 없음)"
	# 중첩되지 않는다 — 같은 카드를 두 장 써도 값이 그대로다.
	picked.damage_taken_bonus = maxf(picked.damage_taken_bonus, float(pct) / 100.0)
	return "받는 피해 +%d%% %s" % [pct, _bs.pilot_label(picked)]


## 현상금 — 대상의 **성장치 N%** 를 값으로 찍는다. [확신] 이 이 값을 피해로
## 바꾼다. 중첩되지 않으므로 더 큰 쪽만 남는다.
func _effect_bounty(pct: int, picked: PilotData) -> String:
	if picked == null:
		return "현상금 (대상 없음)"
	picked.bounty = maxf(picked.bounty, picked.score * float(pct) / 100.0)
	return "현상금 %.2fk %s" % [picked.bounty, _bs.pilot_label(picked)]


## 매혹 — 대상이 버는 성장치를 그대로 복사해 간다. 적에게도 걸 수 있다.
func _effect_growth_link(turns: int, caster: PilotData,
		picked: PilotData) -> String:
	if caster == null or picked == null:
		return "매혹 (대상 없음)"
	picked.growth_link_to = caster
	picked.growth_link_expire_turn = _bs.turn_count + turns
	return "매혹 %s (%d턴)" % [_bs.pilot_label(picked), turns]


## 명상 — 손패에서 **이 카드보다 왼쪽**을 전부 버린다. 자리를 모르면(AI 경로)
## 손패 전체를 버린다: 명상은 손을 통째로 갈아 끼우는 카드이므로 그쪽이 의도에
## 더 가깝다.
func _effect_discard_left(is_player: bool) -> String:
	var hand: Array = _bs.player_hand if is_player else _bs.ai_hand
	var discard: Array = _bs.player_discard if is_player else _bs.ai_discard
	var limit: int = _current_card_index
	if limit < 0:
		limit = hand.size()
	var victims: Array = []
	for i in mini(limit, hand.size()):
		var cd := hand[i] as CardData
		if not cd.is_preserved_by_keyword():
			victims.append(cd)
	for raw in victims:
		var cd := raw as CardData
		hand.erase(cd)
		if _bs.mech_skill != null:
			_bs.mech_skill.on_card_discarded(cd, is_player)
		send_to_discard(cd, discard)
		if is_player:
			_despawn_player_card_node(cd)
	_last_discarded_count = victims.size()
	_refresh_hand_after_bulk_change(is_player)
	return "왼쪽 %d장 버리기" % victims.size()


func _effect_draw_discarded(is_player: bool) -> String:
	var drew: int = 0
	for _i in _last_discarded_count:
		var c := draw_card(is_player)
		if c == null:
			break
		if is_player and not last_draw_merged:
			spawn_card_node(c)
		drew += 1
	_refresh_hand_after_bulk_change(is_player)
	return "드로우 %d" % drew


## 처형 — 충전을 전부 태워 **최대 체력 N% 이하**인 적 또는 포탑을 즉사시킨다.
## 충전이 모자라면 카드가 그냥 사라진다(그것이 카드 텍스트의 "이 카드 제거"다).
func _effect_execute(pct: int, flags: Array, caster: PilotData,
		picked: Variant) -> String:
	if caster == null or _bs.mech_skill == null:
		return "처형 (시전자 없음)"
	var need: int = maxi(1, _flag_int(flags, "charge", 5))
	if _bs.mech_skill.charge_of(caster) < need:
		return "처형 불발 (충전 %d/%d)" % [
				_bs.mech_skill.charge_of(caster), need]
	var victim: Variant = picked
	if victim == null:
		var cell: Variant = _pending_target_cell()
		if cell is Vector2i:
			victim = _foe_at_cell(cell as Vector2i, 1 - caster.team)
	if victim is PilotData:
		var p := victim as PilotData
		if not p.alive or float(p.hp) > float(p.max_hp) * float(pct) / 100.0:
			return "처형 불발 (체력 초과)"
		_bs.mech_skill.spend_charge(caster, need)
		_bs.mark_pilot_dead(p, caster)
		return "처형 %s" % _bs.pilot_label(p)
	if victim is TurretData:
		var td := victim as TurretData
		if not td.alive or float(td.hp) > float(td.max_hp) * float(pct) / 100.0:
			return "처형 불발 (체력 초과)"
		_bs.mech_skill.spend_charge(caster, need)
		var log_lines: Array = []
		_bs.sim_core.apply_card_turret_damage(td, td.hp, caster, log_lines)
		return "포탑 처형 T%d %s" % [td.tier, _bs.LANE_NAMES[td.lane]]
	return "처형 (대상 없음)"


## 확신 — 대상에게 찍힌 **현상금의 N%** 를 그대로 피해로 넣는다. 공격력과 무관한
## 유일한 피해원이라 명중 판정만 공유하고 계산은 따로 한다.
func _effect_attack_bounty(pct: int, caster: PilotData,
		picked: PilotData) -> String:
	if caster == null or picked == null or not picked.alive:
		return "확신 (대상 없음)"
	if not _bs.sim_core.roll_hit(caster, picked):
		if _bs.renderer != null:
			_bs.renderer.spawn_pilot_popup(picked, "MISS",
					BattleRenderer.POPUP_MISS_COLOR, 0.0)
		_chain_hit = false
		return "확신 빗나감"
	# 현상금은 성장치(k) 단위라 피해로 쓰려면 점수 표기 단위로 되돌려야 한다.
	var dmg: int = maxi(1, int(picked.bounty / MechSkillSystem.SCORE_COST_UNIT
			* float(pct) / 100.0))
	var before: int = picked.hp
	if picked.shield > 0:
		var absorbed: int = mini(picked.shield, dmg)
		picked.shield -= absorbed
		dmg -= absorbed
	if dmg > 0:
		picked.hp = maxi(0, picked.hp - dmg)
	_bs.record_pilot_damage(caster, picked, before - picked.hp)
	if _bs.renderer != null:
		_bs.renderer.spawn_pilot_popup(picked, "-%d" % (before - picked.hp),
				BattleRenderer.POPUP_DAMAGE_COLOR, 0.0)
	if picked.hp <= 0:
		_bs.mark_pilot_dead(picked, caster)
	_chain_hit = true
	return "확신 %s -%d" % [_bs.pilot_label(picked), before - picked.hp]


## 주먹다짐 — 시전자와 대상이 **N번씩 서로** 때린다. 대상의 공격은 필중이고
## 시전자의 공격은 판정을 굴린다: 그 비대칭이 이 카드의 값이다.
func _effect_mutual_attack(times: int, caster: PilotData,
		picked: PilotData) -> String:
	if caster == null or picked == null or not picked.alive:
		return "주먹다짐 (대상 없음)"
	var out_dmg: int = 0
	var in_dmg: int = 0
	for _i in maxi(1, times):
		if picked.alive and _bs.sim_core.roll_hit(caster, picked):
			out_dmg += _apply_attack_damage(picked, caster, 1)
		if caster.alive:
			in_dmg += _apply_attack_damage(caster, picked, 1)
		if not caster.alive:
			break
	_chain_hit = out_dmg > 0
	return "주먹다짐 −%d / 자신 −%d" % [out_dmg, in_dmg]


## 고통과 쾌감 — 전장의 **모든 적이** 시전자를 필중으로 한 대씩 친다. 받아 내는
## 것이 곧 이득인 기체(탱커 N)의 카드라, 맞는 만큼 최대 체력이 오르는 그 기체의
## 패시브와 짝이다.
func _effect_taunt_all(caster: PilotData, enemy_team: int) -> String:
	if caster == null or not caster.alive:
		return "도발 (시전자 없음)"
	var total: int = 0
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive or p.team != enemy_team:
			continue
		total += _apply_attack_damage(caster, p, 1)
		if not caster.alive:
			break
	return "도발 — 자신 −%d" % total
