class_name ObjectiveRewardFx
extends Node

# 오브젝트(전령 / 용) **보상 획득 연출** — 보상이 실제로 손패나 덱에 들어가기
# 직전에 그 카드를 화면 한가운데에 펼쳐 보여 주고, 들어갈 자리로 날려 보낸다.
#
# 왜 필요한가: 보상은 `ObjectiveSystem._grant_reward` 한 줄로 들어간다. 그
# 결과는 손패가 한 장 늘거나(전령) 덱 숫자가 다섯 오르는 것(용)뿐이라, 오브젝트
# 하나를 두고 4인 교전까지 벌인 끝의 보답치고는 화면에 아무 일도 일어나지
# 않았다. 특히 용은 **덱에 섞여 들어가므로** 그 자리에서는 손에 잡히는 것이
# 하나도 없다 — 무엇을 받았는지는 카드를 실물로 한 번 보여 줘야 한다.
#
# 두 오브젝트의 연출이 다른 것은 **보상이 들어가는 자리가 다르기 때문**이다.
#
#   • **용** — 보상 카드 N장이 중앙에 부채꼴로 펼쳐졌다가 **한 장처럼 겹쳐지고**,
#     좌측 아래 **덱 뭉치**로 빨려 들어간다. 겹쳐지는 박자가 "이 여러 장이 이제
#     한 더미가 된다"이고, 덱으로 향하는 방향이 "지금 쓸 수는 없다"이다.
#   • **전령** — 보상 카드 한 장이 중앙에 떠올랐다가 **손패 맨 왼쪽 자리**로
#     내려앉는다. 손으로 곧장 들어오는 카드라 덱을 거치지 않는다.
#
# 적이 가져간 경우에는 둘 다 **상단 상대 손패의 왼쪽 끝**으로 날아가 사라진다.
# 상대의 덱은 화면에 없으므로 용도 그 자리를 쓴다 — 중요한 것은 "누구 것이
# 됐는가"이고, 그 답은 카드가 위로 갔는지 아래로 갔는지가 말한다.
#
# 배선: `BattleSim._ready()` 가 `ObjectiveSystem` 옆에 붙이고 `_bs.objective_fx`
# 로 잡는다. 진입점은 `ObjectiveSystem._grant_reward()` 하나이고, 그 함수가
# **연출을 await 한 뒤에** 실제 지급(`CardPhaseManager.grant_cards_to_*`)을
# 부른다 — 순서가 반대면 연출이 도는 동안 이미 손패에 카드가 서 있어 같은 카드가
# 두 군데에 보인다.


## 딤과 카드가 사는 층. 열람(12) · 보상 미리보기(12)와 같은 높이 — 셋이 동시에
## 뜰 일이 없다(연출이 도는 동안 `ObjectiveSystem._busy` 가 전장을 붙잡는다).
const OVERLAY_LAYER: int = 12

const VP_W: float = 1080.0
const VP_H: float = 1920.0

## 카드가 펼쳐지는 자리(카드 **중심** 기준). 전장 한가운데(y 860)보다 살짝
## 아래다 — 위쪽에는 상대 손패와 상단 패널이, 아래에는 내 손패가 있어 그 사이가
## 가장 넓게 비는 띠다.
const CENTER := Vector2(540.0, 880.0)

## 펼친 카드 사이의 가로 간격(px)과 양 끝 기울기(도). 다섯 장이 화면(1080)
## 안에 온전히 들어와야 하므로 간격은 카드 폭(160)보다 좁다 — 겹쳐 펼치는 것이
## 손패 부채꼴과 같은 문법이기도 하다.
const FAN_STEP_PX: float = 118.0
const FAN_TILT_DEG: float = 7.0
## 펼쳐진 카드의 배율. 손패 카드보다 크게 보여 준다(읽으라고 띄운 것이다).
const CARD_SCALE := Vector2(1.05, 1.05)

const SPREAD_SEC: float = 0.34
const HOLD_SEC: float = 0.70
## 부채꼴이 한 장으로 겹쳐지는 시간. 용에서만 돈다(한 장짜리 전령은 겹칠 것이 없다).
const COLLAPSE_SEC: float = 0.26
## 겹쳐진 뒤 목적지로 출발하기까지의 뜸(s). 없으면 겹치는 동작이 곧바로 비행에
## 먹혀 "한 장이 됐다"가 안 읽힌다.
const COLLAPSE_HOLD_SEC: float = 0.14
const FLY_SEC: float = 0.42
## 목적지에 도착했을 때의 배율 — 빨려 들어가는 만큼 작아진다.
const FLY_END_SCALE := Vector2(0.34, 0.34)

const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const DIM_FADE_SEC: float = 0.20

var _bs: BattleSim = null
var _layer: CanvasLayer = null
var _root: Control = null


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = OVERLAY_LAYER
	_layer.name = "ObjectiveRewardFxLayer"
	add_child(_layer)


func bind(bs: BattleSim) -> void:
	_bs = bs


# ─── 진입점 ──────────────────────────────────────────────────────────────────
## 보상 카드 `count` 장을 중앙에 펼쳤다가 목적지로 날린다. 연출이 끝나야 반환되며,
## 실제 지급은 호출 측이 그 뒤에 한다.
##
## `to_deck` 이 용(덱으로 섞여 들어감) / 전령(손패로 곧장)을 가른다. 적 팀이
## 가져간 경우에는 둘 다 상대 손패 왼쪽 끝으로 향하므로 이 플래그를 보지 않는다.
##
## 화면을 세울 수 없는 상황(카드 DB 미스 · 렌더 트리 없음)에서는 조용히 반환한다
## — 연출 하나 때문에 보상이 막히면 안 된다.
func play(card_id: int, is_player: bool, count: int, to_deck: bool) -> void:
	if _bs == null or _bs.card_phase == null or _layer == null:
		return
	var n: int = clampi(count, 0, 8)
	if n <= 0:
		return
	# 딤이 `_root` 를 만들고 카드는 그 밑에 선다 — 순서가 반대면 카드가 부모
	# 없이 뜬다.
	var dim: ColorRect = _build_dim()
	var nodes: Array = _build_cards(card_id, n)
	if nodes.is_empty():
		_teardown()
		return

	# ① 중앙에 부채꼴로 펼친다.
	_tween_spread(nodes)
	await _wait(SPREAD_SEC)
	await _wait(HOLD_SEC)

	# ② 여러 장이면 한 장처럼 겹친다.
	if nodes.size() > 1:
		_tween_collapse(nodes)
		await _wait(COLLAPSE_SEC + COLLAPSE_HOLD_SEC)

	# ③ 목적지로 날아간다. 딤은 이때 걷는다 — 덱 뭉치도 상대 손패도 딤 아래에
	#    있어서, 어디로 들어가는지를 보여 주려면 그 순간에 화면이 밝아야 한다.
	if dim != null and is_instance_valid(dim):
		var tw_dim := create_tween()
		tw_dim.tween_property(dim, "color", Color(DIM_COLOR.r, DIM_COLOR.g,
				DIM_COLOR.b, 0.0), FLY_SEC)
	_tween_fly(nodes, _destination(is_player, to_deck))
	await _wait(FLY_SEC)
	_teardown()


# ─── 목적지 ──────────────────────────────────────────────────────────────────
## 카드가 빨려 들어갈 지점(카드 **중심** 기준, 뷰포트 좌표).
##
##   • 적 팀      → 상단 상대 손패의 왼쪽 끝
##   • 나 · 덱    → 좌측 아래 덱 뭉치
##   • 나 · 손패  → 손패 맨 왼쪽 슬롯(그 자리에 실제로 삽입된다)
func _destination(is_player: bool, to_deck: bool) -> Vector2:
	if not is_player:
		return _ai_hand_left_center()
	if to_deck:
		return _deck_pile_center()
	return _hand_left_center()


## 덱 뭉치의 한가운데. 뭉치가 없으면(HUD 미구축) 화면 왼쪽 아래로 폴백한다.
func _deck_pile_center() -> Vector2:
	if _bs.pile_deck != null and is_instance_valid(_bs.pile_deck):
		return _bs.pile_deck.position + _bs.pile_deck.size * 0.5
	return Vector2(40.0, _bs.BS_HAND_CENTER.y + Card.CARD_H * 0.5)


## 상대 손패 왼쪽 끝 카드의 한가운데.
func _ai_hand_left_center() -> Vector2:
	if _bs.hud != null:
		return _bs.hud.ai_hand_left_anchor() + Vector2(Card.CARD_W, Card.CARD_H) * 0.5
	return Vector2(220.0, 140.0)


## 손패 맨 왼쪽 슬롯의 한가운데. **카드가 한 장 더 늘어난 뒤의** 배치로 재야
## 실제로 앉을 자리와 맞는다(`slot_position` 은 총 장수로 자리를 나눈다).
func _hand_left_center() -> Vector2:
	var total: int = _bs.player_card_nodes.size() + 1
	var slot: Vector2 = _bs.card_phase.slot_position(0, total)
	return slot + Vector2(Card.CARD_W, Card.CARD_H) * 0.5


# ─── 노드 ────────────────────────────────────────────────────────────────────
## 보상 카드 노드 `n` 장을 중앙에 겹쳐 세운다(아직 안 보인다). 손패와 같은
## `Card.tscn` 을 쓰는 이유는 `ObjectiveRewardPopup` 과 같다 — 따로 그린 그림이면
## 실제로 들어온 카드와 같은 것인지 확인할 길이 없다.
func _build_cards(card_id: int, n: int) -> Array:
	var out: Array = []
	for _i in n:
		var cd: CardData = _bs.card_phase.make_objective_card(card_id)
		if cd == null:
			break
		var node := _bs.CARD_SCENE.instantiate() as Card
		# add_child 가 setup 보다 **먼저** — Card.gd 의 @onready 참조는 트리에
		# 들어간 뒤에야 풀린다(CardPileViewer / ObjectiveRewardPopup 과 동일).
		_root.add_child(node)
		node.setup(cd, false, true)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in node.get_children():
			if child is Control:
				(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 회전 · 배율이 카드 한가운데를 축으로 돌도록. 그래서 아래의 자리 계산은
		# 전부 "중심 − 반 카드" 다(HudBuilder._layout_ai_hand 와 같은 규약).
		node.pivot_offset = Vector2(Card.CARD_W, Card.CARD_H) * 0.5
		node.position = CENTER - node.pivot_offset
		node.rotation = 0.0
		node.scale = Vector2(0.55, 0.55)
		node.modulate = Color(1, 1, 1, 0)
		out.append(node)
	return out


func _build_dim() -> ColorRect:
	_root = Control.new()
	_root.name = "ObjectiveRewardFx"
	# CanvasLayer 아래의 Control 은 full-rect 앵커를 풀어 줄 부모 rect 가 없다 —
	# 크기를 명시한다(PilotDetailPanel · ObjectiveRewardPopup 과 같은 이유).
	_root.position = Vector2.ZERO
	_root.size = Vector2(VP_W, VP_H)
	# 연출은 관전 전용이라 입력을 받을 것이 없다. 다만 딤이 STOP 이라 뒤쪽으로
	# 클릭이 새지는 않는다 — 그동안 눌린 손패가 나중에 반응하면 안 된다.
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(DIM_COLOR.r, DIM_COLOR.g, DIM_COLOR.b, 0.0)
	dim.position = Vector2.ZERO
	dim.size = Vector2(VP_W, VP_H)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# 카드보다 **먼저** 붙는다 — 형제 z-order 가 곧 자식 인덱스라, 나중에 붙으면
	# 딤이 카드를 덮는다.
	_root.add_child(dim)
	_root.move_child(dim, 0)
	var tw := create_tween()
	tw.tween_property(dim, "color", DIM_COLOR, DIM_FADE_SEC)
	return dim


func _teardown() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null


# ─── 박자 ────────────────────────────────────────────────────────────────────
## ① 중앙에서 부채꼴로 펼쳐지며 나타난다.
func _tween_spread(nodes: Array) -> void:
	var n: int = nodes.size()
	var half := Vector2(Card.CARD_W, Card.CARD_H) * 0.5
	for i in n:
		var node := nodes[i] as Card
		var k: float = float(i) - float(n - 1) * 0.5
		var at: Vector2 = CENTER + Vector2(k * FAN_STEP_PX, 0.0)
		var tilt: float = 0.0
		if n > 1:
			tilt = deg_to_rad(k / (float(n - 1) * 0.5) * FAN_TILT_DEG)
		var tw := create_tween().set_parallel()
		tw.tween_property(node, "position", at - half, SPREAD_SEC).set_ease(
				Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(node, "rotation", tilt, SPREAD_SEC).set_ease(
				Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(node, "scale", CARD_SCALE, SPREAD_SEC).set_ease(
				Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(node, "modulate", Color.WHITE, SPREAD_SEC * 0.6)


## ② 부채꼴이 한 장으로 겹쳐진다 — 전부 같은 자리 · 같은 각도로 모인다.
func _tween_collapse(nodes: Array) -> void:
	var half := Vector2(Card.CARD_W, Card.CARD_H) * 0.5
	for raw in nodes:
		var node := raw as Card
		var tw := create_tween().set_parallel()
		tw.tween_property(node, "position", CENTER - half, COLLAPSE_SEC).set_ease(
				Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(node, "rotation", 0.0, COLLAPSE_SEC).set_ease(
				Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)


## ③ 목적지로 빨려 들어가며 작아지고 사라진다. 겹쳐진 뒤라 여러 장이어도 한
## 뭉치로 움직인다.
func _tween_fly(nodes: Array, to_center: Vector2) -> void:
	var half := Vector2(Card.CARD_W, Card.CARD_H) * 0.5
	for raw in nodes:
		var node := raw as Card
		var tw := create_tween().set_parallel()
		tw.tween_property(node, "position", to_center - half, FLY_SEC).set_ease(
				Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(node, "scale", FLY_END_SCALE, FLY_SEC).set_ease(
				Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		# 알파는 뒤쪽 절반에서만 빠진다 — 처음부터 흐려지면 어디로 가는지가 안 보인다.
		tw.tween_property(node, "modulate", Color(1, 1, 1, 0),
				FLY_SEC * 0.5).set_delay(FLY_SEC * 0.5)


## 트윈의 `finished` 가 아니라 타이머로 기다린다 — 노드가 도중에 free 되면
## (재시작 · 씬 전환) 그 신호는 영영 오지 않아 코루틴이 매달린다. 드로우
## 인트로(`CardPhaseManager._play_draw_intro`)가 같은 이유로 같은 규칙을 쓴다.
func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
