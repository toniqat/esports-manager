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
@onready var _prep:     Node                   = $MatchPrepController
@onready var _ban_pick: Node                   = $BanPickController
@onready var _assign:   Node                   = $AssignController
@onready var _jungle:   Node                   = $JungleStartController

var phase: int = GameEnums.MatchPhase.LOAD

# Loaded from DB at LOAD phase. Stays read-only after.
var all_players: Array = []   # Array[PlayerData]
var all_mechs:   Array = []   # Array[MechData]

# Team IDs to draft rosters for. Defaults are the standalone-MatchFlow case
# (player vs Team 1); when launched from Season we overwrite enemy_team_id
# from season_state.pending_match.
var player_team_id: int = 0
var enemy_team_id:  int = 1

# Filled by BanPickController.
var banned_mech_ids: Array      = []  # Array[int]
var player_picked_mech_ids: Array = []  # Array[int]
var enemy_picked_mech_ids: Array  = []  # Array[int]
var player_side: int             = GameEnums.DraftSide.BLUE


func _ready() -> void:
	gm.reset_match_ctx()
	# Season-driven match: read player/enemy team ids from pending_match. The
	# player team is the drafted team_id=0 (already updated by TeamDraft), the
	# enemy is whichever team the schedule paired us with.
	var pending = gm.season_state.get("pending_match", null) if gm.season_state.get("active", false) else null
	if pending != null:
		player_team_id = int(gm.season_state["player_team_id"])
		enemy_team_id  = int(pending["enemy_team_id"])
	if not _load_data():
		return

	# Mid-match resume path: title-screen "이어하기" landed here because the
	# slot was saved between BAN_PICK start and BattleSim launch. Skip ahead
	# to the saved phase. Consume the resume hint immediately so a subsequent
	# pre-ban-pick save (still fired below) writes the freshly-derived state.
	var resume = gm.season_state.get("match_resume", null) if gm.season_state.get("active", false) else null
	if typeof(resume) == TYPE_DICTIONARY:
		gm.season_state["match_resume"] = null
		var resume_phase: int = int((resume as Dictionary).get("phase", GameEnums.MatchPhase.BAN_PICK))
		if resume_phase == GameEnums.MatchPhase.LAUNCH:
			# Post-gambit snapshot — rebuild match_ctx from the resume payload
			# and jump straight to BattleSim. No UI needed.
			_resume_at_launch(resume)
			return
		# BAN_PICK resume: restore player_side and fall through to the normal
		# entry path (the pre-ban-pick save below will re-save with the same
		# player_side, idempotent).
		player_side = int((resume as Dictionary).get("player_side", GameEnums.DraftSide.BLUE))
	else:
		# Fresh entry — randomize sides.
		player_side = GameEnums.DraftSide.BLUE if randi() % 2 == 0 else GameEnums.DraftSide.RED

	# Wire signals
	_prep.phase_finished.connect(_on_prep_finished)
	_ban_pick.phase_finished.connect(_on_ban_pick_finished)
	_assign.phase_finished.connect(_on_assign_finished)
	_jungle.phase_finished.connect(_on_jungle_finished)

	# Resume entry skips PREP — the player already committed to the match
	# when the pre-ban-pick save fired.
	if typeof(resume) == TYPE_DICTIONARY:
		_enter_phase(GameEnums.MatchPhase.BAN_PICK)
		return

	# Fresh entry shows the prep dashboard first.
	_enter_phase(GameEnums.MatchPhase.PREP)


func _load_data() -> bool:
	# Season-driven match: reuse the already-mutated pilot pool (the draft
	# rewrites team_ids; reloading from DB would clobber that). Mechs still
	# come from the DB since they're never mutated post-load.
	var pending = gm.season_state.get("pending_match", null) if gm.season_state.get("active", false) else null
	if pending != null and (gm.season_state["all_pilots"] as Array).size() > 0:
		all_players = gm.season_state["all_pilots"]
		var mechs_only: Dictionary = gm.load_match_data()
		if mechs_only.has("error"):
			_show_error(mechs_only["error"])
			return false
		all_mechs = mechs_only["mechs"]
		print("MatchFlow: season mode — %d pilots from season_state, %d mechs" % [all_players.size(), all_mechs.size()])
		return true
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
		GameEnums.MatchPhase.PREP:
			var p_roster := _team_roster(player_team_id)
			var e_roster := _team_roster(enemy_team_id)
			var p_name: String = _team_name(player_team_id)
			var e_name: String = _team_name(enemy_team_id)
			_prep.enter(p_roster, e_roster, p_name, e_name)
		GameEnums.MatchPhase.BAN_PICK:
			_ban_pick.enter(all_mechs, player_side)
		GameEnums.MatchPhase.ASSIGN:
			# Resolve picked mech IDs into MechData objects
			var p_mechs := _ids_to_mechs(player_picked_mech_ids)
			var e_mechs := _ids_to_mechs(enemy_picked_mech_ids)
			var p_roster := _team_roster(player_team_id)
			var e_roster := _team_roster(enemy_team_id)
			_assign.enter(p_roster, p_mechs, e_roster, e_mechs)
		GameEnums.MatchPhase.JUNGLE_START:
			_jungle.enter()
		GameEnums.MatchPhase.LAUNCH:
			_launch_battle()


func _on_prep_finished(_result: Dictionary) -> void:
	# Player confirmed the match-up. Pre-ban-pick autosave fires here so a
	# resume from this slot drops back into BAN_PICK directly — PREP is
	# only shown on first-time entry. Skipped when running MatchFlow
	# standalone (no pending_match).
	if gm.season_state.get("active", false) and gm.season_state.get("pending_match", null) != null:
		gm.season_state["match_resume"] = {
			"phase":           GameEnums.MatchPhase.BAN_PICK,
			"player_side":     player_side,
			"banned_mech_ids": [],
			"player_picked_mech_ids": [],
			"enemy_picked_mech_ids":  [],
			"player_assigned_mech_ids": [],
			"enemy_assigned_mech_ids":  [],
			"jungle_start_dir": -1,
		}
		_autosave("pre_ban_pick")
	_enter_phase(GameEnums.MatchPhase.BAN_PICK)


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
	# Post-gambit autosave (trigger #3). All match state is locked in now —
	# capture mech IDs per role slot so resume can re-attach assigned_mech to
	# each PlayerData on its way back into BattleSim.
	if gm.season_state.get("active", false):
		var p_ids: Array = _roster_mech_ids(gm.match_ctx.get("player_roster", []))
		var e_ids: Array = _roster_mech_ids(gm.match_ctx.get("enemy_roster",  []))
		gm.season_state["match_resume"] = {
			"phase":           GameEnums.MatchPhase.LAUNCH,
			"player_side":     player_side,
			"banned_mech_ids": banned_mech_ids.duplicate(),
			"player_picked_mech_ids": player_picked_mech_ids.duplicate(),
			"enemy_picked_mech_ids":  enemy_picked_mech_ids.duplicate(),
			"player_assigned_mech_ids": p_ids,
			"enemy_assigned_mech_ids":  e_ids,
			"jungle_start_dir": int(result["dir"]),
		}
		_autosave("post_gambit")
	_enter_phase(GameEnums.MatchPhase.LAUNCH)


func _launch_battle() -> void:
	gm.match_ctx["active"]          = true
	gm.match_ctx["player_side"]     = player_side
	gm.match_ctx["banned_mech_ids"] = banned_mech_ids
	gm.match_ctx["all_mechs"]       = all_mechs
	get_tree().change_scene_to_file("res://scenes/BattleSim.tscn")


# Resume path for the post-gambit save: rebuild match_ctx from the resume
# payload and scene-change directly to BattleSim. Mirrors _on_assign_finished
# + _on_jungle_finished + _launch_battle without the UI controllers.
func _resume_at_launch(resume: Dictionary) -> void:
	player_side            = int(resume.get("player_side", GameEnums.DraftSide.BLUE))
	banned_mech_ids        = (resume.get("banned_mech_ids", []) as Array).duplicate()
	player_picked_mech_ids = (resume.get("player_picked_mech_ids", []) as Array).duplicate()
	enemy_picked_mech_ids  = (resume.get("enemy_picked_mech_ids", []) as Array).duplicate()

	var p_roster: Array = _team_roster(player_team_id)
	var e_roster: Array = _team_roster(enemy_team_id)
	var p_assigned: Array = resume.get("player_assigned_mech_ids", [])
	var e_assigned: Array = resume.get("enemy_assigned_mech_ids",  [])
	for i in range(min(5, p_roster.size(), p_assigned.size())):
		(p_roster[i] as PlayerData).assigned_mech = _find_mech(int(p_assigned[i]))
	for i in range(min(5, e_roster.size(), e_assigned.size())):
		(e_roster[i] as PlayerData).assigned_mech = _find_mech(int(e_assigned[i]))

	gm.match_ctx["player_roster"]    = p_roster
	gm.match_ctx["enemy_roster"]     = e_roster
	gm.match_ctx["jungle_start_dir"] = int(resume.get("jungle_start_dir", GameEnums.JungleStartDir.LEFT))
	_launch_battle()


# Extract the mech IDs from a role-sorted Array[PlayerData] (5 entries).
# Returns [] if the roster is malformed; safe defaults so a corrupt save
# won't crash on resume.
func _roster_mech_ids(roster: Array) -> Array:
	var out: Array = []
	for r in roster:
		var p := r as PlayerData
		if p == null or p.assigned_mech == null:
			out.append(-1)
		else:
			out.append(p.assigned_mech.id)
	return out


func _find_mech(id: int) -> MechData:
	for m_raw in all_mechs:
		var m := m_raw as MechData
		if m.id == id:
			return m
	return null


func _autosave(reason: String) -> void:
	var slot: int = int(gm.active_save_slot)
	if slot < 0:
		return
	var err: String = SaveSystem.save_slot(slot)
	if err != "":
		push_warning("MatchFlow: autosave (%s) failed — %s" % [reason, err])
	else:
		print("MatchFlow: autosave (%s) → slot %d" % [reason, slot])


# ── Helpers ──────────────────────────────────────────────────────────────────
func _team_roster(team_id: int) -> Array:
	# Returns 5 PlayerData objects sorted by role 0..4 for the given team.
	# League teams (id < 100) live in `all_players`; INTL teams (id >= 100)
	# live in season_state.intl_pilots — only relevant when launched from
	# Season into an INTL phase. Standalone MatchFlow only uses league teams.
	var pool: Array = all_players
	if team_id >= 100:
		pool = gm.season_state.get("intl_pilots", []) if gm.season_state.get("active", false) else []
	var out: Array = []
	for r in range(5):
		for p_raw in pool:
			var p := p_raw as PlayerData
			if p.team_id == team_id and p.role == r:
				out.append(p)
				break
	return out


func _team_name(team_id: int) -> String:
	# Pull from season_state.team_meta / intl_team_meta when running in season
	# mode. Standalone fallback returns "Team N" so the PREP screen still
	# renders when MatchFlow is launched directly from the editor.
	if gm.season_state.get("active", false):
		if team_id >= 100:
			var imeta: Array = gm.season_state.get("intl_team_meta", [])
			for t in imeta:
				if int(t.get("id", -1)) == team_id:
					return String(t["name"])
		else:
			var meta: Array = gm.season_state.get("team_meta", [])
			if team_id >= 0 and team_id < meta.size():
				return String(meta[team_id]["name"])
	return "Team %d" % team_id


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
