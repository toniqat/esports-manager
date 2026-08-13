class_name BattleSim
extends Node2D

# ─── Preload ──────────────────────────────────────────────────────────────────
const CARD_SCENE := preload("res://scenes/Card.tscn")

# ─── Constants (UI/rendering — not DB scope) ──────────────────────────────────
# Seconds between auto-tick advances during BATTLE (each tick = 1 minute).
const AUTO_PLAY_INTERVAL := 0.5

# Card phase UI constants (not DB scope)
# Hand layout: fixed-width flat hand, centred on the viewport. The X anchor is
# computed in _ready so the layout follows the actual viewport width. Cards
# span ~y=1500..1720 at-rest (CARD_H=220) — above the cost-bar zone (y=1790+).
var BS_HAND_CENTER: Vector2 = Vector2(540.0, 1500.0)
# Side margin (px) reserved for the Deck / Discard count indicators on the
# left and right of the hand row. Hand width = viewport_w − 2 × this.
const BS_HAND_AREA_MARGIN := 130.0
# Target gap (px) between adjacent cards when the hand fits inside its width.
# Once the natural span exceeds BS_HAND_WIDTH the spacing compresses below
# this — see CardPhaseManager.slot_position().
const BS_HAND_CARD_GAP    := 12.0
# Available inner width of the hand row (set in _ready from viewport size).
var BS_HAND_WIDTH: float  = 902.0
# The hand row is widened past the margin-derived width by this factor so the
# cards overlap each other less. It eats into the Deck / Discard gutters, so
# HudBuilder._build_hand_indicators re-derives its gutter from the real hand
# edge instead of BS_HAND_AREA_MARGIN.
const BS_HAND_WIDTH_SCALE := 1.10
# Minimum distance (px) the card *next to* the hovered card slides away from it.
# The real push is usually larger — it grows with the hand size so a tightly
# packed row still leaves its neighbours clickable — see
# CardPhaseManager._hover_push_amount().
const BS_HAND_HOVER_PUSH  := 28.0
# Sliver (px) of the neighbouring card that must stay uncovered by the
# 1.2x-enlarged hovered card. This is what the push size is solved for.
const BS_HAND_HOVER_MIN_STRIP := 32.0
# Shape of the falloff that carries the push from "full" next to the hovered
# card down to exactly 0 on the outermost card, which is what keeps the hand's
# overall width fixed while the row opens. ramp = 1 − (steps/steps_to_end)^POW,
# so a value > 1 holds the near neighbours near full push and concentrates the
# whole give-way in the outer cards. 1.0 would be a plain linear ramp.
const BS_HAND_HOVER_FALLOFF_POW := 2.0
# Radius (px) of the virtual circle the hand fans along. Every card centre rides
# that circle, whose pivot sits directly below the hand row, so the middle card
# is the highest point and the row curves down toward both ends. Smaller radius
# = deeper curve and stronger card tilt — see CardPhaseManager._fan_angle() /
# _fan_arc_drop(). At the 12-card cap the outermost cards tilt ~6.7° and hang
# ~22px below the middle one.
const BS_HAND_FAN_RADIUS := 3200.0

# ─── Pilot battlefield animation consts (fit within AUTO_PLAY_INTERVAL=0.5s) ─
## Move tween: cell-to-cell ease-out interpolation.
const ANIM_MOVE_DUR            := 0.30
## Damage shake: short horizontal jitter when a pilot takes damage.
const ANIM_SHAKE_DUR           := 0.18
## Recall fade-out at original cell (rise + alpha→0).
const ANIM_RECALL_FADE_OUT_DUR := 0.20
## Recall / respawn fade-in at HQ (descend + alpha→1).
const ANIM_RECALL_FADE_IN_DUR  := 0.25
## How far up the recalling/respawning pilot drifts (px) at peak alpha=0.
const ANIM_RECALL_RISE_PX      := 110.0
## Damage shake horizontal amplitude in px (decays linearly to 0 across the duration).
const ANIM_SHAKE_AMP_PX        := 6.0

# ─── Animation timing & easing consts ─────────────────────────────────────────
## Duration (s) for normal hand relayout (draw, play).
const BS_HAND_SPRING_DURATION  := 0.18
## Duration (s) for the deck↔discard reshuffle count animation.
const BS_RESHUFFLE_TWEEN_DUR   := 0.55
## Ease type used in Card.tween_to for hand animations (int = Tween.EASE_OUT).
const BS_HAND_TWEEN_EASE  : int = 1   # Tween.EASE_OUT
## Trans type used in Card.tween_to for hand animations (int = Tween.TRANS_SPRING).
const BS_HAND_TWEEN_TRANS : int = 10  # Tween.TRANS_SPRING

# ─── DB-driven vars (populated from DataLoader in _ready) ─────────────────────
var GRID_COLS:               int   = 0
var GRID_ROWS:               int   = 0
var HQ_MAX_HP:               int   = 0
var RESPAWN_TURNS:           int   = 0
var TURRET_HP:               int   = 0
var TURRET_ATK:              int   = 0
var RECALL_HP_THRESHOLD:     float = 0.0
## 전장 교전이 **파일럿에게** 넣는 피해에 곱하는 배율. 포탑 / HQ 피해와
## 공격 카드 · 교전 아레나는 이 배율을 타지 않는다.
var BATTLE_PILOT_DMG_MULT:   float = 1.0
var MAX_HAND_SIZE:           int   = 0
var COST_RECOVERY:           int   = 0
var CARD_DRAW_INTERVAL:      int   = 1
var COST_RECOVERY_INTERVAL:  int   = 1
var PHASE_THRESHOLD:         int   = 0

# Derived after DB load
var PLAYER_HQ_POS: Vector2i = Vector2i.ZERO
var ENEMY_HQ_POS:  Vector2i = Vector2i.ZERO

var ROLE_STATS:    Dictionary = {}
var ROLE_NAMES:      Array = []
var ROLE_FULL_NAMES: Array = []
var LANE_NAMES:      Array = []
var LANE_MAX:        Array = []
var LANE_MIDPOINTS:  Array = []
var LANE_PATHS_TEAM0: Array = []
var LANE_PATHS_TEAM1: Array = []
var NEUTRAL_ZONES:    Array = []
var TURRET_POSITIONS: Dictionary = {}

# ─── State ────────────────────────────────────────────────────────────────────
var neutral_zone_cells: Dictionary = {}  # Vector2i → int (-1=gray, 0=team0, 1=team1)
var pilots:  Array               = []
var turrets: Array               = []
var player_hq_hp: int            = 0
var enemy_hq_hp: int             = 0
var turn_count: int              = 0
var game_over: bool              = false
var auto_play_timer: float       = AUTO_PLAY_INTERVAL
var last_log: String             = ""
var game_phase: int              = GameEnums.BattlePhase.GAMBIT
# How many cards the player has resolved during the current CARD_PHASE —
# drives the 턴 넘기기 enable rule (play at least one card before passing).
# Reset on phase entry by CardPhaseManager.start_card_phase().
var cards_played_this_phase: int = 0

# Card phase state
var player_hand:    Array = []
var ai_hand:        Array = []
var player_deck:    Array = []
var ai_deck:        Array = []
var player_discard: Array = []
var ai_discard:     Array = []
var player_cost:    int   = 0
var ai_cost:        int   = 0
var player_card_nodes: Array = []
var pending_atk_buff_p:  int   = 0
var pending_atk_buff_ai: int   = 0
var draw_counter:         int   = 0  # shared draw interval counter
var cost_counter:         int   = 0  # shared cost recovery interval counter

# ─── Card cost-modifier state ────────────────────────────────────────────────
# Set by 비용 카드 효과들 (사전 준비 / 전투 준비 / 집중 / 정밀 이동 …) and
# consumed at card-play / card-draw time. The phase-bound pair resets when
# CardPhaseManager.start_card_phase()/end_card_phase() flips back to BATTLE.
# engage_discount_*: one-shot discount applied to the next engage:N card the
#   side plays (전투 준비). Consumed on use.
# phase_cost_inc_*: add-on applied to every card play during the current
#   작전 단계 (정밀 이동 cost_inc_phase). Reset on phase entry.
# phase_draw_discount_*: discount applied to every card drawn during the
#   current 작전 단계 (집중 cost_reduce_draw_phase). Mutates the drawn
#   CardData.cost directly so the cheaper cost survives even if the draw
#   re-enters the discard pile mid-phase.
var engage_discount_p:        int = 0
var engage_discount_ai:       int = 0
var phase_cost_inc_p:         int = 0
var phase_cost_inc_ai:        int = 0
var phase_draw_discount_p:    int = 0
var phase_draw_discount_ai:   int = 0

# ─── Temporary jungle captures (약탈) ────────────────────────────────────────
# Each entry: {cell: Vector2i, prev_owner: int, expires_turn: int}. SimulationCore
# checks expiries each turn and restores `prev_owner` on the cell when
# `turn_count >= expires_turn`.
var temp_zone_overrides: Array = []

# Gambit state — gambit_lanes is filled by GambitPhaseManager.auto_assign_lanes()
var gambit_lanes: Array   = [-1, -1, -1, -1, -1]

# ─── HUD refs (set by HudBuilder) ────────────────────────────────────────────
var canvas: CanvasLayer
var panel_victory: Panel
var lbl_victory: Label
# 전략 포인트 도넛 게이지. `cost_donut` (player) doubles as the 턴 넘기기
# button once tapped; `cost_donut_enemy` is a readout only.
var cost_donut:       CostDonut = null
var cost_donut_enemy: CostDonut = null
# Deck / Discard count indicators on either side of the hand row.
var lbl_deck_count:    Label = null
var lbl_discard_count: Label = null

# ─── Module refs ─────────────────────────────────────────────────────────────
@onready var gm: Node                       = get_node("/root/GameManager")
@onready var _data_loader: Node              = $DataLoader
@onready var _field_loader: Node             = $FieldLoader
@onready var hex_grid:   HexGrid           = $HexGrid
@onready var sim_core:   SimulationCore    = $SimulationCore
@onready var recall_sys: RecallSystem      = $RecallSystem
@onready var pathfinder: Pathfinding       = $Pathfinding
@onready var renderer:   BattleRenderer    = $BattleRenderer
@onready var card_phase: CardPhaseManager  = $CardPhaseManager
@onready var _gambit:     GambitPhaseManager = $GambitPhaseManager
@onready var hud:               HudBuilder        = $HudBuilder
@onready var building_registry: BuildingRegistry  = $BuildingRegistry
# Modal pick overlay for 버리기:N / 찾기:N card effects. Built lazily in
# _ready() once the HUD canvas exists, since the overlay parents its dim
# rect into _bs.canvas.
var card_select_overlay: CardSelectOverlay = null
# 카드 대상 지정(targeting) 오버레이. 플레이어가 대상 지정 카드를 내면
# CardPhaseManager가 이 오버레이를 띄워 PILOT/LOCATION/PREVIEW 모드에서
# 클릭으로 대상을 고르거나 취소할 수 있게 한다. lazy-add in _ready().
var targeting_overlay: CardTargetingOverlay = null
# Deck / Discard 목록 열람 오버레이 (읽기 전용). 핸드 행 양옆의 카운터를 누르면
# 해당 더미의 카드를 이름순 그리드로 펼쳐 보여 준다. 작전 단계에서만 열린다.
# lazy-add in _ready().
var card_pile_viewer: CardPileViewer = null
# 전투 개시(engage) — 카드의 engage:N 효과가 발동되면 잠시 ENGAGE 페이즈로
# 전환되어 실시간 교전 아레나를 띄운다. 전투가 끝나면 아레나를 연 페이즈로
# 복귀한다(플레이어 카드면 CARD_PHASE, 상대 차례의 AI 카드면 BATTLE).
# 모듈은 _ready()에서 lazy-add.
var engage_phase: EngagePhaseManager = null
# AI가 카드를 사용할 때 화면 중앙에 띄우는 카드 애니메이션 오버레이.
# 상대 차례(CardPhaseManager._run_ai_turn) 안에서 await로 한 장씩 차례대로
# 보여 준다. lazy-add.
var ai_card_player: AiCardPlayer = null
# 전투 행동 로거 — 모든 좌표 변화 / 교전 / 카드 사용을 콘솔 + user:// 파일에
# 남기고, 턴 경계에서 적 파일럿 간 교차(cross-over)를 자동 감지한다.
# `debug/BattleLogger.gd` 참고. lazy-add in _ready() after pilots spawn.
var blog: BattleLogger = null

# ─── TileMapLayer refs (set after BattleField.tscn is added as child) ────────
@onready var tiles_layer:    TileMapLayer = $BattleField/Tiles
@onready var _wp_layer:       Node2D       = $BattleField/WaypointLayer
@onready var _building_layer: Node2D       = $BattleField/BuildingLayer

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_data_loader.data_load_failed.connect(_on_data_load_failed)
	if not _data_loader.load_data():
		return  # error panel shown by signal handler

	# 파일럿 portrait 텍스처를 SceneTree에 사전 등록해 GPU 업로드를 트리거.
	# 이 단계가 없으면 draw_texture_rect가 흰 사각형으로 그려진다.
	PilotImages.prime_into(self)

	# Centre the hand row on the actual viewport width (handles any screen size).
	# Subtract half card width so the pivot point (card centre) lands on screen centre,
	# not the top-left corner which Godot uses for Control global_position.
	var vp_w  := get_viewport().get_visible_rect().size.x
	var vp_cx := vp_w * 0.5
	BS_HAND_CENTER.x = vp_cx - Card.CARD_W * 0.5
	# Inner hand width = total width minus the two side margins reserved for
	# the Deck / Discard count labels, widened by BS_HAND_WIDTH_SCALE.
	BS_HAND_WIDTH = max(Card.CARD_W,
			(vp_w - 2.0 * BS_HAND_AREA_MARGIN) * BS_HAND_WIDTH_SCALE)

	_field_loader.load_field(tiles_layer, _building_layer, _wp_layer)
	var _vp_size := get_viewport().get_visible_rect().size
	var _bf_pos := hex_grid.init_from_tilemap(tiles_layer, _vp_size)
	_bf_pos.y -= 100.0
	$BattleField.position = _bf_pos
	hex_grid.grid_top   -= 100.0  # keep hex_to_screen() aligned with the shifted TileMap
	_populate_from_data_loader()
	player_hq_hp = HQ_MAX_HP
	enemy_hq_hp  = HQ_MAX_HP
	hud.build_ui()
	# Pick overlay must exist before any 버리기 / 찾기 card resolves; it parents
	# its UI into the HUD canvas, so build it after hud.build_ui() and before
	# the card phase can fire.
	card_select_overlay = CardSelectOverlay.new()
	card_select_overlay.name = "CardSelectOverlay"
	add_child(card_select_overlay)
	card_select_overlay.bind(self)
	# Targeting overlay owns the modal pilot/cell pick UI for cards that
	# require a target. Built before engage_phase so engage's preview can
	# hand control off to it.
	targeting_overlay = CardTargetingOverlay.new()
	targeting_overlay.name = "CardTargetingOverlay"
	add_child(targeting_overlay)
	targeting_overlay.bind(self)
	# Deck / Discard 열람 오버레이 — HUD 의 카운터 버튼이 열고 닫는다. 자기
	# CanvasLayer(12) 위에 그리므로 다른 오버레이보다 뒤에 만들어도 상관없다.
	card_pile_viewer = CardPileViewer.new()
	card_pile_viewer.name = "CardPileViewer"
	add_child(card_pile_viewer)
	card_pile_viewer.bind(self)
	# Engage manager owns the turn-based 전투 modal lifecycle.
	engage_phase = EngagePhaseManager.new()
	engage_phase.name = "EngagePhaseManager"
	add_child(engage_phase)
	# AI 카드 사용 애니메이션 오버레이 — end_card_phase 동안 활성.
	ai_card_player = AiCardPlayer.new()
	ai_card_player.name = "AiCardPlayer"
	add_child(ai_card_player)
	ai_card_player.bind(self)
	# Lane assignment is fixed by role; jungle direction comes from MatchFlow
	# (or default LEFT when running BattleSim standalone).
	_gambit.auto_assign_lanes()
	_gambit.launch_battle()
	# Action logger — bound AFTER pilots spawn so its header can dump the roster.
	blog = BattleLogger.new()
	blog.name = "BattleLogger"
	add_child(blog)
	blog.bind(self)
	# Build the per-team deck AFTER pilots spawn — each pilot owns 6 random cards
	# from the pool (시전자 rule) and all 5 stacks shuffle into the team deck.
	card_phase.build_starter_decks()


func _on_data_load_failed(reason: String) -> void:
	push_error("BattleSim: data load failed — " + reason)
	# Build a minimal error overlay directly on the scene root
	var err_canvas := CanvasLayer.new()
	err_canvas.layer = 100
	add_child(err_canvas)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.modulate = Color(0.1, 0.05, 0.05, 0.95)
	err_canvas.add_child(panel)
	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size  = Vector2(900.0, 0.0)
	lbl.text = "Data Load Error\n\n" + reason + \
		"\n\nRun Project → Tools → CSV to DB to regenerate game.db."
	panel.add_child(lbl)
	lbl.set_anchors_preset(Control.PRESET_CENTER)


func _populate_from_data_loader() -> void:
	var cfg: Dictionary = _data_loader.game_cfg

	GRID_COLS               = int(cfg.get("GRID_COLS", "9"))
	GRID_ROWS               = int(cfg.get("GRID_ROWS", "11"))
	HQ_MAX_HP               = int(cfg.get("HQ_MAX_HP", "500"))
	RESPAWN_TURNS           = int(cfg.get("RESPAWN_TURNS", "5"))
	TURRET_HP               = int(cfg.get("TURRET_HP", "150"))
	TURRET_ATK              = int(cfg.get("TURRET_ATK", "8"))
	RECALL_HP_THRESHOLD     = float(cfg.get("RECALL_HP_THRESHOLD", "0.2"))
	BATTLE_PILOT_DMG_MULT   = float(cfg.get("BATTLE_PILOT_DMG_MULT", "0.5"))
	MAX_HAND_SIZE           = int(cfg.get("MAX_HAND_SIZE", "7"))
	COST_RECOVERY           = int(cfg.get("COST_RECOVERY", "1"))
	CARD_DRAW_INTERVAL      = max(1, int(cfg.get("CARD_DRAW_INTERVAL", "1")))
	COST_RECOVERY_INTERVAL  = max(1, int(cfg.get("COST_RECOVERY_INTERVAL", "1")))
	PHASE_THRESHOLD         = int(cfg.get("PHASE_THRESHOLD", "8"))
	# Init counters so first event fires on turn 1
	draw_counter = CARD_DRAW_INTERVAL - 1
	cost_counter = COST_RECOVERY_INTERVAL - 1

	# Pilot stats
	ROLE_STATS      = _data_loader.pilot_stats.duplicate(true)
	ROLE_NAMES      = []
	ROLE_FULL_NAMES = []
	for i in range(_data_loader.pilot_stats.size()):
		var s: Dictionary = _data_loader.pilot_stats[i]
		ROLE_NAMES.append(s.get("abbrev", "?"))
		ROLE_FULL_NAMES.append(s.get("name", "?"))

	# Lane config
	LANE_NAMES     = []
	LANE_MAX       = []
	LANE_MIDPOINTS = []
	for lc in _data_loader.lane_cfg:
		LANE_NAMES.append(lc["name"])
		LANE_MAX.append(lc["max_pilots"])
		LANE_MIDPOINTS.append(Vector2i(lc["mid_col"], lc["mid_row"]))

	# Waypoints (from FieldLoader — TileMapLayer source of truth)
	LANE_PATHS_TEAM0 = _field_loader.waypoints[0].duplicate(true)
	LANE_PATHS_TEAM1 = _field_loader.waypoints[1].duplicate(true)

	# HQ positions (from FieldLoader)
	for hq in _field_loader.hqs:
		if hq["team"] == 0:
			PLAYER_HQ_POS = Vector2i(hq["col"], hq["row"])
		else:
			ENEMY_HQ_POS = Vector2i(hq["col"], hq["row"])

	# Neutral zones (from FieldLoader)
	NEUTRAL_ZONES = _field_loader.neutral_zone_cells.duplicate(true)

	# Turret positions (from FieldLoader)
	TURRET_POSITIONS = _field_loader.turret_pos.duplicate(true)

	# Apply disabled cells and actual cell bounds from FieldLoader to hex grid
	hex_grid.set_disabled_cells(_field_loader.disabled_cells)
	hex_grid.set_grid_bounds(_field_loader.min_cell, _field_loader.max_cell)


func _process(delta: float) -> void:
	# BATTLE auto-ticks every AUTO_PLAY_INTERVAL seconds. CARD_PHASE pauses the
	# tick until the player presses "단계 넘기기"; the AI's own turn runs *inside*
	# BATTLE (CardPhaseManager._run_ai_turn) and holds the tick the same way.
	if not game_over and game_phase == GameEnums.BattlePhase.BATTLE \
			and not _ai_turn_active():
		auto_play_timer -= delta
		if auto_play_timer <= 0.0:
			auto_play_timer = AUTO_PLAY_INTERVAL
			card_phase.do_battle_turn()
	# Tick the on-screen MM:SS clock smoothly every frame (paused when not in BATTLE).
	if hud != null:
		hud.update_time_label()
	# Drive pilot UI animations (move tween, damage shake, recall fade) every
	# frame regardless of phase so animations finish during CARD_PHASE too.
	if _advance_pilot_animations(delta):
		renderer.queue_redraw()


# True while the opponent is taking its 작전 단계. That turn runs inside the
# BATTLE phase (game_phase never changes), so every "is the sim running?" check
# has to consult it on top of game_phase.
func _ai_turn_active() -> bool:
	return card_phase != null and card_phase.is_ai_turn_active()


# Smooth in-game seconds, derived from completed turns + fractional progress
# through the current 0.5s real-time tick. 1 turn = 1 in-game minute = 60 sec.
# Frozen during CARD_PHASE / 상대 차례 / game_over so the clock matches the
# paused sim.
func get_elapsed_ingame_seconds() -> int:
	var base: int = turn_count * 60
	if game_over or game_phase != GameEnums.BattlePhase.BATTLE or _ai_turn_active():
		return base
	var frac: float = clamp(1.0 - auto_play_timer / AUTO_PLAY_INTERVAL, 0.0, 1.0)
	return base + int(frac * 60.0)


# ─── Respawn timing ──────────────────────────────────────────────────────────
## 이번 사망에 걸리는 리스폰 턴 수. 초반 사망은 싸게, 후반 사망은 비싸게 —
## `RESPAWN_TURNS`(기본 5) 에 경과 턴의 1/10 을 더한다. 예전에는 DB 값 하나가
## 전 구간에 그대로 쓰여서(16턴) 개전 직후 한 번 죽으면 초반 라인전이 통째로
## 날아갔다.
##
## **모든 사망 판정은 이 함수를 통과해야 한다** — 전장 교전, 공격 카드, 교전
## 아레나가 각자 `RESPAWN_TURNS` 를 직접 읽으면 스케일링이 한쪽에만 붙는다.
const RESPAWN_TURN_SCALE_DIV: int = 10

func respawn_turns_now() -> int:
	@warning_ignore("integer_division")
	var scaled: int = turn_count / RESPAWN_TURN_SCALE_DIV
	return max(1, RESPAWN_TURNS + scaled)


## 전장 밖 파일럿이 나오기까지 남은 턴 수. 살아 있으면 0.
##
## 파일럿이 전장을 비우는 사유는 **사망뿐**이므로 이 값은 곧 `respawn_timer` 다
## (복귀는 HQ 에 선 채로 처리되어 `alive` 를 건드리지 않는다). UI(카드 잠금
## 표시)와 로그는 타이머를 직접 읽지 말고 이 함수를 거친다 — 돌아오기 직전
## 틱에도 최소 1 을 돌려줘서 카드가 깜빡이며 풀리지 않게 한다.
func turns_until_return(p: PilotData) -> int:
	if p == null or p.alive:
		return 0
	return maxi(1, p.respawn_timer)


## The one place a pilot dies. Zeroes HP, takes them off the field, stamps the
## scaled respawn timer and starts the 전사 연출. Every damage source funnels
## through here so the respawn scaling and the death animation can never be
## wired into one path and forgotten in another.
func mark_pilot_dead(p: PilotData) -> void:
	p.hp            = 0
	p.alive         = false
	p.recall_hold   = false   # 복귀 대기 중 죽으면 대기도 함께 사라진다
	p.shield        = 0
	p.respawn_timer = respawn_turns_now()
	anim_pilot_death(p)


# ─── Pilot animation driver ──────────────────────────────────────────────────
# Returns true if at least one pilot is currently animating.
func _advance_pilot_animations(delta: float) -> bool:
	var any_active := false
	for raw in pilots:
		var p := raw as PilotData
		if p.anim_move_dur > 0.0:
			p.anim_move_t += delta
			if p.anim_move_t >= p.anim_move_dur:
				p.anim_move_dur = 0.0
				p.anim_move_t   = 0.0
			any_active = true
		if p.anim_shake_dur > 0.0:
			p.anim_shake_t += delta
			if p.anim_shake_t >= p.anim_shake_dur:
				p.anim_shake_dur = 0.0
				p.anim_shake_t   = 0.0
			any_active = true
		if p.anim_recall_phase != 0:
			p.anim_recall_t += delta
			if p.anim_recall_t >= p.anim_recall_dur:
				if p.anim_recall_phase == 1:
					# Phase 1 done → start fade-in at HQ.
					p.anim_recall_phase = 2
					p.anim_recall_t     = 0.0
					p.anim_recall_dur   = ANIM_RECALL_FADE_IN_DUR
				else:
					p.anim_recall_phase = 0
					p.anim_recall_t     = 0.0
					p.anim_recall_dur   = 0.0
			any_active = true
	return any_active


# Triggered by SimulationCore when a pilot moves cell. `from_cell` is the cell
# the pilot was on before the move. The visual interpolates from from_cell to
# the pilot's current grid_pos.
func anim_pilot_move(p: PilotData, from_cell: Vector2i) -> void:
	# Skip if same cell or pilot is mid-recall (recall takes priority).
	if from_cell == p.grid_pos or p.anim_recall_phase != 0:
		return
	p.anim_prev_grid_pos = from_cell
	p.anim_move_t   = 0.0
	p.anim_move_dur = ANIM_MOVE_DUR


func anim_pilot_shake(p: PilotData) -> void:
	p.anim_shake_t   = 0.0
	p.anim_shake_dur = ANIM_SHAKE_DUR


# Recall sequence: fade out + rise at orig_cell, then fade in + descend at HQ.
func anim_pilot_recall(p: PilotData, orig_cell: Vector2i) -> void:
	p.anim_move_dur     = 0.0
	p.anim_move_t       = 0.0
	p.anim_recall_orig  = orig_cell
	p.anim_recall_phase = 1
	p.anim_recall_t     = 0.0
	p.anim_recall_dur   = ANIM_RECALL_FADE_OUT_DUR


# Respawn: skip phase 1; just fade in + descend at the pilot's HQ cell.
func anim_pilot_respawn(p: PilotData) -> void:
	p.anim_move_dur     = 0.0
	p.anim_move_t       = 0.0
	p.anim_recall_phase = 2
	p.anim_recall_t     = 0.0
	p.anim_recall_dur   = ANIM_RECALL_FADE_IN_DUR

# ─── Public helpers (used by modules) ────────────────────────────────────────
func cell_center(pos: Vector2i) -> Vector2:
	return hex_grid.hex_to_screen(pos.x, pos.y)


func pilot_label(p: PilotData) -> String:
	return "%s%d" % [ROLE_NAMES[p.role], p.team]


func role_stats_str(role: int) -> String:
	var s: Dictionary = ROLE_STATS[role]
	return "HP:%d ATK:%d" % [s["hp"], s["atk"]]


# Effective cost of a card for the given side, after applying:
#  • phase_cost_inc_* (정밀 이동) — additive, can push cost up.
#  • engage_discount_* (전투 준비) — applied only if the card carries an
#    engage clause (engage:N). Does NOT consume the discount; consumption
#    happens in CardPhaseManager._play_card_direct after the cost is paid.
# Clamped to 0 from below.
func effective_cost_for(cd: CardData, is_player: bool) -> int:
	if cd == null:
		return 0
	var inc: int = phase_cost_inc_p if is_player else phase_cost_inc_ai
	var c: int = cd.cost + inc
	var disc: int = engage_discount_p if is_player else engage_discount_ai
	if disc > 0 and card_phase != null and card_phase.card_has_engage(cd):
		c = max(0, c - disc)
	return max(0, c)


# Drawn-position of a pilot marker assuming it sits solo on its tile. Used by
# CardTargetingOverlay's PILOT-mode hit test so the click lands on the visible
# marker (which is offset above/below the tile centre by team) rather than
# the tile centre. When a cell hosts multiple pilots BattleRenderer further
# spreads them, but the close-row centre still falls inside the click radius.
func pilot_marker_pos_solo(p: PilotData) -> Vector2:
	var center := cell_center(p.grid_pos)
	# Mirror BattleRenderer's enemy-up / ally-down convention — a lone pilot is
	# drawn on that same close-row offset, never at the tile centre.
	var dir: float = -1.0 if p.team == 1 else 1.0
	var hex_h: float = hex_grid.hex_height
	var radius: float = 31.5 * HexGrid.DISPLAY_SCALE  # PILOT_RADIUS_BASE
	var close_off: float = hex_h * 0.45 + radius * 0.4
	return Vector2(center.x, center.y + dir * close_off)

# ─── Button callbacks ─────────────────────────────────────────────────────────
# Season-mode return: the win panel "다음 →" button hands control back to the
# campaign hub. SeasonHub._ready() picks up season_state.pending_match.winner_side
# and applies the result to standings.
func _on_return_to_season_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Season.tscn")


func _on_restart_pressed() -> void:
	_populate_from_data_loader()
	player_hq_hp = HQ_MAX_HP; enemy_hq_hp = HQ_MAX_HP
	turn_count = 0; game_over = false
	last_log = ""; auto_play_timer = AUTO_PLAY_INTERVAL
	game_phase    = GameEnums.BattlePhase.GAMBIT
	gambit_lanes = [-1, -1, -1, -1, -1]
	panel_victory.visible = false
	pilots.clear()
	turrets.clear()
	player_hand.clear();    ai_hand.clear()
	player_discard.clear(); ai_discard.clear()
	player_cost = 0;        ai_cost = 0
	pending_atk_buff_p = 0; pending_atk_buff_ai = 0
	cards_played_this_phase = 0
	engage_discount_p = 0; engage_discount_ai = 0
	phase_cost_inc_p = 0; phase_cost_inc_ai = 0
	phase_draw_discount_p = 0; phase_draw_discount_ai = 0
	temp_zone_overrides.clear()
	for node in player_card_nodes:
		if is_instance_valid(node):
			node.queue_free()
	player_card_nodes.clear()
	# Clear AI hand visuals; HudBuilder reflows from the now-empty ai_hand.
	if hud != null:
		hud.update_ai_hand_visuals()
	_gambit.auto_assign_lanes()
	_gambit.launch_battle()
	card_phase.build_starter_decks()
