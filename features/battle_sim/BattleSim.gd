class_name BattleSim
extends Node2D

# ─── Preload ──────────────────────────────────────────────────────────────────
const CARD_SCENE := preload("res://scenes/Card.tscn")

# ─── Constants ────────────────────────────────────────────────────────────────
const GRID_COLS          := 9
const GRID_ROWS          := 15
const CELL_SIZE          := 100
const GRID_ORIGIN        := Vector2(90.0, 130.0)
const PLAYER_HQ_POS      := Vector2i(4, 14)
const ENEMY_HQ_POS       := Vector2i(4, 0)
const HQ_MAX_HP          := 500
const RESPAWN_TURNS      := 10
const AUTO_PLAY_INTERVAL := 0.5
const TURRET_HP          := 150
const TURRET_ATK         := 8
const RECALL_HP_THRESHOLD  := 0.2
const RECALL_CHANNEL_TURNS := 3
const MINION_SPAWN_COUNT    := 30
const MINION_SPAWN_INTERVAL := 3
const MINION_SIEGE_ATK_DIVISOR := 10

# Card phase
const MAX_HAND_SIZE    := 7
const COST_RECOVERY    := 1
const PHASE_THRESHOLD  := 8
const BS_HAND_CENTER    := Vector2(540.0, 1750.0)
const BS_AI_HAND_CENTER := Vector2(540.0, 200.0)
const BS_FAN_RADIUS     := 900.0
const BS_FAN_HALF_DEG   := 24.0
const BS_FAN_CARD_DEG   := 5.0
const BS_SELECTED_POS   := Vector2(540.0, 1480.0)
const BS_SELECTED_SCALE := Vector2(1.4, 1.4)

const ROLE_NAMES:      Array = ["T", "F", "A", "Su", "Sn"]
const ROLE_FULL_NAMES: Array = ["Tank", "Fighter", "Assassin", "Support", "Sniper"]
const LANE_NAMES:      Array = ["Left", "Center", "Right", "Guerrilla"]
const LANE_MAX:        Array = [2, 2, 2, 1]

const ROLE_STATS: Dictionary = {
	0: { "hp": 200, "atk": 8  },
	1: { "hp": 120, "atk": 15 },
	2: { "hp": 80,  "atk": 25 },
	3: { "hp": 100, "atk": 10, "heal": 5 },
	4: { "hp": 70,  "atk": 20 },
}

const LANE_COLS:      Array = [ [0, 1, 2], [3, 4, 5], [6, 7, 8] ]
const LANE_MIDPOINTS: Array = [ Vector2i(1, 7), Vector2i(4, 7), Vector2i(7, 7) ]

# Neutral Zones (CODE coordinates: 0,0 = top-left)
const NEUTRAL_ZONE_FRIENDLY_LEFT: Array = [
	Vector2i(2,11), Vector2i(3,11), Vector2i(2,10), Vector2i(3,10),
	Vector2i(2,9),  Vector2i(3,9),  Vector2i(2,8),  Vector2i(3,8),
]
const NEUTRAL_ZONE_FRIENDLY_RIGHT: Array = [
	Vector2i(6,11), Vector2i(5,11), Vector2i(6,10), Vector2i(5,10),
	Vector2i(6,9),  Vector2i(5,9),  Vector2i(6,8),  Vector2i(5,8),
]
const NEUTRAL_ZONE_ENEMY_LEFT: Array = [
	Vector2i(2,3), Vector2i(3,3), Vector2i(2,4), Vector2i(3,4),
	Vector2i(2,5), Vector2i(3,5), Vector2i(2,6), Vector2i(3,6),
]
const NEUTRAL_ZONE_ENEMY_RIGHT: Array = [
	Vector2i(5,3), Vector2i(6,3), Vector2i(5,4), Vector2i(6,4),
	Vector2i(5,5), Vector2i(6,5), Vector2i(5,6), Vector2i(6,6),
]

const TURRET_COLS_T1: Array = [1, 4, 7]
const TURRET_COLS_T2: Array = [1, 4, 7]
const TURRET_ROW_T1_TEAM1 := 6
const TURRET_ROW_T2_TEAM1 := 3
const TURRET_ROW_T1_TEAM0 := 8
const TURRET_ROW_T2_TEAM0 := 11

const LANE_PATHS_TEAM0: Array = [
	[Vector2i(4,14), Vector2i(1,11), Vector2i(1,8), Vector2i(1,7), Vector2i(1,6), Vector2i(1,3), Vector2i(4,0)],
	[Vector2i(4,14), Vector2i(4,11), Vector2i(4,8), Vector2i(4,7), Vector2i(4,6), Vector2i(4,3), Vector2i(4,0)],
	[Vector2i(4,14), Vector2i(7,11), Vector2i(7,8), Vector2i(7,7), Vector2i(7,6), Vector2i(7,3), Vector2i(4,0)],
]
const LANE_PATHS_TEAM1: Array = [
	[Vector2i(4,0), Vector2i(1,3), Vector2i(1,6), Vector2i(1,7), Vector2i(1,8), Vector2i(1,11), Vector2i(4,14)],
	[Vector2i(4,0), Vector2i(4,3), Vector2i(4,6), Vector2i(4,7), Vector2i(4,8), Vector2i(4,11), Vector2i(4,14)],
	[Vector2i(4,0), Vector2i(7,3), Vector2i(7,6), Vector2i(7,7), Vector2i(7,8), Vector2i(7,11), Vector2i(4,14)],
]

# ─── State ────────────────────────────────────────────────────────────────────
var ownership_map: Array[int]    = []
var _neutral_zone_cells: Dictionary = {}  # Vector2i → int (-1=gray, 0=team0, 1=team1)
var pilots:  Array               = []
var turrets: Array               = []
var player_hq_hp: int            = HQ_MAX_HP
var enemy_hq_hp: int             = HQ_MAX_HP
var turn_count: int              = 0
var game_over: bool              = false
@export var auto_play: bool      = false
var auto_play_timer: float       = 0.0
var last_log: String             = ""
var game_phase: int              = GameEnums.BattlePhase.GAMBIT
var _minions: Array              = []

# Card phase state
var _player_hand:    Array = []
var _ai_hand:        Array = []
var _player_deck:    Array = []
var _ai_deck:        Array = []
var _player_discard: Array = []
var _ai_discard:     Array = []
var _player_cost:    int   = 0
var _ai_cost:        int   = 0
var _player_card_nodes: Array = []
var _ai_card_nodes:     Array = []
var _selected_card              = null
var _pending_atk_buff_p:  int   = 0
var _pending_atk_buff_ai: int   = 0

# Gambit state
var _gambit_selected: int  = -1
var _gambit_lanes: Array   = [-1, -1, -1, -1, -1]
var _recall_pulse_t: float = 0.0

# ─── HUD refs (set by HudBuilder / GambitPhaseManager) ───────────────────────
var _canvas: CanvasLayer
var _lbl_enemy_hq: Label
var _lbl_player_hq: Label
var _lbl_turn: Label
var _lbl_log: Label
var _btn_next: Button
var _btn_auto: Button
var _panel_victory: Panel
var _lbl_victory: Label
var _panel_gambit: Panel
var _gambit_pilot_btns: Array  = []
var _gambit_slot_labels: Array = []
var _btn_launch: Button
var _lbl_gambit_status: Label
var _lbl_cost_bs: Label        = null
var _btn_end_card_phase: Button = null

# ─── Module refs ─────────────────────────────────────────────────────────────
@onready var _sim_core:   SimulationCore     = $SimulationCore
@onready var _minion_sys: MinionSystem       = $MinionSystem
@onready var _recall_sys: RecallSystem       = $RecallSystem
@onready var _pathfinder: Pathfinding        = $Pathfinding
@onready var _renderer:   BattleRenderer     = $BattleRenderer
@onready var _card_phase: CardPhaseManager   = $CardPhaseManager
@onready var _gambit:     GambitPhaseManager = $GambitPhaseManager
@onready var _hud:        HudBuilder         = $HudBuilder
@onready var _gm: Node                       = get_node("/root/GameManager")

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_hud.build_ui()
	_gambit.build_gambit_ui()
	_card_phase.build_starter_decks()
	_gambit_lanes = [-1, -1, -1, -1, -1]
	_sim_core.init_ownership_map()
	_gambit.refresh_gambit_ui()
	_panel_gambit.visible = true
	_renderer.queue_redraw()
	_hud.update_hud()


func _unhandled_key_input(event: InputEvent) -> void:
	if game_phase != GameEnums.BattlePhase.BATTLE:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				if not game_over:
					_card_phase.do_battle_turn()
			KEY_A:
				_on_auto_play_pressed()


func _process(delta: float) -> void:
	if auto_play and not game_over and game_phase == GameEnums.BattlePhase.BATTLE:
		auto_play_timer -= delta
		if auto_play_timer <= 0.0:
			auto_play_timer = AUTO_PLAY_INTERVAL
			_card_phase.do_battle_turn()
	if game_phase != GameEnums.BattlePhase.GAMBIT and not game_over:
		_recall_pulse_t = fmod(_recall_pulse_t + delta * 1.5, 1.0)
		var any_recall := pilots.any(
				func(r) -> bool: return (r as PilotData).alive and \
						(r as PilotData).recall_state != GameEnums.RecallState.NONE)
		if any_recall:
			_renderer.queue_redraw()

# ─── Public helpers (used by modules) ────────────────────────────────────────
func cell_center(pos: Vector2i) -> Vector2:
	return GRID_ORIGIN + Vector2(pos.x * CELL_SIZE + CELL_SIZE * 0.5, pos.y * CELL_SIZE + CELL_SIZE * 0.5)


func cell_rect(pos: Vector2i) -> Rect2:
	return Rect2(GRID_ORIGIN + Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE),
			Vector2(CELL_SIZE, CELL_SIZE))


func pilot_label(p: PilotData) -> String:
	return "%s%d" % [ROLE_NAMES[p.role], p.team]


func role_stats_str(role: int) -> String:
	var s: Dictionary = ROLE_STATS[role]
	return "HP:%d ATK:%d" % [s["hp"], s["atk"]]

# ─── Button callbacks ─────────────────────────────────────────────────────────
func _on_next_turn_pressed() -> void:
	if not game_over and game_phase == GameEnums.BattlePhase.BATTLE:
		_card_phase.do_battle_turn()


func _on_auto_play_pressed() -> void:
	auto_play = not auto_play
	_btn_auto.text = "⏸ Pause" if auto_play else "Auto Play ▶"
	if auto_play:
		auto_play_timer = AUTO_PLAY_INTERVAL


func _on_restart_pressed() -> void:
	player_hq_hp = HQ_MAX_HP; enemy_hq_hp = HQ_MAX_HP
	turn_count = 0; game_over = false; auto_play = false
	last_log = ""; auto_play_timer = 0.0
	game_phase       = GameEnums.BattlePhase.GAMBIT
	_gambit_selected = -1
	_gambit_lanes    = [-1, -1, -1, -1, -1]
	_btn_auto.text   = "Auto Play ▶"
	_panel_victory.visible = false
	pilots.clear()
	turrets.clear()
	_minions.clear()
	_sim_core.init_ownership_map()
	_player_hand.clear();    _ai_hand.clear()
	_player_discard.clear(); _ai_discard.clear()
	_player_cost = 0;        _ai_cost = 0
	_pending_atk_buff_p = 0; _pending_atk_buff_ai = 0
	for node in _player_card_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_player_card_nodes.clear()
	for node in _ai_card_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_ai_card_nodes.clear()
	_selected_card = null
	_card_phase.build_starter_decks()
	_gambit.refresh_gambit_ui()
	_lbl_gambit_status.text = "Click a pilot to select, then click a lane to assign."
	_panel_gambit.visible   = true
	_renderer.queue_redraw()
	_hud.update_hud()
