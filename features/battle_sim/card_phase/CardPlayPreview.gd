class_name CardPlayPreview
extends Control

# 손패 카드 **미리보기** — 카드를 누르거나 끄는 동안 "이 카드를 쓰면 무엇이
# 일어나는가"를 화면에 미리 그린다. 놓거나 취소하면 전부 사라진다(시전이
# 확정된 뒤의 연출은 각자의 자리 — 버프 배너는 `BattleRenderer.spawn_buff_banner`).
#
# 세 군데에 나눠 그린다.
#   • **이 노드의 `_draw`** (캔버스, `z_index` 로 손패 위) — 덱 / 버린 더미 위
#     chevron 기둥 + 장수, 찾기 돋보기, 보존 자물쇠.
#   • **손패 카드 자신** — 버려질 카드의 붉은 딤 + 아래 chevron 은 카드의 자식
#     (`Card.DoomMark`)이 그린다. 이 노드는 무엇이 버려질지만 정하고
#     (`doomed_cards`), 켜고 끄는 것은 `CardPhaseManager.refresh_doom_marks` 다.
#     이 층에 모아 그리던 시절에는 겹친 카드의 딤끼리 포개졌다.
#   • **`BattleRenderer`** (전장 좌표) — 시전자 하얀 네온, 이동 경로 화살표,
#     공격 예상(명중률 · 깎일 체력), 회복 / 보호막 예상, 복귀 · 후퇴 고스트,
#     약탈 · 정글 파밍의 영혼 궤적. 렌더러가 `field_spec()` / `neon_pilot()` 을 읽는다.
#   • **남의 위젯에 상태만 건다** — 전략 점수 도넛(`CostDonut.set_preview`),
#     손패 카드 비용 리본(`Card.set_cost_preview`). 하단 스트립 초상의 시전자
#     네온은 삭제됐다 — 끄는 동안 스트립은 어두워져 내려간다.
#
# 단계는 둘이다. **누른 순간**(`show_caster`)에는 시전자만 강조하고, **끌기
# 시작하면**(`begin`) 효과 미리보기가 붙는다. 대상이 있는 카드는 손가락 밑의
# 대상이 바뀔 때마다 `set_target` 이 다시 계산한다.

## 기둥 하나의 chevron 수 / 간격 / 크기.
const CHEVRON_COUNT: int = 3
const CHEVRON_STEP: float = 30.0
const CHEVRON_W: float = 54.0
const CHEVRON_H: float = 18.0
const CHEVRON_THICK: float = 7.0
## 흐름 속도(칸 / 초) — 한 칸 = `CHEVRON_STEP`.
const FLOW_SPEED: float = 1.6
## 기둥 아래끝과 더미 윗변 사이.
const PILE_GAP: float = 10.0
const COUNT_FONT: int = 34

const DRAW_COLOR    := Color(0.55, 0.95, 1.00)
const DISCARD_COLOR := Color(1.00, 0.45, 0.40)
## 덱 더미 위 "비용 -N" 태그 — 어두운 전장 위라 밝은 초록.
const PILE_DISCOUNT_COLOR := Color(0.45, 1.0, 0.45)
const SEARCH_COLOR  := Color(1.00, 0.88, 0.45)
const PRESERVE_COLOR := Color(0.45, 0.90, 1.00)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.85)
## 버려질 카드 위 붉은 딤(`Card.DoomMark` 가 읽는다).
const DOOMED_TINT   := Color(0.85, 0.08, 0.06, 0.34)

var _bs: BattleSim = null
var _card: CardData = null
var _caster: PilotData = null
## 손가락 밑 대상 — PilotData / Vector2i / null.
var _target: Variant = null
var _dragging: bool = false
var _t: float = 0.0
## 이번 카드의 미리보기 내용. `_rebuild` 가 채운다.
var _spec: Dictionary = {}


func setup(bs: BattleSim) -> void:
	_bs = bs
	name = "CardPlayPreview"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = ScreenMetrics.viewport_size()
	# 손패 카드 노드는 `_reorder_hand_nodes` 가 끊임없이 자식 목록 끝으로 올리므로
	# 자식 순서로는 그 위에 설 수 없다 — z_index 로 선다.
	z_index = 20
	set_process(false)


# ─── 공개 진입점 (CardPhaseManager) ──────────────────────────────────────────

## 카드를 **눌렀다** — 시전자만 강조한다.
func show_caster(cd: CardData) -> void:
	if cd == null:
		clear()
		return
	if _card == cd and not _dragging:
		return
	_card = cd
	_caster = cd.owner_pilot
	_target = null
	_dragging = false
	_spec = {}
	_activate()


## 끌기 시작 — 효과 미리보기까지 켠다.
func begin(cd: CardData) -> void:
	if cd == null:
		clear()
		return
	_card = cd
	_caster = cd.owner_pilot
	_target = null
	_dragging = true
	_rebuild()
	_activate()


## 손가락 밑 대상이 바뀌었다.
func set_target(target: Variant) -> void:
	if not _dragging or _card == null:
		return
	if typeof(target) == typeof(_target) and target == _target:
		return
	_target = target
	_rebuild()


func clear() -> void:
	if _card == null and _spec.is_empty():
		return
	_card = null
	_caster = null
	_target = null
	_dragging = false
	_spec = {}
	_push_widgets()
	set_process(false)
	queue_redraw()
	_kick_renderer()


func is_active() -> bool:
	return _card != null


## 전장 시전자 네온의 주인(없으면 null).
func neon_pilot() -> PilotData:
	if _caster == null or not _caster.alive:
		return null
	return _caster


## 렌더러가 읽는 전장 쪽 미리보기. 키: `attack` / `restore` / `ghost` / `soul`. 없는 키는 그릴 것이 없다는 뜻.
func field_spec() -> Dictionary:
	return _spec.get("field", {}) as Dictionary


## 끄는 카드의 효과로 버려질 손패 카드(CardData). 끄는 중이 아니면 빈 배열.
func doomed_cards() -> Array:
	if not _dragging:
		return []
	return _spec.get("doomed", []) as Array


## 연출 시계(초). 렌더러가 같은 시계로 흐르게 한다.
func anim_time() -> float:
	return _t


func _activate() -> void:
	set_process(true)
	queue_redraw()
	_kick_renderer()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	_kick_renderer()


func _kick_renderer() -> void:
	if _bs != null and _bs.renderer != null:
		_bs.renderer.queue_redraw()


# ─── 미리보기 내용 계산 ──────────────────────────────────────────────────────

func _rebuild() -> void:
	_spec = _compute_spec(_card, _caster, _target)
	_push_widgets()
	queue_redraw()
	_kick_renderer()


## 카드 효과 체인을 훑어 "무엇을 보여 줄지"를 정한다. `on_hit` / `on_miss` 뒤의
## 조건부 절은 결과를 미리 알 수 없으므로 건너뛴다.
func _compute_spec(cd: CardData, caster: PilotData, target: Variant) -> Dictionary:
	var spec: Dictionary = {}
	if cd == null or _bs == null or _bs.card_phase == null:
		return spec
	var cp: CardPhaseManager = _bs.card_phase
	var hand: Array = _hand_without(cd)
	var picked: PilotData = target as PilotData if target is PilotData else null
	var cell: Variant = target if target is Vector2i else null
	var field: Dictionary = {}
	var doomed: Array = []
	var draw_n: int = 0
	var discard_pick: int = 0
	var draw_from_discard: int = 0
	var search_deck: int = 0
	var search_discard: int = 0
	var preserve_n: int = 0
	var strat_gain: int = 0
	var has_strategy: bool = false
	var cost_cut_all: int = 0
	var cost_cut_engage: int = 0
	var deck_cost_cut: int = 0
	for raw in cp.effect_clauses(cd):
		var e: Dictionary = raw
		var ename: String = String(e["name"])
		var v: int = int(e["value"])
		var flags: Array = e["flags"] as Array
		if ename == "on_hit" or ename == "on_miss":
			break
		match ename:
			"draw":
				draw_n += v
			"draw_next_phase", "strategy_next_phase", "strategy_on_kill":
				pass    # 다음 단계 예약 — 미리보기 대신 시전 뒤 예약 칩이 남는다.
			"search":
				search_deck += v
			"search_card":
				search_deck += maxi(1, cp.flag_int(flags, "count", 1))
			"search_discard":
				search_discard += maxi(1, v)
			"draw_discard":
				draw_from_discard += v
				deck_cost_cut += cp.flag_int(flags, "cost_reduce", 0)
			"discard":
				discard_pick += v
			"discard_hand":
				_add_unique(doomed, hand)
			"discard_hand_draw":
				var all: Array = cp.discardable(hand)
				_add_unique(doomed, all)
				draw_n += all.size()
			"discard_right":
				_add_unique(doomed, _rightmost(hand, v))
			"discard_left":
				_add_unique(doomed, _leftmost(hand, 1))
			"draw_discarded":
				draw_n += 1
			"discard_other_pilots":
				var others: Array = _other_pilots_cards(hand, caster)
				_add_unique(doomed, others)
				var per: int = cp.flag_int(flags, "strategy_each", 0)
				if per != 0:
					has_strategy = true
					strat_gain += per * others.size()
			"preserve":
				preserve_n += v
			"strategy":
				has_strategy = true
				strat_gain += v
			"cost_reduce_hand":
				cost_cut_all += v
			"cost_reduce_engage":
				cost_cut_engage += v
			"cost_reduce_draw_phase":
				deck_cost_cut += v
			"move":
				_spec_move(field, caster, cell)
			"ambush":
				_spec_move(field, caster, cell)
			"steal_camp":
				if cell != null and caster != null \
						and _bs.sim_core.camp_charged(cell as Vector2i):
					field["soul"] = {"cell": cell, "pilot": caster,
							"amount": _bs.jungle_camp_score()}
			"retreat_turret":
				if caster != null and caster.alive:
					var to: Vector2i = cp.nearest_own_turret_cell(caster)
					if to != caster.grid_pos:
						field["ghost"] = {"pilot": caster, "to": to,
								"path": _bfs_path(caster.grid_pos, to)}
			"recall_ally":
				if picked != null:
					var hq: Vector2i = _bs.PLAYER_HQ_POS if picked.team == 0 \
							else _bs.ENEMY_HQ_POS
					field["ghost"] = {"pilot": picked, "to": hq, "path": []}
					field["restore"] = {"pilot": picked,
							"heal": picked.max_hp - picked.hp, "shield": 0}
			"attack":
				if picked != null and picked.team != _caster_team(caster) \
						and not field.has("attack"):
					field["attack"] = _attack_preview(caster, picked, v, flags)
			"shield_pct":
				if picked != null:
					_add_restore(field, picked, 0, int(picked.max_hp * v / 100))
			"shield_atk":
				if caster != null:
					var who: PilotData = caster if "self" in flags else picked
					if who != null:
						_add_restore(field, who, 0, int(caster.atk * v / 100))
			"heal_pct":
				var who_h: PilotData = caster if "self" in flags else picked
				if who_h != null and not "per_hit" in flags:
					_add_restore(field, who_h, int(who_h.max_hp * v / 100), 0)
	spec["field"] = field
	spec["doomed"] = doomed
	spec["draw"] = draw_n
	spec["discard_pick"] = discard_pick
	spec["draw_from_discard"] = draw_from_discard
	spec["search_deck"] = search_deck
	spec["search_discard"] = search_discard
	spec["preserve"] = preserve_n
	spec["deck_cost_cut"] = deck_cost_cut
	if has_strategy:
		spec["strategy_gain"] = strat_gain
		spec["strategy_after"] = maxi(0, _bs.player_cost
				- _bs.effective_cost_for(cd, true) + strat_gain)
	spec["cost_preview"] = _cost_changes(hand, cost_cut_all, cost_cut_engage)
	return spec


func _caster_team(caster: PilotData) -> int:
	return caster.team if caster != null else 0


## 손패에서 지금 끄는 카드를 뺀 것 — 카드가 나가는 순간 손패를 떠나므로 체인의
## "오른쪽 N장" 같은 질문은 그 카드가 빠진 손패에 대한 것이다.
func _hand_without(cd: CardData) -> Array:
	var out: Array = []
	for raw in _bs.player_hand:
		if raw != cd:
			out.append(raw)
	return out


static func _add_unique(into: Array, items: Array) -> void:
	for raw in items:
		if not into.has(raw):
			into.append(raw)


## `_effect_discard_right` 와 같은 규칙 — 오른쪽부터, `보존` 키워드는 건너뛴다.
static func _rightmost(hand: Array, n: int) -> Array:
	var out: Array = []
	var i: int = hand.size() - 1
	while i >= 0 and out.size() < n:
		var cd := hand[i] as CardData
		if not cd.is_preserved_by_keyword():
			out.append(cd)
		i -= 1
	return out


static func _leftmost(hand: Array, n: int) -> Array:
	var out: Array = []
	for raw in hand:
		if out.size() >= n:
			break
		var cd := raw as CardData
		if not cd.is_preserved_by_keyword():
			out.append(cd)
	return out


## `_effect_discard_other_pilots` 와 같은 규칙.
static func _other_pilots_cards(hand: Array, caster: PilotData) -> Array:
	var out: Array = []
	if caster == null:
		return out
	for raw in hand:
		var cd := raw as CardData
		if cd.owner_pilot == caster or cd.owner_pilot == null \
				or cd.is_preserved_by_keyword():
			continue
		out.append(cd)
	return out


## 비용이 바뀔 손패 카드 → 바뀐 뒤의 **실효 비용**.
func _cost_changes(hand: Array, cut_all: int, cut_engage: int) -> Dictionary:
	var out: Dictionary = {}
	if cut_all <= 0 and cut_engage <= 0:
		return out
	for raw in hand:
		var cd := raw as CardData
		if not cd.is_playable():
			continue
		var cut: int = cut_all
		if cut_engage > 0 and _bs.card_phase.card_has_engage(cd):
			cut += cut_engage
		if cut <= 0:
			continue
		var eff: int = _bs.effective_cost_for(cd, true)
		var after: int = maxi(0, eff - cut)
		if after != eff:
			out[cd] = after
	return out


func _spec_move(field: Dictionary, caster: PilotData, cell: Variant) -> void:
	if caster == null or cell == null:
		return
	var to := cell as Vector2i
	if to == caster.grid_pos:
		return
	# 이동은 순간이동이라 경로를 그리지 않는다 — 도착 칸에 반투명 초상(고스트)
	# 하나만 세운다(`line = false`: 지금 자리와 잇는 점선도 없다). 정글 캠프 위에
	# 내려앉아 먹게 될 성장치도 여기서는 보여 주지 않는다.
	field["ghost"] = {"pilot": caster, "to": to, "path": [], "line": false}


## 칸 단위 최단 경로(양 끝 포함) — 후퇴 고스트가 "어느 칸을 지나 어디로
## 가는가"를 타일 단위로 보여 준다.
func _bfs_path(from: Vector2i, to: Vector2i) -> Array:
	var came: Dictionary = {from: from}
	var queue: Array = [from]
	var found: bool = false
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == to:
			found = true
			break
		for nb in _bs.pathfinder.neighbors(cur):
			if not came.has(nb):
				came[nb] = cur
				queue.append(nb)
	if not found:
		return [from, to]
	var path: Array = [to]
	while path[-1] != from:
		path.append(came[path[-1]])
	path.reverse()
	return path


func _attack_preview(caster: PilotData, t: PilotData, n: int,
		flags: Array) -> Dictionary:
	var chance: float = 1.0
	if not "pierce" in flags and caster != null:
		chance = _bs.sim_core.hit_chance_of(caster, t)
	var hits: int = 1
	if "charge" in flags and _card != null and _card.is_charge_card():
		hits = maxi(1, _card.charge)
	var dmg: int = _bs.card_phase.estimate_attack_damage(caster, t, n) * hits
	return {"pilot": t, "chance": chance, "damage": dmg,
			"repeat": "repeat" in flags}


func _add_restore(field: Dictionary, p: PilotData, heal: int, shield: int) -> void:
	var cur: Dictionary = field.get("restore", {}) as Dictionary
	if not cur.is_empty() and cur["pilot"] != p:
		return
	field["restore"] = {
		"pilot": p,
		"heal": int(cur.get("heal", 0)) + heal,
		"shield": int(cur.get("shield", 0)) + shield,
	}


# ─── 남의 위젯에 상태 걸기 ───────────────────────────────────────────────────

func _push_widgets() -> void:
	if _bs == null:
		return
	if _bs.card_phase != null:
		_bs.card_phase.refresh_doom_marks()
	if _bs.cost_donut != null:
		if _spec.has("strategy_gain"):
			# 위에 뜨는 값은 **효과가 더하는 양**, 가운데 숫자는 비용까지 치른
			# 실제 결과다 — 둘 다 플레이어가 묻는 질문이다.
			_bs.cost_donut.set_preview(true, int(_spec["strategy_gain"]),
					int(_spec["strategy_after"]))
		else:
			_bs.cost_donut.set_preview(false, 0, 0)
	var changes: Dictionary = _spec.get("cost_preview", {}) as Dictionary
	var any_cleared: bool = false
	for node in _bs.player_card_nodes:
		var c := node as Card
		if c == null or c.data == null:
			continue
		if changes.has(c.data):
			c.set_cost_preview(int(changes[c.data]))
		elif c.has_cost_preview():
			c.clear_cost_preview()
			any_cleared = true
	# 미리보기를 걷은 카드는 원래 값(수정자 색 포함)으로 다시 칠한다.
	if any_cleared and _bs.card_phase != null:
		_bs.card_phase.highlight_affordable_cards()


# ─── 그리기 (덱 / 버린 더미 / 손패 위) ───────────────────────────────────────

func _draw() -> void:
	if not _dragging or _spec.is_empty():
		return
	var font := ThemeDB.fallback_font
	var draw_n: int = int(_spec.get("draw", 0))
	var search_deck: int = int(_spec.get("search_deck", 0))
	var deck_cut: int = int(_spec.get("deck_cost_cut", 0))
	if draw_n > 0:
		_draw_pile_column(_bs.pile_deck, true, DRAW_COLOR, "+%d" % draw_n, font)
	elif search_deck > 0:
		_draw_pile_search(_bs.pile_deck, search_deck, font)
	if deck_cut > 0:
		_draw_pile_tag(_bs.pile_deck, Loc.t(L.BATTLE_PLAY_PREVIEW_COST_CUT, {"n": deck_cut}), font)
	var discard_pick: int = int(_spec.get("discard_pick", 0))
	var from_discard: int = int(_spec.get("draw_from_discard", 0))
	var search_discard: int = int(_spec.get("search_discard", 0))
	if discard_pick > 0:
		_draw_pile_column(_bs.pile_discard, false, DISCARD_COLOR,
				"-%d" % discard_pick, font)
	elif from_discard > 0:
		_draw_pile_column(_bs.pile_discard, true, DRAW_COLOR,
				"+%d" % from_discard, font)
	elif search_discard > 0:
		_draw_pile_search(_bs.pile_discard, search_discard, font)
	var preserve_n: int = int(_spec.get("preserve", 0))
	if preserve_n > 0:
		_draw_preserve_hint(preserve_n, font)


## 더미의 **그림** rect(이 노드 좌표) — 위끝은 맨 위 카드의 윗변이다. 노드
## rect 는 손패 띠 높이 전체라 그 위에 얹으면 도넛과 겹친다.
func _pile_rect(pile: CardPileStack) -> Rect2:
	if pile == null or not is_instance_valid(pile):
		return Rect2()
	var xf: Transform2D = get_global_transform().affine_inverse() \
			* pile.get_global_transform()
	var top: Vector2 = xf * Vector2(0.0, pile.stack_top_local())
	var bottom: Vector2 = xf * pile.size
	return Rect2(Vector2(xf.origin.x, top.y),
			Vector2(bottom.x - xf.origin.x, bottom.y - top.y))


## 더미 위 chevron 기둥 + 맨 위 장수. `up` = 뽑기(위로 흐른다), 아니면 버리기.
func _draw_pile_column(pile: CardPileStack, up: bool, col: Color, label: String,
		font: Font) -> void:
	var r: Rect2 = _pile_rect(pile)
	if r.size == Vector2.ZERO:
		return
	var cx: float = r.get_center().x
	var bottom: float = r.position.y - PILE_GAP
	var span: float = CHEVRON_STEP * float(CHEVRON_COUNT)
	var phase: float = fposmod(_t * FLOW_SPEED, 1.0)
	# 칸 수 + 1 개를 흘려 보내고 양 끝에서 페이드 — 이어지는 흐름으로 읽힌다.
	for i in CHEVRON_COUNT + 1:
		var k: float = (float(i) + phase) / float(CHEVRON_COUNT + 1)   # 0..1
		var y: float
		if up:
			y = bottom - CHEVRON_H * 0.5 - k * span
		else:
			y = bottom - span + CHEVRON_H * 0.5 + k * span
		var a: float = clampf(minf(k, 1.0 - k) * 4.0, 0.0, 1.0)
		_draw_chevron(Vector2(cx, y), up, col, a)
	_draw_count(Vector2(cx, bottom - span - 8.0), label, col, font)


## 찾기 — 더미 위 돋보기 + 장수.
func _draw_pile_search(pile: CardPileStack, n: int, font: Font) -> void:
	var r: Rect2 = _pile_rect(pile)
	if r.size == Vector2.ZERO:
		return
	var bob: float = sin(_t * 4.0) * 4.0
	var c := Vector2(r.get_center().x, r.position.y - PILE_GAP - 40.0 + bob)
	var ring_r: float = 17.0
	var hdir := Vector2(0.7071, 0.7071)
	draw_line(c + hdir * ring_r, c + hdir * (ring_r + 18.0), OUTLINE_COLOR, 12.0)
	draw_arc(c, ring_r, 0.0, TAU, 32, OUTLINE_COLOR, 10.0, true)
	draw_line(c + hdir * ring_r, c + hdir * (ring_r + 18.0), SEARCH_COLOR, 7.0)
	draw_arc(c, ring_r, 0.0, TAU, 32, SEARCH_COLOR, 5.0, true)
	draw_circle(c, ring_r - 3.0, Color(SEARCH_COLOR.r, SEARCH_COLOR.g,
			SEARCH_COLOR.b, 0.18))
	_draw_count(Vector2(c.x, c.y - ring_r - 14.0), str(n), SEARCH_COLOR, font)


## 더미 위 작은 꼬리표(뽑는 카드 비용 할인).
func _draw_pile_tag(pile: CardPileStack, text: String, font: Font) -> void:
	var r: Rect2 = _pile_rect(pile)
	if r.size == Vector2.ZERO:
		return
	var fsz: int = 20
	var tsz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz)
	var at := Vector2(r.get_center().x - tsz.x * 0.5, r.position.y + tsz.y + 6.0)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, 5,
			OUTLINE_COLOR)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz,
			PILE_DISCOUNT_COLOR)


## 보존 — 손패 행 위 가운데에 자물쇠 + 장수.
func _draw_preserve_hint(n: int, font: Font) -> void:
	var nodes: Array = _bs.player_card_nodes
	if nodes.is_empty():
		return
	var top: float = INF
	var left: float = INF
	var right: float = -INF
	for node in nodes:
		var c := node as Card
		if c == null or c.is_dragging:
			continue
		var r: Rect2 = c.get_global_rect()
		top = minf(top, r.position.y)
		left = minf(left, r.position.x)
		right = maxf(right, r.end.x)
	if top == INF:
		return
	var bob: float = sin(_t * 4.0) * 3.0
	var c0 := Vector2((left + right) * 0.5 - 30.0, top - 46.0 + bob)
	# 몸통 + 고리.
	var body := Rect2(c0.x - 18.0, c0.y - 4.0, 36.0, 28.0)
	draw_arc(Vector2(c0.x, c0.y - 4.0), 12.0, PI, TAU, 16, OUTLINE_COLOR, 10.0, true)
	draw_arc(Vector2(c0.x, c0.y - 4.0), 12.0, PI, TAU, 16, PRESERVE_COLOR, 5.0, true)
	draw_rect(body.grow(3.0), OUTLINE_COLOR)
	draw_rect(body, PRESERVE_COLOR)
	draw_circle(Vector2(c0.x, c0.y + 9.0), 4.0, OUTLINE_COLOR)
	var label: String = Loc.t(L.BATTLE_PLAY_PREVIEW_PRESERVE, {"n": n})
	var tsz: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			COUNT_FONT - 6)
	var at := Vector2(c0.x + 28.0, c0.y + tsz.y * 0.35)
	draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			COUNT_FONT - 6, 7, OUTLINE_COLOR)
	draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT - 6,
			PRESERVE_COLOR)


func _draw_chevron(c: Vector2, up: bool, col: Color, alpha: float) -> void:
	draw_chevron(self, c, up, col, alpha)


## chevron 한 개(검은 테 + 본 색). 손패 카드의 버려질 표시(`Card` 의 DoomMark)와
## 오브젝트 보상 미리보기(`ui/ObjectiveRewardPopup.gd`)도 같은 모양을 쓴다.
static func draw_chevron(ci: CanvasItem, c: Vector2, up: bool, col: Color,
		alpha: float) -> void:
	if alpha <= 0.01:
		return
	var dy: float = -CHEVRON_H * 0.5 if up else CHEVRON_H * 0.5
	var pts := PackedVector2Array([
		Vector2(c.x - CHEVRON_W * 0.5, c.y - dy),
		Vector2(c.x, c.y + dy),
		Vector2(c.x + CHEVRON_W * 0.5, c.y - dy),
	])
	ci.draw_polyline(pts, Color(0, 0, 0, 0.8 * alpha), CHEVRON_THICK + 5.0, true)
	ci.draw_polyline(pts, Color(col.r, col.g, col.b, alpha), CHEVRON_THICK, true)


## 아래로 흐르는 chevron 기둥 — `top` 에서 시작해 `CHEVRON_STEP × CHEVRON_COUNT`
## 만큼 흘러 내려가며 양 끝에서 페이드한다. `t` 는 초 단위 시계.
static func draw_falling_chevrons(ci: CanvasItem, cx: float, top: float,
		col: Color, t: float) -> void:
	var phase: float = fposmod(t * FLOW_SPEED, 1.0)
	var span: float = CHEVRON_STEP * float(CHEVRON_COUNT)
	for i in CHEVRON_COUNT + 1:
		var k: float = (float(i) + phase) / float(CHEVRON_COUNT + 1)
		var a: float = clampf(minf(k, 1.0 - k) * 4.0, 0.0, 1.0)
		draw_chevron(ci, Vector2(cx, top + k * span), false, col, a)


## 가운데 정렬 큰 숫자. `bottom_center` 는 글자 기준선 가운데.
func _draw_count(bottom_center: Vector2, text: String, col: Color, font: Font) -> void:
	var tsz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			COUNT_FONT)
	var at := Vector2(bottom_center.x - tsz.x * 0.5, bottom_center.y)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT,
			8, OUTLINE_COLOR)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT, col)
