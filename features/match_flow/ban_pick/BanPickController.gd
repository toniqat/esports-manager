extends Node

# LoL international ban/pick: B-B-P-PP-PP-P-B-B-PP-PP
# Each side ends with 2 bans + 5 picks. Sides alternate per token.
# AI picks/bans are completely random among legal mechs.

signal phase_finished(result: Dictionary)

const _AI_THINK_SEC := 0.45

# Per-action sequence (14 entries). Each = [side, kind].
# kind: 0 = BAN, 1 = PICK
const ACTION_BAN  := 0
const ACTION_PICK := 1

const SEQUENCE: Array = [
	[GameEnums.DraftSide.BLUE, ACTION_BAN],   # 0
	[GameEnums.DraftSide.RED,  ACTION_BAN],   # 1
	[GameEnums.DraftSide.BLUE, ACTION_PICK],  # 2
	[GameEnums.DraftSide.RED,  ACTION_PICK],  # 3
	[GameEnums.DraftSide.RED,  ACTION_PICK],  # 4
	[GameEnums.DraftSide.BLUE, ACTION_PICK],  # 5
	[GameEnums.DraftSide.BLUE, ACTION_PICK],  # 6
	[GameEnums.DraftSide.RED,  ACTION_PICK],  # 7
	[GameEnums.DraftSide.BLUE, ACTION_BAN],   # 8
	[GameEnums.DraftSide.RED,  ACTION_BAN],   # 9
	[GameEnums.DraftSide.BLUE, ACTION_PICK],  # 10
	[GameEnums.DraftSide.BLUE, ACTION_PICK],  # 11
	[GameEnums.DraftSide.RED,  ACTION_PICK],  # 12
	[GameEnums.DraftSide.RED,  ACTION_PICK],  # 13
]

@onready var _mf: MatchFlow = get_parent() as MatchFlow

var _all_mechs: Array = []
var _player_side: int = GameEnums.DraftSide.BLUE
var _action_idx: int  = 0
var _banned: Array     = []  # Array[int]
var _blue_picks: Array = []  # Array[int]
var _red_picks: Array  = []

# UI
var _panel: Panel
var _mech_buttons: Dictionary = {}     # mech_id(int) → Button
var _seq_boxes: Array         = []     # Array[Panel] (14)
var _lbl_status: Label
var _lbl_blue_picks: Label
var _lbl_red_picks: Label
var _lbl_blue_bans: Label
var _lbl_red_bans: Label


func enter(all_mechs: Array, player_side: int) -> void:
	_all_mechs   = all_mechs
	_player_side = player_side
	_action_idx  = 0
	_banned.clear()
	_blue_picks.clear()
	_red_picks.clear()
	_build_ui()
	_refresh_ui()
	_maybe_run_ai()


# ── UI build ─────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.04, 0.10, 1.0)
	_panel.add_theme_stylebox_override("panel", bg)
	_mf.canvas.add_child(_panel)

	# Title
	UiHelpers.mk_label(_panel, "BAN / PICK PHASE", 46, Color(1.0, 0.85, 0.2),
			Vector2(0.0, 30.0), Vector2(1080.0, 60.0), HORIZONTAL_ALIGNMENT_CENTER)

	# Sequence indicator (14 boxes)
	for i in range(SEQUENCE.size()):
		var b := Panel.new()
		var sty := StyleBoxFlat.new()
		sty.bg_color     = _seq_color(i, 0)
		sty.border_color = Color(0.25, 0.25, 0.3)
		sty.border_width_left = 2; sty.border_width_right = 2
		sty.border_width_top = 2; sty.border_width_bottom = 2
		b.add_theme_stylebox_override("panel", sty)
		var box_w := 64.0; var gap := 6.0
		var total_w := SEQUENCE.size() * box_w + (SEQUENCE.size() - 1) * gap
		var start_x := (1080.0 - total_w) * 0.5
		b.position = Vector2(start_x + i * (box_w + gap), 110.0)
		b.size     = Vector2(box_w, 50.0)
		_panel.add_child(b)
		_seq_boxes.append(b)

		var l := Label.new()
		l.text = ("B" if SEQUENCE[i][1] == ACTION_BAN else "P")
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.position = Vector2(0.0, 0.0)
		l.size     = Vector2(box_w, 50.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		b.add_child(l)

	# Bans row labels (top of grid)
	_lbl_blue_bans = UiHelpers.mk_label(_panel, "Blue Bans:", 22, Color(0.55, 0.75, 1.0),
			Vector2(40.0, 180.0), Vector2(500.0, 30.0))
	_lbl_red_bans  = UiHelpers.mk_label(_panel, "Red Bans:", 22, Color(1.0, 0.55, 0.55),
			Vector2(540.0, 180.0), Vector2(500.0, 30.0), HORIZONTAL_ALIGNMENT_RIGHT)

	# Mech grid: 5 cols × 6 rows of MechData
	var grid_x0 := 28.0
	var grid_y0 := 230.0
	var card_w  := 200.0
	var card_h  := 150.0
	var gx      := 4.0
	var gy      := 8.0
	for i in range(_all_mechs.size()):
		var m := _all_mechs[i] as MechData
		var col: int = i % 5
		@warning_ignore("integer_division")
		var row: int = i / 5
		var btn := Button.new()
		btn.text = "%s\nHP %d  ATK %d" % [m.name, m.hp, m.atk]
		btn.add_theme_font_size_override("font_size", 18)
		btn.position = Vector2(grid_x0 + col * (card_w + gx), grid_y0 + row * (card_h + gy))
		btn.size     = Vector2(card_w, card_h)
		btn.pressed.connect(_on_mech_pressed.bind(m.id))
		_panel.add_child(btn)
		_mech_buttons[m.id] = btn

	# Pick rosters (under grid)
	var picks_y := grid_y0 + 6 * (card_h + gy) + 30.0
	_lbl_blue_picks = UiHelpers.mk_label(_panel, "Blue Picks: —", 24, Color(0.55, 0.75, 1.0),
			Vector2(40.0, picks_y), Vector2(500.0, 40.0))
	_lbl_red_picks  = UiHelpers.mk_label(_panel, "Red Picks: —", 24, Color(1.0, 0.55, 0.55),
			Vector2(540.0, picks_y), Vector2(500.0, 40.0), HORIZONTAL_ALIGNMENT_RIGHT)

	# Status / current action
	_lbl_status = UiHelpers.mk_label(_panel, "", 30, Color(1.0, 1.0, 0.9),
			Vector2(0.0, picks_y + 60.0), Vector2(1080.0, 50.0), HORIZONTAL_ALIGNMENT_CENTER)


# ── State refresh ────────────────────────────────────────────────────────────
func _refresh_ui() -> void:
	# Sequence boxes
	for i in range(SEQUENCE.size()):
		var b := _seq_boxes[i] as Panel
		var sty: StyleBoxFlat = b.get_theme_stylebox("panel") as StyleBoxFlat
		sty.bg_color = _seq_color(i, 1 if i < _action_idx else (2 if i == _action_idx else 0))
		sty.border_width_left = 4 if i == _action_idx else 2
		sty.border_width_right = 4 if i == _action_idx else 2
		sty.border_width_top = 4 if i == _action_idx else 2
		sty.border_width_bottom = 4 if i == _action_idx else 2

	# Mech buttons — disable banned/picked, color picks
	for id in _mech_buttons.keys():
		var btn := _mech_buttons[id] as Button
		var locked := false
		var modulate := Color(1, 1, 1)
		if int(id) in _banned:
			modulate = Color(0.35, 0.35, 0.4)
			locked = true
		elif int(id) in _blue_picks:
			modulate = Color(0.45, 0.65, 1.0)
			locked = true
		elif int(id) in _red_picks:
			modulate = Color(1.0, 0.5, 0.5)
			locked = true
		btn.modulate = modulate
		btn.disabled = locked or not _is_player_turn()

	# Bans summary
	_lbl_blue_bans.text = "Blue Bans: " + _names_for_side_actions(GameEnums.DraftSide.BLUE, ACTION_BAN)
	_lbl_red_bans.text  = "Red Bans: "  + _names_for_side_actions(GameEnums.DraftSide.RED,  ACTION_BAN)
	_lbl_blue_picks.text = "Blue Picks: " + _names_for_ids(_blue_picks)
	_lbl_red_picks.text  = "Red Picks: "  + _names_for_ids(_red_picks)

	# Status text
	if _action_idx >= SEQUENCE.size():
		_lbl_status.text = "Ban/Pick complete — proceeding…"
		return
	var cur: Array = SEQUENCE[_action_idx]
	var side_name := "Blue" if cur[0] == GameEnums.DraftSide.BLUE else "Red"
	var kind_name := "Ban" if cur[1] == ACTION_BAN else "Pick"
	var who := "YOU" if cur[0] == _player_side else "OPPONENT"
	_lbl_status.text = "%s %s — %s (%d / %d)" % [side_name, kind_name, who, _action_idx + 1, SEQUENCE.size()]


func _seq_color(idx: int, state: int) -> Color:
	# state: 0=upcoming, 1=done, 2=current
	var side: int = SEQUENCE[idx][0]
	var base := Color(0.2, 0.35, 0.7) if side == GameEnums.DraftSide.BLUE else Color(0.7, 0.25, 0.25)
	if state == 1: return base.darkened(0.5)
	if state == 2: return base.lightened(0.15)
	return base.darkened(0.7)


func _names_for_ids(ids: Array) -> String:
	if ids.is_empty(): return "—"
	var out: Array = []
	for id in ids:
		var m := _find_mech(int(id))
		if m != null: out.append(m.name)
	return ", ".join(out)


func _names_for_side_actions(side: int, kind: int) -> String:
	# Walk SEQUENCE up to _action_idx, collect _banned in order matched to side.
	var out: Array = []
	var ban_idx := 0
	for i in range(min(_action_idx, SEQUENCE.size())):
		var s: Array = SEQUENCE[i]
		if s[1] != kind:
			# advance only matching kind cursor — but bans/picks share separate arrays
			continue
		if kind == ACTION_BAN:
			# Banned array stores in chronological action order; pull i'th ban
			if ban_idx < _banned.size() and s[0] == side:
				var m := _find_mech(int(_banned[ban_idx]))
				if m != null: out.append(m.name)
			ban_idx += 1
	if out.is_empty(): return "—"
	return ", ".join(out)


# ── Click handling ───────────────────────────────────────────────────────────
func _on_mech_pressed(mech_id: int) -> void:
	if not _is_player_turn():
		return
	if not _is_legal(mech_id):
		return
	_commit_action(mech_id)


func _is_player_turn() -> bool:
	if _action_idx >= SEQUENCE.size(): return false
	return SEQUENCE[_action_idx][0] == _player_side


func _is_legal(mech_id: int) -> bool:
	return not (int(mech_id) in _banned) \
		and not (int(mech_id) in _blue_picks) \
		and not (int(mech_id) in _red_picks)


func _commit_action(mech_id: int) -> void:
	var cur: Array = SEQUENCE[_action_idx]
	if cur[1] == ACTION_BAN:
		_banned.append(int(mech_id))
	elif cur[0] == GameEnums.DraftSide.BLUE:
		_blue_picks.append(int(mech_id))
	else:
		_red_picks.append(int(mech_id))
	_action_idx += 1
	_refresh_ui()
	if _action_idx >= SEQUENCE.size():
		_finish()
	else:
		_maybe_run_ai()


func _maybe_run_ai() -> void:
	if _action_idx >= SEQUENCE.size():
		return
	if _is_player_turn():
		return
	# AI turn — pick a random legal mech after a short delay
	await get_tree().create_timer(_AI_THINK_SEC).timeout
	if _action_idx >= SEQUENCE.size():
		return
	var legal: Array = []
	for m_raw in _all_mechs:
		var m := m_raw as MechData
		if _is_legal(m.id): legal.append(m)
	if legal.is_empty():
		push_error("BanPickController: no legal mechs left for AI")
		return
	var pick := legal[randi() % legal.size()] as MechData
	_commit_action(pick.id)


func _finish() -> void:
	var player_picks: Array = _blue_picks.duplicate() if _player_side == GameEnums.DraftSide.BLUE else _red_picks.duplicate()
	var enemy_picks: Array  = _red_picks.duplicate()  if _player_side == GameEnums.DraftSide.BLUE else _blue_picks.duplicate()
	_panel.queue_free()
	_panel = null
	_mech_buttons.clear()
	_seq_boxes.clear()
	phase_finished.emit({
		"banned": _banned.duplicate(),
		"player_picks": player_picks,
		"enemy_picks": enemy_picks,
	})


# ── Helpers ──────────────────────────────────────────────────────────────────
func _find_mech(id: int) -> MechData:
	for m_raw in _all_mechs:
		var m := m_raw as MechData
		if m.id == id: return m
	return null


