class_name MatchFlow
extends Node2D

# Top-level orchestrator for the pre-battle match flow:
#   LOAD -> BAN_PICK -> ASSIGN -> JUNGLE_START -> LAUNCH (change_scene to BattleSim)
#
# Each child controller (BanPickController, AssignController, JungleStartController)
# builds its own UI on enter() and emits phase_finished when done. MatchFlow
# advances the state machine and feeds GameManager.match_ctx.

signal phase_changed(new_phase: int)

@onready var gm: Node                          = get_node("/root/GameManager")
@onready var canvas: CanvasLayer               = $CanvasLayer
@onready var _ban_pick: Node                   = $BanPickController
@onready var _assign:   Node                   = $AssignController
@onready var _jungle:   Node                   = $JungleStartController

var phase: int = GameEnums.MatchPhase.LOAD

# Loaded from DB at LOAD phase. Stays read-only after.
var all_players: Array = []   # Array[PlayerData]
var all_mechs:   Array = []   # Array[MechData]

# Filled by BanPickController.
var banned_mech_ids: Array      = []  # Array[int]
var player_picked_mech_ids: Array = []  # Array[int]
var enemy_picked_mech_ids: Array  = []  # Array[int]
var player_side: int             = GameEnums.DraftSide.BLUE


func _ready() -> void:
	gm.reset_match_ctx()
	if not _load_data():
		return

	# Decide sides up front (random)
	player_side = GameEnums.DraftSide.BLUE if randi() % 2 == 0 else GameEnums.DraftSide.RED

	# Wire signals
	_ban_pick.phase_finished.connect(_on_ban_pick_finished)
	_assign.phase_finished.connect(_on_assign_finished)
	_jungle.phase_finished.connect(_on_jungle_finished)

	_enter_phase(GameEnums.MatchPhase.BAN_PICK)


func _load_data() -> bool:
	var result: Dictionary = gm.load_match_data()
	if result.has("error"):
		_show_error(result["error"])
		return false
	all_players = result["players"]
	all_mechs   = result["mechs"]
	print("MatchFlow: loaded %d players, %d mechs" % [all_players.size(), all_mechs.size()])
	return true


func _enter_phase(p: int) -> void:
	phase = p
	phase_changed.emit(p)
	match p:
		GameEnums.MatchPhase.BAN_PICK:
			_ban_pick.enter(all_mechs, player_side)
		GameEnums.MatchPhase.ASSIGN:
			# Resolve picked mech IDs into MechData objects
			var p_mechs := _ids_to_mechs(player_picked_mech_ids)
			var e_mechs := _ids_to_mechs(enemy_picked_mech_ids)
			var p_roster := _team_roster(0)
			var e_roster := _team_roster(1)
			_assign.enter(p_roster, p_mechs, e_roster, e_mechs)
		GameEnums.MatchPhase.JUNGLE_START:
			_jungle.enter()
		GameEnums.MatchPhase.LAUNCH:
			_launch_battle()


func _on_ban_pick_finished(result: Dictionary) -> void:
	banned_mech_ids        = result["banned"]
	player_picked_mech_ids = result["player_picks"]
	enemy_picked_mech_ids  = result["enemy_picks"]
	_enter_phase(GameEnums.MatchPhase.ASSIGN)


func _on_assign_finished(result: Dictionary) -> void:
	# AssignController has already mutated PlayerData.assigned_mech on each player.
	# Result echoes the rosters for clarity.
	gm.match_ctx["player_roster"] = result["player_roster"]
	gm.match_ctx["enemy_roster"]  = result["enemy_roster"]
	_enter_phase(GameEnums.MatchPhase.JUNGLE_START)


func _on_jungle_finished(result: Dictionary) -> void:
	gm.match_ctx["jungle_start_dir"] = result["dir"]
	_enter_phase(GameEnums.MatchPhase.LAUNCH)


func _launch_battle() -> void:
	gm.match_ctx["active"]          = true
	gm.match_ctx["player_side"]     = player_side
	gm.match_ctx["banned_mech_ids"] = banned_mech_ids
	gm.match_ctx["all_mechs"]       = all_mechs
	get_tree().change_scene_to_file("res://scenes/BattleSim.tscn")


# ── Helpers ──────────────────────────────────────────────────────────────────
func _team_roster(team_id: int) -> Array:
	# Returns 5 PlayerData objects sorted by role 0..4 for the given team.
	var out: Array = []
	for r in range(5):
		for p_raw in all_players:
			var p := p_raw as PlayerData
			if p.team_id == team_id and p.role == r:
				out.append(p)
				break
	return out


func _ids_to_mechs(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		for m_raw in all_mechs:
			var m := m_raw as MechData
			if m.id == int(id):
				out.append(m)
				break
	return out


func _show_error(msg: String) -> void:
	var lbl := Label.new()
	lbl.text = "MatchFlow load error\n\n" + msg + \
		"\n\nRun Project → Tools → Rebuild game.db then restart."
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(lbl)
