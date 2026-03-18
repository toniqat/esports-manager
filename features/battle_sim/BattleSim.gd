class_name BattleSim
extends Node2D

# ─── Preload ──────────────────────────────────────────────────────────────────
const CARD_SCENE := preload("res://scenes/Card.tscn")

# ─── Constants (UI/rendering — not DB scope) ──────────────────────────────────
const AUTO_PLAY_INTERVAL := 0.5

# Card phase UI constants (not DB scope)
# Hand centers X is computed dynamically from viewport in _ready.
var BS_HAND_CENTER:    Vector2 = Vector2(540.0, 1750.0)
var BS_AI_HAND_CENTER: Vector2 = Vector2(540.0, 200.0)
const BS_FAN_RADIUS   := 1400.0
const BS_FAN_HALF_DEG := 36.0
const BS_FAN_CARD_DEG := 5.5
# Y threshold: drop above this line = "played on field"; below = return to hand.
const BS_HAND_ZONE_Y  := 1500.0

# ─── Hover & hand-layout consts (easy-tweak values for CardPhaseManager) ──────
## Pixels a hovered card lifts upward. Applied from a FIXED baseline Y so every
## card reaches the same screen height regardless of its arc position.
const BS_HOVER_LIFT            := 150.0
## Pixels the immediate neighbours of the hovered card shift away from it.
const PRIMARY_HOVER_SPACING    := 180.0
## All other non-hovered cards shift by PRIMARY_HOVER_SPACING × this ratio.
const SECONDARY_SPACING_RATIO  := 0.8

# ─── Animation timing & easing consts ─────────────────────────────────────────
## Duration (s) for normal hand relayout (draw, play, unhover).
const BS_HAND_SPRING_DURATION  := 0.15
## Duration (s) for the hover-expand animation (slightly snappier).
const BS_HOVER_SPRING_DURATION := 0.12
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
var RECALL_CHANNEL_TURNS:    int   = 0
var MINION_SPAWN_COUNT:      int   = 0
var MINION_SPAWN_INTERVAL:   int   = 0
var MINION_SIEGE_ATK_DIVISOR: int  = 0
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
@export var auto_play: bool      = false
var auto_play_timer: float       = 0.0
var last_log: String             = ""
var game_phase: int              = GameEnums.BattlePhase.GAMBIT
var _minions: Array              = []

# Card phase state
var _player_hand:    Array = []
var _ai_hand:        Array = []
var player_deck:    Array = []
var ai_deck:        Array = []
var _player_discard: Array = []
var _ai_discard:     Array = []
var _player_cost:    int   = 0
var _ai_cost:        int   = 0
var _player_card_nodes: Array = []
var _ai_card_nodes:     Array = []
var _pending_atk_buff_p:  int   = 0
var _pending_atk_buff_ai: int   = 0
var _draw_counter:         int   = 0  # shared draw interval counter
var _cost_counter:         int   = 0  # shared cost recovery interval counter

# Gambit state
var _gambit_selected: int  = -1
var _gambit_lanes: Array   = [-1, -1, -1, -1, -1]
var _recall_pulse_t: float = 0.0

# ─── HUD refs (set by HudBuilder / GambitPhaseManager) ───────────────────────
var canvas: CanvasLayer
var lbl_enemy_hq: Label
var lbl_player_hq: Label
var lbl_turn: Label
var lbl_log: Label
var btn_next: Button
var _btn_auto: Button
var _panel_victory: Panel
var lbl_victory: Label
var _panel_gambit: Panel
var gambit_pilot_btns: Array  = []
var gambit_slot_labels: Array = []
var btn_launch: Button
var _lbl_gambit_status: Label
var lbl_cost_bs: Label        = null
var btn_end_card_phase: Button = null

# ─── Module refs ─────────────────────────────────────────────────────────────
@onready var gm: Node                       = get_node("/root/GameManager")
@onready var _data_loader: Node              = $DataLoader
@onready var _field_loader: Node             = $FieldLoader
@onready var _hex_grid:   HexGrid           = $HexGrid
@onready var sim_core:   SimulationCore    = $SimulationCore
@onready var minion_sys: MinionSystem      = $MinionSystem
@onready var recall_sys: RecallSystem      = $RecallSystem
@onready var pathfinder: Pathfinding       = $Pathfinding
@onready var _renderer:   BattleRenderer    = $BattleRenderer
@onready var _card_phase: CardPhaseManager  = $CardPhaseManager
@onready var _gambit:     GambitPhaseManager = $GambitPhaseManager
@onready var _hud:               HudBuilder        = $HudBuilder
@onready var building_registry: BuildingRegistry  = $BuildingRegistry

# ─── TileMapLayer refs (set after BattleField.tscn is added as child) ────────
@onready var _tiles_layer:    TileMapLayer = $BattleField/Tiles
@onready var _wp_layer:       Node2D       = $BattleField/WaypointLayer
@onready var _building_layer: Node2D       = $BattleField/BuildingLayer

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_data_loader.data_load_failed.connect(_on_data_load_failed)
	if not _data_loader.load_data():
		return  # error panel shown by signal handler

	# Centre hand arcs on the actual viewport width (handles any screen size).
	# Subtract half card width so the pivot point (card centre) lands on screen centre,
	# not the top-left corner which Godot uses for Control global_position.
	var vp_cx := get_viewport().get_visible_rect().size.x * 0.5
	BS_HAND_CENTER.x    = vp_cx - Card.CARD_W * 0.5
	BS_AI_HAND_CENTER.x = vp_cx - Card.CARD_W * 0.5

	_field_loader.load_field(_tiles_layer, _building_layer, _wp_layer)
	var _vp_size := get_viewport().get_visible_rect().size
	$BattleField.position = _hex_grid.init_from_tilemap(_tiles_layer, _vp_size)
	_populate_from_data_loader()
	player_hq_hp = HQ_MAX_HP
	enemy_hq_hp  = HQ_MAX_HP
	_hud.build_ui()
	_gambit.build_gambit_ui()
	_card_phase.build_starter_decks()
	_gambit_lanes = [-1, -1, -1, -1, -1]
	_gambit.refresh_gambit_ui()
	_panel_gambit.visible = true
	_renderer.queue_redraw()
	_hud.update_hud()


func _on_data_load_failed(reason: String) -> void:
	push_error("BattleSim: data load failed — " + reason)
	# Build a minimal error overlay directly on the scene root
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.modulate = Color(0.1, 0.05, 0.05, 0.95)
	canvas.add_child(panel)
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
	RESPAWN_TURNS           = int(cfg.get("RESPAWN_TURNS", "10"))
	TURRET_HP               = int(cfg.get("TURRET_HP", "150"))
	TURRET_ATK              = int(cfg.get("TURRET_ATK", "8"))
	RECALL_HP_THRESHOLD     = float(cfg.get("RECALL_HP_THRESHOLD", "0.2"))
	RECALL_CHANNEL_TURNS    = int(cfg.get("RECALL_CHANNEL_TURNS", "3"))
	MINION_SPAWN_COUNT      = int(cfg.get("MINION_SPAWN_COUNT", "30"))
	MINION_SPAWN_INTERVAL   = int(cfg.get("MINION_SPAWN_INTERVAL", "3"))
	MINION_SIEGE_ATK_DIVISOR = int(cfg.get("MINION_SIEGE_ATK_DIVISOR", "10"))
	MAX_HAND_SIZE           = int(cfg.get("MAX_HAND_SIZE", "7"))
	COST_RECOVERY           = int(cfg.get("COST_RECOVERY", "1"))
	CARD_DRAW_INTERVAL      = max(1, int(cfg.get("CARD_DRAW_INTERVAL", "1")))
	COST_RECOVERY_INTERVAL  = max(1, int(cfg.get("COST_RECOVERY_INTERVAL", "1")))
	PHASE_THRESHOLD         = int(cfg.get("PHASE_THRESHOLD", "8"))
	# Init counters so first event fires on turn 1
	_draw_counter = CARD_DRAW_INTERVAL - 1
	_cost_counter = COST_RECOVERY_INTERVAL - 1

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
	_hex_grid.set_disabled_cells(_field_loader.disabled_cells)
	_hex_grid.set_grid_bounds(_field_loader.min_cell, _field_loader.max_cell)


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
	return _hex_grid.hex_to_screen(pos.x, pos.y)


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
	_populate_from_data_loader()
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
	_card_phase.build_starter_decks()
	_gambit.refresh_gambit_ui()
	_lbl_gambit_status.text = "Click a pilot to select, then click a lane to assign."
	_panel_gambit.visible   = true
	_renderer.queue_redraw()
	_hud.update_hud()
