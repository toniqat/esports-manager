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
# span ~y=1440..1660 at-rest (CARD_H=220).
#
# y 1440 은 전장 축소(`HexGrid.DISPLAY_SCALE` 1.5 → 1.35)를 따라온 값이다:
# 전장 하단이 1406 → 1351 로 55px 올라갔으므로 핸드도 60px 올려 카드 윗단과
# 전장 아랫단 사이의 ~90px 간격을 그대로 유지한다. 확인/취소 버튼 행, 전략
# 포인트 도넛, Deck / Discard 카운터는 전부 이 값에서 역산하므로 함께 따라온다.
var BS_HAND_CENTER: Vector2 = Vector2(540.0, 1440.0)
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
## 사망 연출 1단계 — 쓰러진 자리에서 딤드된 채 버티는 시간.
const ANIM_DEATH_HOLD_DUR      := 1.0
## 사망 연출 2단계 — 투명해지며 위로 떠오르는 시간.
const ANIM_DEATH_FADE_DUR      := 0.45
## 사망 연출 2단계에서 떠오르는 높이(px).
const ANIM_DEATH_RISE_PX       := 90.0
## 사망 연출 1단계의 딤드 색 배율 (초상 / 링에 함께 곱해진다).
const ANIM_DEATH_TINT          := Color(0.34, 0.34, 0.40, 1.0)
## 포탑 피격 연출 — 흔들림 + 붉은 섬광이 감쇠하며 사라지기까지의 시간(s).
const ANIM_TURRET_HIT_DUR      := 0.26
## 포탑 피격 흔들림의 좌우 진폭(px). 파일럿보다 크게 흔들어 준다 —
## 포탑 스프라이트가 타일만 하기 때문에 6px 로는 눈에 띄지 않는다.
const ANIM_TURRET_HIT_AMP_PX   := 9.0
## 피격 순간 포탑 스프라이트에 곱하는 색. 연출이 끝나면 흰색으로 돌아온다.
const ANIM_TURRET_HIT_TINT     := Color(1.0, 0.42, 0.36, 1.0)

# ─── 공격 카드 돌진 연출 ─────────────────────────────────────────────────────
# 공격 카드(`attack:N`)를 낼 때 시전자 초상이 대상 초상으로 파고들었다가
# 돌아온다. 자세한 배선은 anim_pilot_lunge / pilot_lunge_offset 참조.
## 돌진(1단계) 시간. **거리와 무관하게 고정**이라 먼 대상일수록 빠르게 날아간다 —
## 연출 길이가 전장 위치에 따라 들쭉날쭉하면 연속 공격의 리듬이 무너진다.
const ANIM_LUNGE_IN_DUR    := 0.50
## 복귀(2단계) 시간. 돌진보다 길다 — "천천히 돌아온다"가 이 연출의 후반부다.
const ANIM_LUNGE_OUT_DUR   := 0.62
## 복귀 중 붕 뜨는 높이(px). 궤적 한가운데서 최대가 되는 반주기 사인.
const ANIM_LUNGE_HOP_PX    := 34.0
## 돌진이 끝났을 때 대상 초상과 겹치는 비율(대상 지름 기준). 0.5 = 절반.
## 두 마커 반지름이 같으므로 최종 중심 간 거리는 정확히 마커 반지름 1개분이 된다.
const ANIM_LUNGE_OVERLAP   := 0.5

# ─── 피해 수치 팝업 (공격 카드 전용) ─────────────────────────────────────────
## 팝업이 화면에 머무는 시간(s).
const DMG_POPUP_DUR      := 0.95
## 팝업이 떠오르는 총 높이(px).
const DMG_POPUP_RISE_PX  := 46.0
## 연속 공격처럼 한 번에 여러 번 터질 때 팝업 사이에 주는 시작 지연(s).
const DMG_POPUP_STAGGER  := 0.18

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
## 블루 진영이 개시 시점에 선점하는 전략 포인트. 밴픽에서 후밴/후픽을 하는
## 대가로 인게임 선을 잡게 하는 노브다 (see `blue_team`).
var BLUE_COST_HEAD_START:    int   = 0
var COST_RECOVERY:           int   = 0
var CARD_DRAW_INTERVAL:      int   = 1
var COST_RECOVERY_INTERVAL:  int   = 1
var PHASE_THRESHOLD:         int   = 0
## 카드 경제(전략 점수 회복 + 자동 드로우)가 처음 도는 턴. 그 전 턴들에는
## 회복도 드로우도 없고 **개시 손패도 없다** — 0턴에 들어가는 것은 블루 선점
## (`BLUE_COST_HEAD_START`) 하나뿐이고, 양 팀은 빈 손으로 이 턴까지 순수
## 라인전만 한다. 성장은 이 게이트를 타지 않는다(1턴부터 돈다).
var ECONOMY_START_TURN:      int   = 1
## 턴당 누적 성장률. 살아 있는 파일럿의 `atk` / `max_hp` 가 매 턴 이만큼
## 원본 대비 늘어난다 (0.01 = +1%p/턴). SimulationCore.tick_growth_and_expiries.
var GROWTH_PER_TURN:         float = 0.0

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

# ─── 진영 (블루 / 레드) ───────────────────────────────────────────────────────
# 어느 팀이 블루인가. 0 = 플레이어 팀, 1 = AI 팀. `match_ctx.player_side`
# (GameEnums.DraftSide) 에서 유도되며, MatchFlow 를 거치지 않은 단독 실행에서는
# 플레이어가 블루다.
#
# 블루는 밴픽에서 **후밴 / 후픽**을 하는 대신 인게임에서 두 가지를 가져간다:
#   1. 개시 시점에 전략 포인트를 `BLUE_COST_HEAD_START` 만큼 선점한다.
#   2. 양 팀이 같은 점수로 문턱에 닿았을 때 **먼저 차례를 잡는다**
#      (CardPhaseManager.do_battle_turn 의 우선순위 규칙).
var blue_team: int = 0

# ─── Card cost-modifier state ────────────────────────────────────────────────
# Set by 비용 카드 효과들 (사전 준비 / 전투 준비 / 집중 …) and consumed at
# card-play / card-draw time. The phase-bound pair resets when
# CardPhaseManager.start_card_phase()/end_card_phase() flips back to BATTLE.
# engage_discount_*: one-shot discount applied to the next engage:N card the
#   side plays (전투 준비). Consumed on use.
# phase_cost_inc_*: add-on applied to every card play during the current
#   작전 단계 (cost_inc_phase). Reset on phase entry. **No card in the pool
#   carries that clause right now** — 정밀 이동 used to, but its +1 is now
#   self-only and lands on the card's own cost via return_left:1.
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

# ─── 카드 지연 효과 상태 ─────────────────────────────────────────────────────
# 계획 중시 (`preserve:N`) — 상한 초과 자동 버리기로부터 보호되는 손패 카드들.
# `CardPhaseManager._trim_hand_overflow` 만 이 목록을 본다: 카드 효과에 의한
# **강제** 버리기(재고 / 완벽한 마무리 / 과감한 정리 / 솔로 퍼포먼스)는 보존을
# 무시한다. 보존은 그 팀의 **다음 작전 단계 시작 시** 통째로 해제된다.
var preserved_cards_p:  Array = []   # Array[CardData]
var preserved_cards_ai: Array = []
# 아드레날린 (`strategy_next_phase:N`) — 다음 작전 단계 진입 시 전략 점수에
# 더해질 값(음수 가능). 적용 후 0으로 리셋되며 점수는 0 아래로 내려가지 않는다.
var next_phase_strategy_p:  int = 0
var next_phase_strategy_ai: int = 0
# 계획 살인 (`strategy_on_kill:N`) — **선불 예약형** 현상금. 카드를 낸 시점에
# 심어 두고, `mark_pilot_dead` 가 상대 팀 파일럿의 사망을 볼 때 한 번 지급하고
# 소모한다. 그 작전 단계가 끝나면 미사용분은 사라진다.
var kill_bounty_p:  int = 0
var kill_bounty_ai: int = 0

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
# Deck / Discard 카드 뭉치 — 핸드 행 양옆 거터. 앞으로 누운 카드 뭉치이자
# 장수 카운터이자 목록 열람 버튼(위에 투명 Button 이 얹힌다).
var pile_deck:    CardPileStack = null
var pile_discard: CardPileStack = null

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
# 파일럿 상세 패널 — 하단 아군 스트립의 얼굴을 누르면 열리는 모달. 좌측에 전신
# 아트, 우측에 아웃게임 / 인게임 / 메크 스탯. **자기 작전 단계에서만** 열리며
# 단계를 벗어나면 HudBuilder 가 닫는다. lazy-add in _ready().
var pilot_detail: PilotDetailPanel = null
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
	# 파일럿 상세 패널 — 하단 아군 스트립을 누르면 열린다(작전 단계 한정).
	pilot_detail = PilotDetailPanel.new()
	pilot_detail.name = "PilotDetailPanel"
	add_child(pilot_detail)
	pilot_detail.bind(self)
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


## Reads `match_ctx.player_side` into `blue_team` and seeds both sides' 전략
## 포인트 from it: 블루가 `BLUE_COST_HEAD_START` 만큼 앞선 채로 시작한다.
##
## 선점은 순전히 **선을 잡기 위한** 장치다 — COST_RECOVERY 는 양 팀에 같은
## 틱에 같은 양이 들어가므로, 개시 시점의 차이가 그대로 유지되어 블루가 항상
## 문턱에 먼저 닿는다. 같은 점수로 동시에 닿는 경우(카드로 점수를 쓴 뒤 등)의
## 타이브레이크는 CardPhaseManager 의 차례 우선순위가 따로 책임진다.
##
## MatchFlow 를 거치지 않은 단독 실행에서는 match_ctx 가 비어 있어 플레이어가
## 블루가 된다.
func seed_side_costs() -> void:
	var side: int = GameEnums.DraftSide.BLUE
	if gm != null and bool(gm.match_ctx.get("active", false)):
		side = int(gm.match_ctx.get("player_side", GameEnums.DraftSide.BLUE))
	# player_side 는 "플레이어 팀의 진영"이므로, 플레이어가 BLUE 면 블루 팀은 0.
	blue_team = 0 if side == GameEnums.DraftSide.BLUE else 1
	player_cost = BLUE_COST_HEAD_START if blue_team == 0 else 0
	ai_cost     = BLUE_COST_HEAD_START if blue_team == 1 else 0


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
	MAX_HAND_SIZE           = int(cfg.get("MAX_HAND_SIZE", "10"))
	BLUE_COST_HEAD_START    = int(cfg.get("BLUE_COST_HEAD_START", "1"))
	COST_RECOVERY           = int(cfg.get("COST_RECOVERY", "1"))
	CARD_DRAW_INTERVAL      = max(1, int(cfg.get("CARD_DRAW_INTERVAL", "1")))
	COST_RECOVERY_INTERVAL  = max(1, int(cfg.get("COST_RECOVERY_INTERVAL", "1")))
	PHASE_THRESHOLD         = int(cfg.get("PHASE_THRESHOLD", "8"))
	ECONOMY_START_TURN      = max(1, int(cfg.get("ECONOMY_START_TURN", "1")))
	GROWTH_PER_TURN         = float(cfg.get("GROWTH_PER_TURN", "0.0"))
	# Init counters so first event fires on turn 1
	draw_counter = CARD_DRAW_INTERVAL - 1
	cost_counter = COST_RECOVERY_INTERVAL - 1
	seed_side_costs()

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
	var pilot_anim: bool = _advance_pilot_animations(delta)
	var turret_anim: bool = _advance_turret_animations(delta)
	if pilot_anim or turret_anim:
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
##
## `killer` 는 **성장치 정산 전용**이다. 계획 살인 현상금은 예나 지금이나
## "쓰러진 파일럿의 반대 팀"으로 충분하지만(전장에 제3세력이 없다), 성장치는
## 개인 지표라 실제로 마지막 타격을 넣은 파일럿을 알아야 한다. 모르면 null 을
## 넘긴다 — 포탑 처치가 그런 경우다.
func mark_pilot_dead(p: PilotData, killer: PilotData = null) -> void:
	p.hp            = 0
	p.alive         = false
	p.recall_hold   = false   # 복귀 대기 중 죽으면 대기도 함께 사라진다
	p.shield        = 0
	p.respawn_timer = respawn_turns_now()
	anim_pilot_death(p)
	_award_kill_bounty(p.team)
	add_score(p, SCORE_DEATH)
	if killer != null:
		add_score(killer, SCORE_KILL)


## 계획 살인의 지급 지점. 전장에는 제3세력이 없으므로 "누가 죽였는가"를 따로
## 넘겨받을 필요가 없다 — 쓰러진 파일럿의 **반대 팀**이 처치자다. 예약해 둔
## 현상금이 있으면 한 번 지급하고 곧바로 소모한다(카드 한 장 = 처치 한 번).
func _award_kill_bounty(dead_team: int) -> void:
	if dead_team == 1:
		if kill_bounty_p > 0:
			player_cost += kill_bounty_p
			kill_bounty_p = 0
	elif kill_bounty_ai > 0:
		ai_cost += kill_bounty_ai
		kill_bounty_ai = 0


# ─── 성장치 (파일럿 점수) ────────────────────────────────────────────────────
# 파일럿마다 개시 1.00k 에서 출발해 경기 내내 누적되는 종합 지표. 파일럿
# 스트립의 체력 바 아래에 찍히고, 상단 중앙의 팀 점수는 그 팀 다섯 명의 **합산**
# 이다(개시 5.00k - 5.00k). 상한이 없으므로 게이지가 아니라 숫자로만 보여 준다.
#
# **성장(`PilotData.growth`)과는 다른 것이다.** 성장은 매 턴 `atk`/`max_hp` 를
# 밀어 올리는 스탯 배율이고, 성장치는 전투 기여를 읽는 점수라 스탯에 아무
# 영향을 주지 않는다. 이름이 비슷해 헷갈리기 쉬우니 필드도 `growth` 와
# `score` 로 갈라 두었다.
#
# 적립은 **피해가 굴려지는 그 지점**에서 한다 — 실제로 깎인 양이 아니라 굴린
# 양이다. 오버킬 몇 점이 지표를 흔들지는 않고, 반대로 적용 지점(damage_map
# 소진 루프)에서 잡으려면 공격자를 거기까지 들고 가야 해서 배선이 훨씬 는다.
## 개시값.
const SCORE_START: float = 1.0
## 아무리 죽어도 여기 아래로는 내려가지 않는다.
const SCORE_MIN: float = 0.10
const SCORE_KILL: float = 0.20
const SCORE_DEATH: float = -0.10
## 피해 1 당 적립량 (= 100 당 0.01 / 0.02 / 0.03).
const SCORE_PER_PILOT_DMG: float  = 0.01 / 100.0
const SCORE_PER_TURRET_DMG: float = 0.02 / 100.0
const SCORE_PER_HQ_DMG: float     = 0.03 / 100.0
const SCORE_TURRET_KILL: float = 0.15


## 모든 성장치 변동이 지나는 한 지점. 하한만 지킨다(상한 없음).
func add_score(p: PilotData, delta: float) -> void:
	if p == null or is_zero_approx(delta):
		return
	p.score = maxf(SCORE_MIN, p.score + delta)


func score_pilot_damage(attacker: PilotData, amount: int) -> void:
	if amount > 0:
		add_score(attacker, float(amount) * SCORE_PER_PILOT_DMG)


func score_turret_damage(attacker: PilotData, amount: int) -> void:
	if amount > 0:
		add_score(attacker, float(amount) * SCORE_PER_TURRET_DMG)


func score_hq_damage(attacker: PilotData, amount: int) -> void:
	if amount > 0:
		add_score(attacker, float(amount) * SCORE_PER_HQ_DMG)


func score_turret_kill(attacker: PilotData) -> void:
	add_score(attacker, SCORE_TURRET_KILL)


## 팀 합산 성장치. 상단 중앙 점수표가 읽는다 — 죽어 있는 파일럿도 포함한다
## (점수는 전장에 서 있는지와 무관한 누적 기록이다).
func team_score(team: int) -> float:
	var total: float = 0.0
	for raw in pilots:
		var p := raw as PilotData
		if p.team == team:
			total += p.score
	return total


## 성장치 표기. 1.0 → "1.00k". 소수 둘째 자리까지 — 피해 100 이 0.01k 라
## 한 자리로 자르면 한참을 싸워도 숫자가 안 움직이는 것처럼 보인다.
static func fmt_score(v: float) -> String:
	return "%.2fk" % v


# ─── Pilot animation driver ──────────────────────────────────────────────────
# Returns true if at least one pilot is currently animating.
func _advance_pilot_animations(delta: float) -> bool:
	var any_active := false
	for raw in pilots:
		var p := raw as PilotData
		if p.anim_death_phase != 0:
			p.anim_death_t += delta
			if p.anim_death_t >= p.anim_death_dur:
				if p.anim_death_phase == 1:
					# 딤드 대기 끝 → 투명해지며 상승.
					p.anim_death_phase = 2
					p.anim_death_t     = 0.0
					p.anim_death_dur   = ANIM_DEATH_FADE_DUR
				else:
					p.anim_death_phase = 0
					p.anim_death_t     = 0.0
					p.anim_death_dur   = 0.0
			any_active = true
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
		if p.anim_lunge_phase != 0:
			if p.anim_lunge_t < p.anim_lunge_dur:
				p.anim_lunge_t = minf(p.anim_lunge_t + delta, p.anim_lunge_dur)
				any_active = true
			elif p.anim_lunge_phase == 2:
				# 복귀가 끝나면 스스로 걷는다. **1단계는 시간이 다 차도 꺼지지
				# 않고 대상 앞에 멈춰 선다** — 그 정지 구간이 피해와 쉐이크가
				# 재생되는 자리이고, 2단계는 anim_pilot_lunge_return 이 건다.
				anim_pilot_lunge_clear(p)
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
#
# 복귀는 전장을 비우지 않으므로 두 반쪽이 늘 이어 붙는다 — 저HP / 위치 이탈
# 복귀와 복귀 card 가 같은 연출을 쓴다. (파일럿이 전장에서 사라지는 사유는
# 사망뿐이고, 그건 anim_pilot_death 가 맡는다.)
func anim_pilot_recall(p: PilotData, orig_cell: Vector2i) -> void:
	p.anim_move_dur       = 0.0
	p.anim_move_t         = 0.0
	anim_pilot_lunge_clear(p)
	p.anim_recall_orig    = orig_cell
	p.anim_recall_phase   = 1
	p.anim_recall_t       = 0.0
	p.anim_recall_dur     = ANIM_RECALL_FADE_OUT_DUR


# Respawn: skip phase 1; just fade in + descend at the pilot's HQ cell.
func anim_pilot_respawn(p: PilotData) -> void:
	p.anim_move_dur       = 0.0
	p.anim_move_t         = 0.0
	anim_pilot_lunge_clear(p)
	p.anim_recall_phase   = 2
	p.anim_recall_t       = 0.0
	p.anim_recall_dur     = ANIM_RECALL_FADE_IN_DUR
	# 쓰러진 자리에 남아 있던 시신 연출은 부활과 함께 걷는다.
	anim_pilot_death_clear(p)


# 전사 연출 — 쓰러진 셀에서 ANIM_DEATH_HOLD_DUR 동안 딤드된 채 남아 있다가
# 투명해지며 위로 떠올라 전장에서 사라진다. 로직상 파일럿은 이미 alive == false
# 이므로 이 연출은 순수 UI다: 렌더러가 anim_death_phase 를 보고 계속 그려 준다.
#
# 사망 판정을 내리는 모든 경로(전장 교전 / 전진 카드 / 공격 카드 / 교전 아레나)
# 에서 불러야 한다 — 안 부르면 예전처럼 파일럿이 그 프레임에 툭 사라진다.
func anim_pilot_death(p: PilotData) -> void:
	p.anim_move_dur       = 0.0
	p.anim_move_t         = 0.0
	p.anim_recall_phase   = 0
	# 돌진 중에 쓰러질 수 있다(교전 무대가 아니라 전장에서 반격을 맞는 경우).
	# 시신은 쓰러진 칸에 그대로 남아야 하므로 변위를 걷어 낸다.
	anim_pilot_lunge_clear(p)
	p.anim_death_cell     = p.grid_pos
	p.anim_death_phase    = 1
	p.anim_death_t        = 0.0
	p.anim_death_dur      = ANIM_DEATH_HOLD_DUR


func anim_pilot_death_clear(p: PilotData) -> void:
	p.anim_death_phase = 0
	p.anim_death_t     = 0.0
	p.anim_death_dur   = 0.0


# ─── 공격 카드 돌진 연출 ─────────────────────────────────────────────────────
# 한 번의 타격이 세 박자다: **파고들기 → 타격(정지) → 복귀**. 가운데 박자는
# 여기 없다 — 시전자가 대상 앞에 멈춰 선 채로 호출 측(`CardPhaseManager.
# _effect_attack`)이 피해를 넣고 쉐이크를 걸고 팝업을 띄운다. 그래서 두 함수로
# 갈라져 있고, 둘 다 자기 단계가 끝날 때까지 await 할 수 있는 코루틴이다.
#
# 연속 공격(`repeat`)은 이 세 박자를 타수만큼 반복한다. 다음 카드는 마지막
# 복귀가 끝나야 낼 수 있다(`CardPhaseManager` 의 입력 잠금 참조).

## 1단계 — 시전자를 대상 초상 앞까지 밀어 넣고, 도달할 때까지 기다린다.
## 도달 시점의 겹침은 `ANIM_LUNGE_OVERLAP`, 소요 시간은 거리와 무관하게
## `ANIM_LUNGE_IN_DUR` 고정이다.
func anim_pilot_lunge(attacker: PilotData, target: PilotData) -> void:
	if attacker == null or target == null or attacker == target:
		return
	if not attacker.alive or renderer == null:
		return
	# 그려진 마커끼리 재야 한다 — 마커는 타일 밖(적 위 / 아군 아래)으로 밀려나 있어
	# 타일 중심으로 재면 같은 칸의 적에게 돌진할 때 방향이 아예 반대가 된다.
	var markers: Dictionary = renderer.pilot_marker_positions()
	var from_pos: Vector2 = markers[attacker] as Vector2 if markers.has(attacker) \
			else pilot_marker_pos_solo(attacker)
	var to_pos: Vector2 = markers[target] as Vector2 if markers.has(target) \
			else pilot_marker_pos_solo(target)
	var delta_v: Vector2 = to_pos - from_pos
	var dist: float = delta_v.length()
	# 반지름 1개분을 남기면 두 초상이 대상 지름의 절반만큼 겹친다(둘의 반지름이
	# 같으므로). 이미 그보다 가까우면 파고들 자리가 없으니 제자리에서 때린다.
	var keep: float = renderer.pilot_marker_radius(target) * (2.0 * ANIM_LUNGE_OVERLAP)
	var travel: float = maxf(0.0, dist - keep)
	attacker.anim_lunge_vec   = Vector2.ZERO if dist < 0.01 \
			else (delta_v / dist) * travel
	attacker.anim_lunge_phase = 1
	attacker.anim_lunge_t     = 0.0
	attacker.anim_lunge_dur   = ANIM_LUNGE_IN_DUR
	renderer.queue_redraw()
	await get_tree().create_timer(ANIM_LUNGE_IN_DUR).timeout


## 2단계 — 붕 뜬 채 천천히 원래 자리로. 돌진이 걸려 있지 않으면 즉시 반환하므로
## 시전자가 없거나 이미 정리된 경우에도 호출 측이 분기할 필요가 없다.
func anim_pilot_lunge_return(attacker: PilotData) -> void:
	if attacker == null or attacker.anim_lunge_phase == 0:
		return
	attacker.anim_lunge_phase = 2
	attacker.anim_lunge_t     = 0.0
	attacker.anim_lunge_dur   = ANIM_LUNGE_OUT_DUR
	if renderer != null:
		renderer.queue_redraw()
	await get_tree().create_timer(ANIM_LUNGE_OUT_DUR).timeout


func anim_pilot_lunge_clear(p: PilotData) -> void:
	p.anim_lunge_phase = 0
	p.anim_lunge_t     = 0.0
	p.anim_lunge_dur   = 0.0
	p.anim_lunge_vec   = Vector2.ZERO


## 지금 프레임의 돌진 변위. `BattleRenderer._pilot_anim_offset` 이 다른 오프셋
## 위에 그대로 더한다.
##  • 1단계 — `t²` 로 **서서히 빨라지며** 파고든다. 앞 절반에서 25% 만 가므로
##    짧은 준비 동작 뒤 달려드는 것처럼 읽힌다.
##  • 2단계 — smoothstep 으로 되돌아오며, 궤적 한가운데서 가장 높이 뜬다.
func pilot_lunge_offset(p: PilotData) -> Vector2:
	if p == null or p.anim_lunge_phase == 0 or p.anim_lunge_dur <= 0.0:
		return Vector2.ZERO
	var t: float = clampf(p.anim_lunge_t / p.anim_lunge_dur, 0.0, 1.0)
	if p.anim_lunge_phase == 1:
		return p.anim_lunge_vec * (t * t)
	var back: float = t * t * (3.0 - 2.0 * t)
	return p.anim_lunge_vec * (1.0 - back) \
			+ Vector2(0.0, -ANIM_LUNGE_HOP_PX * sin(PI * t))


# ─── Turret animation driver ─────────────────────────────────────────────────
# 포탑 스프라이트는 렌더러가 그리는 게 아니라 BattleField/BuildingLayer 아래의
# `Building` 노드다. 그래서 피격 연출은 여기서 직접 그 노드의 position/modulate
# 를 흔든다 — 렌더러는 같은 `TurretData.anim_hit_*` 를 읽어 HP 바만 함께 흔든다.
# 파괴는 예전대로 `Building.queue_free()` 라 살아 있는 피격에만 연출이 붙는다.

## Building 노드의 기본 위치(셀 좌표 → 흔들리기 전 position). 연출 도중 다시
## 맞으면 진행 중인 오프셋을 기준으로 삼지 않도록 **처음 한 번만** 채운다.
var _turret_home_pos: Dictionary = {}


## 포탑이 피해를 입었을 때 호출한다 (파괴된 타격은 제외 — 스프라이트가 사라진다).
func anim_turret_hit(td: TurretData) -> void:
	if td == null:
		return
	td.anim_hit_t   = 0.0
	td.anim_hit_dur = ANIM_TURRET_HIT_DUR


# Returns true while at least one turret is still playing its hit reaction.
func _advance_turret_animations(delta: float) -> bool:
	var any_active := false
	for raw in turrets:
		var td := raw as TurretData
		if td == null or td.anim_hit_dur <= 0.0:
			continue
		td.anim_hit_t += delta
		var finished: bool = td.anim_hit_t >= td.anim_hit_dur
		if finished:
			td.anim_hit_t   = 0.0
			td.anim_hit_dur = 0.0
		_apply_turret_hit_visual(td, finished)
		any_active = true
	return any_active


# Pushes the current frame of the hit reaction onto the Building node: a
# decaying horizontal jitter plus a red flash that fades back to white.
func _apply_turret_hit_visual(td: TurretData, finished: bool) -> void:
	if building_registry == null:
		return
	var b: Building = building_registry.get_at(td.grid_pos)
	if b == null:
		return
	if not _turret_home_pos.has(td.grid_pos):
		_turret_home_pos[td.grid_pos] = b.position
	var home: Vector2 = _turret_home_pos[td.grid_pos] as Vector2
	if finished:
		b.position = home
		b.modulate = Color.WHITE
		return
	var t: float = clampf(td.anim_hit_t / td.anim_hit_dur, 0.0, 1.0)
	var decay: float = 1.0 - t
	b.position = home + Vector2(sin(t * TAU * 3.0) * ANIM_TURRET_HIT_AMP_PX * decay, 0.0)
	b.modulate = Color.WHITE.lerp(ANIM_TURRET_HIT_TINT, decay)


## 재시작 — 연출 도중이었던 포탑 스프라이트를 기본 위치 / 흰색으로 되돌린다.
## `turrets` 는 곧바로 비워지므로 남은 연출을 소모해 줄 주체가 사라진다.
func _clear_turret_hit_visuals() -> void:
	for raw in turrets:
		var td := raw as TurretData
		if td == null:
			continue
		td.anim_hit_t   = 0.0
		td.anim_hit_dur = 0.0
		_apply_turret_hit_visual(td, true)


## 포탑 피격 오프셋 — 렌더러가 HP 바를 스프라이트와 같이 흔들 때 읽는다.
func turret_hit_offset(td: TurretData) -> Vector2:
	if td == null or td.anim_hit_dur <= 0.0:
		return Vector2.ZERO
	var t: float = clampf(td.anim_hit_t / td.anim_hit_dur, 0.0, 1.0)
	return Vector2(sin(t * TAU * 3.0) * ANIM_TURRET_HIT_AMP_PX * (1.0 - t), 0.0)

# ─── Public helpers (used by modules) ────────────────────────────────────────
func cell_center(pos: Vector2i) -> Vector2:
	return hex_grid.hex_to_screen(pos.x, pos.y)


func pilot_label(p: PilotData) -> String:
	return "%s%d" % [ROLE_NAMES[p.role], p.team]


## 이 파일럿의 아웃게임 페르소나(`PlayerData`). 없으면 null — 단독 실행이나
## 초상화 없는 INTL 파일럿이 그렇다.
##
## `pilots` 는 스폰 순서가 곧 역할 순서다(0..4 = 팀0, 5..9 = 팀1). match_ctx 의
## 두 로스터도 같은 역할 순서라 인덱스가 그대로 대응한다 — 스폰 이후 배열이
## 재정렬되지 않는다는 것이 이 대응의 전제이므로, `pilots` 를 정렬하고 싶으면
## 사본을 정렬할 것(HudBuilder 가 그렇게 한다).
func player_data_for(p: PilotData) -> PlayerData:
	if p == null or gm == null or not bool(gm.match_ctx.get("active", false)):
		return null
	var idx: int = pilots.find(p)
	if idx < 0:
		return null
	var roster: Array = gm.match_ctx.get(
			"player_roster" if idx < 5 else "enemy_roster", [])
	var slot: int = idx if idx < 5 else idx - 5
	if slot >= roster.size():
		return null
	return roster[slot] as PlayerData


func role_stats_str(role: int) -> String:
	var s: Dictionary = ROLE_STATS[role]
	return "HP:%d ATK:%d" % [s["hp"], s["atk"]]


# Effective cost of a card for the given side, after applying:
#  • phase_cost_inc_* (cost_inc_phase) — additive, can push cost up.
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
	# 진영 선점 포인트를 다시 심는다 — _populate_from_data_loader 가 이미
	# seed_side_costs() 를 돌렸지만, 여기서 0 으로 밀어 버리면 재시작한 판에서만
	# 블루의 선이 사라진다.
	seed_side_costs()
	pending_atk_buff_p = 0; pending_atk_buff_ai = 0
	engage_discount_p = 0; engage_discount_ai = 0
	phase_cost_inc_p = 0; phase_cost_inc_ai = 0
	phase_draw_discount_p = 0; phase_draw_discount_ai = 0
	preserved_cards_p.clear(); preserved_cards_ai.clear()
	next_phase_strategy_p = 0; next_phase_strategy_ai = 0
	kill_bounty_p = 0; kill_bounty_ai = 0
	temp_zone_overrides.clear()
	_clear_turret_hit_visuals()
	if renderer != null:
		renderer.clear_popups()
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
