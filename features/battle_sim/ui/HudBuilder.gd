class_name HudBuilder
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim

# ── Role → portrait background color ─────────────────────────────────────────
const ROLE_COLORS := [
	Color(0.2, 0.4, 0.9),   # TANK
	Color(0.9, 0.5, 0.1),   # FIGHTER
	Color(0.6, 0.1, 0.8),   # ASSASSIN
	Color(0.1, 0.7, 0.3),   # SUPPORT
	Color(0.8, 0.2, 0.1),   # SNIPER
]

# ── Top panel layout ─────────────────────────────────────────────────────────
const TOP_PANEL_Y      := 10.0
const TOP_PANEL_H      := 120.0
const SIDE_MARGIN      := 10.0
const SLOT_W           := 84.0
const SLOT_H           := 108.0
# 5 slots + 5 slots + center => center width is whatever's left.
const PILOTS_PER_SIDE  := 5
const PILOT_BLOCK_W    := SLOT_W * PILOTS_PER_SIDE  # 420
const CENTER_W         := 1080.0 - SIDE_MARGIN * 2.0 - PILOT_BLOCK_W * 2.0  # 220

# Slot internals — vertical HP bar removed; face image takes the freed space and
# a horizontal HP bar sits directly under the face.
const PORTRAIT_X       := 4.0
const PORTRAIT_Y       := 0.0
const PORTRAIT_W       := SLOT_W - PORTRAIT_X * 2.0  # 76
const PORTRAIT_H       := 76.0
const HBAR_X           := PORTRAIT_X
const HBAR_Y           := PORTRAIT_Y + PORTRAIT_H + 2.0  # 78
const HBAR_W           := PORTRAIT_W                       # 76
const HBAR_H           := 6.0
const SCORE_Y          := HBAR_Y + HBAR_H + 4.0            # 88
const SCORE_H          := 16.0

# Placeholder score (real scoring system not implemented yet).
const PLACEHOLDER_SCORE := "1.0k"

# ── AI hand peek (below score panel) ─────────────────────────────────────────
# AI hand is shown as a row of card-back nodes whose tops are tucked behind
# the score panel — only ~AI_HAND_PEEK_PX of each card protrudes below the
# panel, giving an "edge of the cards" look that just conveys hand size.
const AI_HAND_SCALE  := 0.45
const AI_HAND_TOP_Y  := 80.0   # most of the card hides behind the score panel
const AI_HAND_GAP    := 6.0    # px gap between adjacent card backs at full spread

# ── 전략 포인트 도넛 (cost gauges) ────────────────────────────────────────────
# The old bottom cell-bar stack and the rectangular 단계 넘기기 button are gone.
# Both sides now read out on a ring gauge in the right-hand gutter:
#   player — above the Discard counter, top-right of the hand row; doubles as
#            the 턴 넘기기 button once tapped (see CostDonut).
#   enemy  — top-right of the screen, just under the AI hand peek.
const DONUT_FILL_PLAYER := Color(0.25, 0.60, 1.00)
const DONUT_FILL_ENEMY  := Color(0.95, 0.35, 0.25)
## Vertical gap between the player donut and the targeting overlay's
## 취소 / 확인 button row, which itself hovers just above the hand row. Keeping
## the donut clear of that band means the two never overlap mid-targeting.
const DONUT_HAND_GAP    := 24.0
## Vertical gap between the AI hand peek's bottom edge and the enemy donut.
const DONUT_AI_HAND_GAP := 20.0
## Fallback 100% mark used before DataLoader fills PHASE_THRESHOLD.
const DONUT_DEFAULT_MAX := 8

# ── Pilot slot refs (internal to HudBuilder) ─────────────────────────────────
var _player_slots: Array = []   # team 0, on the left
var _enemy_slots:  Array = []   # team 1, on the right

# ── Center labels ────────────────────────────────────────────────────────────
var _lbl_time: Label = null
var _lbl_total_score: Label = null


# ── AI hand peek refs ────────────────────────────────────────────────────────
# `_ai_hand_root` is added to the canvas BEFORE `_build_top_panel`, so the
# score panel z-orders above it and visually clips the cards' top portion.
var _ai_hand_root:        Control = null
var _ai_card_back_nodes:  Array   = []   # Array<Card> — face-down cards

# ── Turn announcer refs ──────────────────────────────────────────────────────
# Centre-screen "당신의 차례 / 상대 차례" banner shown when CARD_PHASE starts
# (player) or before the AI's run_ai_plays loop (enemy). Built last so it
# z-orders above every other HUD element including the AI hand.
var _turn_announce_root: Control = null


func build_ui() -> void:
	_bs.canvas = CanvasLayer.new()
	_bs.add_child(_bs.canvas)

	# AI hand peek must build BEFORE the score panel so the panel's opaque
	# background covers the cards' top portion (sibling z-order = child index).
	_build_ai_hand_peek()
	_build_top_panel()
	_build_hand_indicators()
	_build_cost_donuts()
	_build_victory_panel()
	# Turn announcer added last so its banner draws over everything.
	_build_turn_announcer()


# ── Deck / Discard count labels ──────────────────────────────────────────────
# Live in the BS_HAND_AREA_MARGIN gutters on either side of the hand row.
# The hand row spans y=BS_HAND_CENTER.y .. y=BS_HAND_CENTER.y + Card.CARD_H,
# so we centre the labels vertically across that same band.
const HAND_INDICATOR_FONT       := 22
const HAND_INDICATOR_TITLE_COL  := Color(0.85, 0.85, 0.85)
func _build_hand_indicators() -> void:
	var hand_y: float = _bs.BS_HAND_CENTER.y
	var hand_h: float = Card.CARD_H
	var margin: float = _bs.BS_HAND_AREA_MARGIN
	# Inset the labels a few px so they don't kiss the screen edge.
	var inset: float  = 8.0
	var w: float      = margin - inset * 2.0

	_bs.lbl_deck_count = Label.new()
	_bs.lbl_deck_count.text = "Deck\n0"
	_bs.lbl_deck_count.add_theme_font_size_override("font_size", HAND_INDICATOR_FONT)
	_bs.lbl_deck_count.add_theme_color_override("font_color", HAND_INDICATOR_TITLE_COL)
	_bs.lbl_deck_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bs.lbl_deck_count.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_bs.lbl_deck_count.position = Vector2(inset, hand_y)
	_bs.lbl_deck_count.size     = Vector2(w, hand_h)
	_bs.canvas.add_child(_bs.lbl_deck_count)

	var screen_w := get_viewport().get_visible_rect().size.x
	_bs.lbl_discard_count = Label.new()
	_bs.lbl_discard_count.text = "Discard\n0"
	_bs.lbl_discard_count.add_theme_font_size_override("font_size", HAND_INDICATOR_FONT)
	_bs.lbl_discard_count.add_theme_color_override("font_color", HAND_INDICATOR_TITLE_COL)
	_bs.lbl_discard_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bs.lbl_discard_count.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_bs.lbl_discard_count.position = Vector2(screen_w - margin + inset, hand_y)
	_bs.lbl_discard_count.size     = Vector2(w, hand_h)
	_bs.canvas.add_child(_bs.lbl_discard_count)


# ── Top panel: 5 player slots | center (time + total score) | 5 enemy slots ──
func _build_top_panel() -> void:
	var tp := Panel.new()
	tp.position = Vector2(0.0, TOP_PANEL_Y)
	tp.size     = Vector2(1080.0, TOP_PANEL_H)
	# Force an opaque dark background so the AI hand card backs sitting
	# behind this panel are visually clipped to the peek strip below.
	var tp_style := StyleBoxFlat.new()
	tp_style.bg_color = Color(0.06, 0.06, 0.10, 1.0)
	tp_style.border_color = Color(0.18, 0.18, 0.24, 1.0)
	tp_style.border_width_top    = 1
	tp_style.border_width_bottom = 1
	tp_style.border_width_left   = 1
	tp_style.border_width_right  = 1
	tp.add_theme_stylebox_override("panel", tp_style)
	_bs.canvas.add_child(tp)

	var slot_y := (TOP_PANEL_H - SLOT_H) * 0.5  # vertical centering inside panel

	# Player slots — leftmost block
	for i in range(PILOTS_PER_SIDE):
		var sx := SIDE_MARGIN + i * SLOT_W
		_player_slots.append(_build_slot(tp, sx, slot_y))

	# Center column
	var center_x := SIDE_MARGIN + PILOT_BLOCK_W
	_lbl_time = UiHelpers.mk_label(tp, "00:00", 18, Color(0.85, 0.85, 0.85),
			Vector2(center_x, slot_y + 2.0), Vector2(CENTER_W, 22.0),
			HORIZONTAL_ALIGNMENT_CENTER)
	_lbl_total_score = UiHelpers.mk_label(tp, "%s - %s" % [PLACEHOLDER_SCORE, PLACEHOLDER_SCORE],
			28, Color(1.0, 0.95, 0.6),
			Vector2(center_x, slot_y + 30.0), Vector2(CENTER_W, 50.0),
			HORIZONTAL_ALIGNMENT_CENTER)

	# Enemy slots — rightmost block
	var enemy_block_x := SIDE_MARGIN + PILOT_BLOCK_W + CENTER_W
	for i in range(PILOTS_PER_SIDE):
		var sx := enemy_block_x + i * SLOT_W
		_enemy_slots.append(_build_slot(tp, sx, slot_y))


# AI hand peek — row of face-down card backs whose tops hide behind the score
# panel. update_ai_hand_visuals() syncs the visible count to `_bs.ai_hand`.
func _build_ai_hand_peek() -> void:
	_ai_hand_root = Control.new()
	_ai_hand_root.position = Vector2.ZERO
	_ai_hand_root.size     = Vector2(1080.0, 1920.0)
	_ai_hand_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Force opaque dark background on the score panel later by giving the
	# panel an explicit StyleBoxFlat. The panel is created in `_build_top_panel`,
	# but we apply the override here so the AI cards always stay visually
	# clipped, even with a transparent default theme.
	_bs.canvas.add_child(_ai_hand_root)


# Sync `_ai_card_back_nodes` count with `_bs.ai_hand.size()` and reflow.
# Called from CardPhaseManager.do_battle_turn() after the AI draws, and from
# pop_ai_hand_card_node() after AiCardPlayer pulls a card out for the
# centre animation.
func update_ai_hand_visuals() -> void:
	if _ai_hand_root == null:
		return
	var n: int = _bs.ai_hand.size()
	while _ai_card_back_nodes.size() < n:
		var card := _bs.CARD_SCENE.instantiate() as Card
		card.scale = Vector2(AI_HAND_SCALE, AI_HAND_SCALE)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# add_child BEFORE setup — Card.gd's @onready refs only resolve after
		# the node enters the tree; setup() touches card_back/card_front.
		_ai_hand_root.add_child(card)
		card.setup(null, false, false)  # face-down card back
		# Belt-and-braces: card sub-controls also non-interactive.
		for child in card.get_children():
			if child is Control:
				(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ai_card_back_nodes.append(card)
	while _ai_card_back_nodes.size() > n:
		var node := _ai_card_back_nodes.pop_back() as Card
		if is_instance_valid(node):
			node.queue_free()
	_layout_ai_hand()


# Pops the rightmost card-back from the AI hand visuals and reparents it
# to `_bs.canvas` (preserving world position and scale), so AiCardPlayer can
# fly it freely to the centre of the screen. Returns null if the hand is
# already empty.
func pop_ai_hand_card_node() -> Card:
	if _ai_card_back_nodes.is_empty():
		return null
	var card := _ai_card_back_nodes.pop_back() as Card
	_layout_ai_hand()
	if not is_instance_valid(card):
		return null
	var world_pos: Vector2  = card.global_position
	var world_scale: Vector2 = card.scale
	var parent := card.get_parent()
	if parent != null:
		parent.remove_child(card)
	_bs.canvas.add_child(card)
	card.global_position = world_pos
	card.scale = world_scale
	return card


# Adaptive horizontal fan: target gap between cards is AI_HAND_GAP, but if the
# hand wouldn't fit inside the inner width, spacing compresses uniformly.
# Inner width matches the player hand gutter so the deck/discard counters
# never collide with the AI cards.
func _layout_ai_hand() -> void:
	var n: int = _ai_card_back_nodes.size()
	if n == 0:
		return
	var card_w_scaled: float = Card.CARD_W * AI_HAND_SCALE
	var inner_w: float = 1080.0 - 2.0 * _bs.BS_HAND_AREA_MARGIN
	var ideal_total: float = float(n) * card_w_scaled + float(max(n - 1, 0)) * AI_HAND_GAP
	var spacing: float = card_w_scaled + AI_HAND_GAP
	if n > 1 and ideal_total > inner_w:
		spacing = (inner_w - card_w_scaled) / float(n - 1)
	var total_w: float = card_w_scaled + spacing * float(n - 1)
	var start_x: float = (1080.0 - total_w) * 0.5
	for i in n:
		var card := _ai_card_back_nodes[i] as Card
		card.position = Vector2(start_x + spacing * float(i), AI_HAND_TOP_Y)


# ── Turn announcer ───────────────────────────────────────────────────────────
# A horizontal bar that sweeps in from the centre with the message
# "당신의 차례" / "상대 차례", holds briefly, then fades out. Caller awaits
# play_turn_announce(...) so input gating can re-enable on completion.
const TURN_ANNOUNCE_BAR_H        := 110.0
const TURN_ANNOUNCE_IN_DUR       := 0.32
const TURN_ANNOUNCE_HOLD_DUR     := 0.55
const TURN_ANNOUNCE_OUT_DUR      := 0.32
const TURN_ANNOUNCE_PLAYER_COLOR := Color(0.18, 0.45, 0.95, 0.92)
const TURN_ANNOUNCE_ENEMY_COLOR  := Color(0.95, 0.30, 0.25, 0.92)

func _build_turn_announcer() -> void:
	_turn_announce_root = Control.new()
	_turn_announce_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_turn_announce_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_announce_root.visible = false
	_bs.canvas.add_child(_turn_announce_root)


# Plays the centre-screen turn banner. `is_player == true` shows "당신의 차례"
# in blue; false shows "상대 차례" in red. Awaits the full sweep-in / hold /
# fade-out cycle so the caller can use it as a gate.
func play_turn_announce(is_player: bool) -> void:
	if _turn_announce_root == null:
		return
	for child in _turn_announce_root.get_children():
		child.queue_free()
	var bar_color: Color = TURN_ANNOUNCE_PLAYER_COLOR if is_player else TURN_ANNOUNCE_ENEMY_COLOR
	var msg: String      = "당신의 차례" if is_player else "상대 차례"
	var center_y: float = 960.0 - TURN_ANNOUNCE_BAR_H * 0.5  # 1920 / 2

	var bar := ColorRect.new()
	bar.color = bar_color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.position = Vector2(540.0, center_y)
	bar.size     = Vector2(0.0, TURN_ANNOUNCE_BAR_H)
	bar.pivot_offset = Vector2(0.0, TURN_ANNOUNCE_BAR_H * 0.5)
	_turn_announce_root.add_child(bar)

	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_font_size_override("font_size", 56)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.position = Vector2(0.0, center_y)
	lbl.size     = Vector2(1080.0, TURN_ANNOUNCE_BAR_H)
	lbl.modulate = Color(1.0, 1.0, 1.0, 0.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_announce_root.add_child(lbl)

	_turn_announce_root.visible = true

	var tw_in := _bs.create_tween().set_parallel()
	tw_in.tween_property(bar, "size", Vector2(1080.0, TURN_ANNOUNCE_BAR_H),
			TURN_ANNOUNCE_IN_DUR).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw_in.tween_property(bar, "position", Vector2(0.0, center_y),
			TURN_ANNOUNCE_IN_DUR).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw_in.tween_property(lbl, "modulate", Color.WHITE,
			TURN_ANNOUNCE_IN_DUR).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tw_in.finished

	await _bs.get_tree().create_timer(TURN_ANNOUNCE_HOLD_DUR).timeout

	if not is_instance_valid(bar) or not is_instance_valid(lbl):
		_turn_announce_root.visible = false
		return
	var tw_out := _bs.create_tween().set_parallel()
	tw_out.tween_property(bar, "modulate", Color(1.0, 1.0, 1.0, 0.0),
			TURN_ANNOUNCE_OUT_DUR).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw_out.tween_property(lbl, "modulate", Color(1.0, 1.0, 1.0, 0.0),
			TURN_ANNOUNCE_OUT_DUR).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	await tw_out.finished

	_turn_announce_root.visible = false
	for child in _turn_announce_root.get_children():
		child.queue_free()


# 전략 포인트 도넛 두 개를 화면 우측 거터에 배치한다.
#  - player: 핸드 우측 상단 (Discard 카운터 바로 위). 탭하면 뒤집혀 턴 넘기기
#    원형 버튼이 되고, 바깥을 탭하면 다시 도넛으로 돌아온다.
#  - enemy: 화면 우측 상단 (상대 핸드 peek 바로 아래). 표시 전용.
func _build_cost_donuts() -> void:
	var screen_w: float = get_viewport().get_visible_rect().size.x
	var cx: float = screen_w - _bs.BS_HAND_AREA_MARGIN * 0.5

	_bs.cost_donut_enemy = CostDonut.new()
	_bs.cost_donut_enemy.name = "CostDonutEnemy"
	_bs.canvas.add_child(_bs.cost_donut_enemy)
	_bs.cost_donut_enemy.fill_color = DONUT_FILL_ENEMY
	_bs.cost_donut_enemy.interactive = false
	var ai_hand_bottom: float = AI_HAND_TOP_Y + Card.CARD_H * AI_HAND_SCALE
	_bs.cost_donut_enemy.set_center(Vector2(cx,
			ai_hand_bottom + DONUT_AI_HAND_GAP + CostDonut.RADIUS))

	_bs.cost_donut = CostDonut.new()
	_bs.cost_donut.name = "CostDonutPlayer"
	_bs.canvas.add_child(_bs.cost_donut)
	_bs.cost_donut.fill_color = DONUT_FILL_PLAYER
	_bs.cost_donut.interactive = true
	var targeting_btn_band: float = CardTargetingOverlay.BTN_HAND_GAP \
			+ CardTargetingOverlay.BTN_H
	_bs.cost_donut.set_center(Vector2(cx, _bs.BS_HAND_CENTER.y
			- targeting_btn_band - DONUT_HAND_GAP - CostDonut.RADIUS))
	_bs.cost_donut.end_turn_pressed.connect(_bs.card_phase.end_card_phase)


func _build_victory_panel() -> void:
	_bs.panel_victory = Panel.new()
	_bs.panel_victory.position = Vector2(190.0, 760.0)
	_bs.panel_victory.size     = Vector2(700.0, 400.0)
	_bs.panel_victory.visible  = false
	_bs.canvas.add_child(_bs.panel_victory)

	_bs.lbl_victory = Label.new()
	_bs.lbl_victory.add_theme_font_size_override("font_size", 48)
	_bs.lbl_victory.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bs.lbl_victory.position = Vector2(0.0, 80.0)
	_bs.lbl_victory.size     = Vector2(700.0, 80.0)
	_bs.panel_victory.add_child(_bs.lbl_victory)

	# Standalone runs replay the same battle; Season-driven runs return to the
	# campaign hub so LeagueManager can record the result.
	var season_mode: bool = _bs.gm.season_state.get("pending_match", null) != null
	var rb := Button.new()
	rb.text = "다음 →" if season_mode else "Play Again"
	rb.position = Vector2(200.0, 240.0)
	rb.size     = Vector2(300.0, 80.0)
	rb.add_theme_font_size_override("font_size", 32)
	if season_mode:
		rb.pressed.connect(_bs._on_return_to_season_pressed)
	else:
		rb.pressed.connect(_bs._on_restart_pressed)
	_bs.panel_victory.add_child(rb)


# Builds one pilot slot (face portrait + horizontal HP bar + score label).
# Returns a Dictionary of refs used by `_apply_slots`.
func _build_slot(parent: Control, x: float, y: float) -> Dictionary:
	# Tinted background that doubles as a fallback when no face image exists
	# (standalone runs, INTL pilots without art, dead pilot grayscale tint).
	var icon_bg := ColorRect.new()
	icon_bg.position = Vector2(x + PORTRAIT_X, y + PORTRAIT_Y)
	icon_bg.size     = Vector2(PORTRAIT_W, PORTRAIT_H)
	icon_bg.color    = Color(0.3, 0.3, 0.3)
	icon_bg.visible  = false
	parent.add_child(icon_bg)

	# Face portrait — sits on top of icon_bg. Texture is set in _apply_slots
	# from PilotImages.face_for(pilot.pilot_id); when null, falls back to bg.
	var face_rect := TextureRect.new()
	face_rect.position = Vector2(x + PORTRAIT_X, y + PORTRAIT_Y)
	face_rect.size     = Vector2(PORTRAIT_W, PORTRAIT_H)
	face_rect.expand_mode      = TextureRect.EXPAND_IGNORE_SIZE
	face_rect.stretch_mode     = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face_rect.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	face_rect.visible          = false
	parent.add_child(face_rect)

	# Role label — tiny tag overlaid in the bottom-left corner of the portrait
	# so the role is still readable when the face fills the slot.
	var icon_lbl := Label.new()
	icon_lbl.text = ""
	icon_lbl.add_theme_font_size_override("font_size", 14)
	icon_lbl.add_theme_color_override("font_color", Color.WHITE)
	icon_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	icon_lbl.add_theme_constant_override("outline_size", 3)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	icon_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	icon_lbl.position = Vector2(x + PORTRAIT_X + 3.0, y + PORTRAIT_Y)
	icon_lbl.size     = Vector2(PORTRAIT_W - 6.0, PORTRAIT_H - 2.0)
	icon_lbl.visible  = false
	parent.add_child(icon_lbl)

	# Horizontal HP bar — sits directly under the face, full portrait width.
	var bar := ProgressBar.new()
	bar.position        = Vector2(x + HBAR_X, y + HBAR_Y)
	bar.size            = Vector2(HBAR_W, HBAR_H)
	bar.min_value       = 0.0
	bar.max_value       = 100.0
	bar.value           = 0.0
	bar.show_percentage = false
	bar.fill_mode       = ProgressBar.FILL_BEGIN_TO_END
	bar.visible         = false
	parent.add_child(bar)

	# Score below the HP bar — placeholder until scoring system exists.
	var score_lbl := Label.new()
	score_lbl.text = PLACEHOLDER_SCORE
	score_lbl.add_theme_font_size_override("font_size", 14)
	score_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_lbl.position = Vector2(x, y + SCORE_Y)
	score_lbl.size     = Vector2(SLOT_W, SCORE_H)
	score_lbl.visible  = false
	parent.add_child(score_lbl)

	return {
		"bar": bar,
		"icon_bg": icon_bg,
		"face_rect": face_rect,
		"icon_lbl": icon_lbl,
		"score_lbl": score_lbl,
	}


func update_hud() -> void:
	# Battle log is no longer surfaced on screen; `_bs.last_log` is still
	# updated by effect handlers for diagnostics but renders nowhere.
	var in_card_phase := _bs.game_phase == GameEnums.BattlePhase.CARD_PHASE
	_update_cost_donuts(in_card_phase)
	_update_pilot_boards()
	update_time_label()


# The ring is full at PHASE_THRESHOLD; the number in the middle is the raw
# point total, so boost cards read as "8+ on a full ring".
# The player donut only accepts the flip → 턴 넘기기 during 작전 단계.
func _update_cost_donuts(in_card_phase: bool) -> void:
	var maxv: int = _bs.PHASE_THRESHOLD if _bs.PHASE_THRESHOLD > 0 else DONUT_DEFAULT_MAX
	if _bs.cost_donut_enemy != null:
		_bs.cost_donut_enemy.set_value(_bs.ai_cost, maxv)
	if _bs.cost_donut != null:
		_bs.cost_donut.set_value(_bs.player_cost, maxv)
		_bs.cost_donut.set_flip_allowed(in_card_phase)
		_bs.cost_donut.set_end_enabled(in_card_phase
				and _bs.card_phase.can_end_card_phase())


# Smooth in-game timer — driven by turn_count + auto_play_timer fraction.
# Called every frame from BattleSim._process so the seconds tick visibly.
func update_time_label() -> void:
	if _lbl_time == null:
		return
	var sec_total: int = _bs.get_elapsed_ingame_seconds()
	@warning_ignore("integer_division")
	var mm: int = sec_total / 60
	var ss: int = sec_total % 60
	_lbl_time.text = "%02d:%02d" % [mm, ss]


func _update_pilot_boards() -> void:
	var team0: Array = []
	var team1: Array = []
	for p in _bs.pilots:
		var pd := p as PilotData
		if pd.team == 0:
			team0.append(pd)
		else:
			team1.append(pd)
	# Sort by LanePosition (LEFT=0, CENTER=1, RIGHT=2, GUERRILLA=3).
	team0.sort_custom(func(a: PilotData, b: PilotData) -> bool: return a.lane < b.lane)
	team1.sort_custom(func(a: PilotData, b: PilotData) -> bool: return a.lane < b.lane)
	_apply_slots(_player_slots, team0)
	_apply_slots(_enemy_slots,  team1)


func _apply_slots(slots: Array, sorted_pilots: Array) -> void:
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		if i >= sorted_pilots.size():
			slot.bar.visible       = false
			slot.icon_bg.visible   = false
			slot.face_rect.visible = false
			slot.icon_lbl.visible  = false
			slot.score_lbl.visible = false
			continue

		var pd: PilotData = sorted_pilots[i]
		var role_color: Color = ROLE_COLORS[pd.role] if pd.role < ROLE_COLORS.size() \
				else Color(0.5, 0.5, 0.5)

		slot.bar.visible       = true
		slot.icon_bg.visible   = true
		slot.face_rect.visible = true
		slot.icon_lbl.visible  = true
		slot.score_lbl.visible = true
		slot.icon_lbl.text     = _bs.ROLE_NAMES[pd.role] if pd.role < _bs.ROLE_NAMES.size() else "?"
		slot.score_lbl.text    = PLACEHOLDER_SCORE

		var face_rect: TextureRect = slot.face_rect
		face_rect.texture = PilotImages.face_for(pd.pilot_id)

		if pd.alive:
			slot.icon_bg.color = role_color
			face_rect.modulate = Color.WHITE
			slot.bar.value     = float(pd.hp) / float(pd.max_hp) * 100.0
		else:
			# Luminance-based grayscale so the desaturated shape is still visible.
			var lum := role_color.r * 0.299 + role_color.g * 0.587 + role_color.b * 0.114
			slot.icon_bg.color = Color(lum, lum, lum)
			# Desaturate the face so dead pilots are visually distinct.
			face_rect.modulate = Color(0.55, 0.55, 0.55, 1.0)
			slot.bar.value     = 0.0


